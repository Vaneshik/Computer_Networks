#!/bin/sh
set -eu

echo "[oauth2-proxy] waiting for eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do
  sleep 1
done

echo "[oauth2-proxy] waiting for IP 10.3.0.40..."
while ! ip addr show eth1 | grep -q '10.3.0.40'; do
  sleep 1
done

echo "[oauth2-proxy] waiting for Keycloak..."
until curl -fsS --max-time 2 http://10.3.0.50:8080/realms/itmo/.well-known/openid-configuration >/dev/null; do
  sleep 2
done

echo "[oauth2-proxy] starting oauth2-proxy"
exec /bin/oauth2-proxy --config=/etc/oauth2-proxy.cfg
