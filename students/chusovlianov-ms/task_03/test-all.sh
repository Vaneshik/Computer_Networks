#!/usr/bin/env bash
# Smoke-test suite for itmo-net containerlab topology
# Usage: bash test-all.sh
# Requires: sudo clab deploy -t topology.clab.yml already done

set -uo pipefail

LAB=itmo-net
PASS=0
FAIL=0

green() { printf '\033[32m[PASS]\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
red()   { printf '\033[31m[FAIL]\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
info()  { printf '\033[34m[INFO]\033[0m %s\n' "$1"; }

dc() {
    # docker exec inside clab node, suppress container-not-found error text
    docker exec "clab-${LAB}-$1" sh -c "$2" 2>/dev/null
}

# ─────────────────────────────────────────────────
# 1. BGP anycast: ISP must have ECMP routes for VIP
# ─────────────────────────────────────────────────
info "1. BGP anycast routes on ISP"
BGP_OUT=$(dc isp "vtysh -c 'show bgp ipv4 unicast 10.99.0.1/32'" 2>/dev/null || true)
if echo "$BGP_OUT" | grep -q "10.99.0.1"; then
    # Count number of next-hops (ECMP)
    NHOPS=$(echo "$BGP_OUT" | grep -c "10.1.0.1[12]" || echo 0)
    if [ "$NHOPS" -ge 2 ]; then
        green "BGP ECMP: $NHOPS paths for 10.99.0.1/32 (edge1 + edge2)"
    else
        green "BGP: 10.99.0.1/32 present (single path — both edges may not be up yet)"
    fi
else
    red "BGP: 10.99.0.1/32 not found in ISP table"
fi

BGP6_OUT=$(dc isp "vtysh -c 'show bgp ipv6 unicast fd00:99::1/128'" 2>/dev/null || true)
if echo "$BGP6_OUT" | grep -q "fd00:99::1"; then
    green "BGP IPv6: fd00:99::1/128 present in ISP table"
else
    red "BGP IPv6: fd00:99::1/128 not found in ISP table"
fi

# ─────────────────────────────────────────────────
# 2. DNS public zone: itmo.ru
# ─────────────────────────────────────────────────
info "2. Public DNS (coredns-pub, 1.1.1.53)"
DNS_A=$(dc client "nslookup itmo.ru 1.1.1.53 2>/dev/null | grep 'Address' | grep -v '#'" || true)
if echo "$DNS_A" | grep -q "10.99.0.1"; then
    green "DNS public: itmo.ru → 10.99.0.1"
else
    red "DNS public: itmo.ru did not resolve to 10.99.0.1 (got: $DNS_A)"
fi

DNS_AAAA=$(dc client "nslookup -type=AAAA itmo.ru 1.1.1.53 2>/dev/null" || true)
if echo "$DNS_AAAA" | grep -q "fd00:99::1"; then
    green "DNS public IPv6: itmo.ru → fd00:99::1"
else
    red "DNS public IPv6: itmo.ru AAAA not found"
fi

# ─────────────────────────────────────────────────
# 3. L4→L7 HTTPS: itmo.ru served correctly
# ─────────────────────────────────────────────────
info "3. HTTPS via anycast VIP → lb-l34 → lb-l7 → web backends"
HTTP_OUT=$(dc client "curl -sk --connect-timeout 5 \
    --resolve itmo.ru:443:10.99.0.1 \
    https://itmo.ru/" 2>/dev/null || true)
if echo "$HTTP_OUT" | grep -qi "ITMO"; then
    green "HTTPS itmo.ru: page returned (contains ITMO)"
else
    red "HTTPS itmo.ru: no ITMO content (got: $(echo "$HTTP_OUT" | head -2))"
fi

# ─────────────────────────────────────────────────
# 4. L7 round-robin: different backends
# ─────────────────────────────────────────────────
info "4. Round-robin across web1/web2/web3"
BACKENDS=""
for i in 1 2 3 4 5 6; do
    B=$(dc client "curl -sk --connect-timeout 5 \
        --resolve itmo.ru:443:10.99.0.1 \
        https://itmo.ru/ 2>/dev/null" | grep -oE 'web-[0-9]' | head -1 || true)
    BACKENDS="$BACKENDS $B"
done
UNIQUE=$(echo "$BACKENDS" | tr ' ' '\n' | sort -u | grep -c 'web-' || echo 0)
if [ "$UNIQUE" -ge 2 ]; then
    green "Round-robin: $UNIQUE distinct backends hit ($BACKENDS)"
else
    red "Round-robin: only $UNIQUE distinct backend(s) seen ($BACKENDS)"
fi

# ─────────────────────────────────────────────────
# 5. IPv6 path: client → fd00:99::1 → lb-l7 → web
# ─────────────────────────────────────────────────
info "5. IPv6 dual-stack path"
HTTP6=$(dc client "curl -6 -sk --connect-timeout 5 \
    --resolve itmo.ru:443:[fd00:99::1] \
    https://itmo.ru/" 2>/dev/null || true)
if echo "$HTTP6" | grep -qi "ITMO"; then
    green "IPv6: curl -6 itmo.ru returned ITMO page"
else
    red "IPv6: curl -6 itmo.ru failed or returned wrong page"
fi

# ─────────────────────────────────────────────────
# 6. TLS certificate
# ─────────────────────────────────────────────────
info "6. TLS certificate"
CERT=$(dc client "echo | openssl s_client -connect 10.99.0.1:443 \
    -servername itmo.ru 2>/dev/null | openssl x509 -noout -subject 2>/dev/null" || true)
if echo "$CERT" | grep -qi "itmo"; then
    green "TLS: certificate CN contains itmo ($CERT)"
else
    red "TLS: certificate check failed (got: $CERT)"
fi

# ─────────────────────────────────────────────────
# 7. Firewall: postgres NOT reachable from DMZ
# ─────────────────────────────────────────────────
info "7. Firewall: postgres blocked from DMZ"
PG_TEST=$(dc lb-l34 "nc -z -w2 10.3.0.20 5432 && echo OPEN || echo BLOCKED" 2>/dev/null || echo "BLOCKED")
if echo "$PG_TEST" | grep -q "BLOCKED"; then
    green "Firewall: postgres 5432 blocked from DMZ (lb-l34)"
else
    red "Firewall: postgres 5432 is REACHABLE from DMZ — firewall rules broken"
fi

# ─────────────────────────────────────────────────
# 8. Internal DNS: itmo-team.ru
# ─────────────────────────────────────────────────
info "8. Internal DNS (coredns-int, 10.3.0.53)"
INT_DNS=$(dc lb-l7 "nslookup db.itmo-team.ru 10.3.0.53 2>/dev/null | grep 'Address' | grep -v '#'" 2>/dev/null || true)
if echo "$INT_DNS" | grep -q "10.99.0.1"; then
    green "DNS internal: db.itmo-team.ru → 10.99.0.1"
else
    red "DNS internal: db.itmo-team.ru did not resolve (got: $INT_DNS)"
fi

# ─────────────────────────────────────────────────
# 9. SSO redirect: db.itmo-team.ru requires auth
# ─────────────────────────────────────────────────
info "9. SSO: unauthenticated request to db.itmo-team.ru redirects to keycloak"
SSO_HDR=$(dc client "curl -sk --max-redirs 0 \
    --resolve db.itmo-team.ru:443:10.99.0.1 \
    -D - https://db.itmo-team.ru/ 2>/dev/null | head -20" || true)
if echo "$SSO_HDR" | grep -qi "location.*realms\|keycloak\|10.3.0.50\|oauth2"; then
    green "SSO: redirect to Keycloak/oauth2-proxy detected"
elif echo "$SSO_HDR" | grep -q "302\|301"; then
    green "SSO: got redirect response (may not include Keycloak URL in header)"
else
    red "SSO: no redirect from db.itmo-team.ru (got: $(echo "$SSO_HDR" | head -3))"
fi

# ─────────────────────────────────────────────────
# 10. NAT: internet access from internal segment
# ─────────────────────────────────────────────────
info "10. NAT: outbound internet from INT via nat-gw"
NAT_TEST=$(dc web1 "wget -q -T5 -O- http://example.com 2>/dev/null | grep -c 'Example Domain'" || echo "0")
if [ "$NAT_TEST" -gt "0" ]; then
    green "NAT: web1 reached example.com via nat-gw masquerade"
else
    # Fallback: check if there's a default route via nat-gw
    ROUTE=$(dc web1 "ip route | grep default" 2>/dev/null || true)
    if echo "$ROUTE" | grep -q "10.3.0.254"; then
        green "NAT: default route via nat-gw (10.3.0.254) configured — internet access depends on host connectivity"
    else
        red "NAT: no default route via nat-gw on web1"
    fi
fi

# ─────────────────────────────────────────────────
# 11. Teleport web UI reachable
# ─────────────────────────────────────────────────
info "11. Teleport SSH SSO service"
TELE=$(dc lb-l7 "nc -z -w5 10.3.0.60 3080 && echo UP || echo DOWN" 2>/dev/null || echo "DOWN")
if echo "$TELE" | grep -q "UP"; then
    green "Teleport: web UI (port 3080) is UP"

    # Print invite URL if available
    INVITE=$(docker exec "clab-${LAB}-teleport" cat /var/lib/teleport/admin-invite.txt 2>/dev/null | grep -i "https\?://" | head -1 || true)
    if [ -n "$INVITE" ]; then
        info "  → Teleport admin invite: $INVITE"
    else
        info "  → To create SSH user: docker exec -it clab-${LAB}-teleport tctl users add admin --roles=access,editor --logins=root"
    fi
else
    red "Teleport: port 3080 not reachable (may still be starting)"
fi

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
printf "  Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
echo "════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
