#!/bin/sh
set -eu

echo "[teleport] waiting for eth1..."
while ! busybox ip link show eth1 >/dev/null 2>&1; do
  sleep 1
done

echo "[teleport] waiting for IP 10.3.0.60..."
while ! busybox ip addr show eth1 | grep -q '10.3.0.60'; do
  sleep 1
done

echo "[teleport] preparing shell environment..."

# Allow Teleport SSH sessions as root.
sed -i 's#^root:x:0:0:root:/root:/sbin/nologin#root:x:0:0:root:/root:/busybox/sh#' /etc/passwd || true

# Provide common commands for interactive sessions in distroless-debug image.
mkdir -p /bin
for app in sh ls cat echo id whoami pwd uname ps env sleep grep sed awk vi date touch mkdir rm cp mv; do
  ln -sf /busybox/busybox /bin/$app 2>/dev/null || true
done

export PATH="/bin:/busybox:/usr/local/bin:$PATH"

mkdir -p /var/lib/teleport

echo "[teleport] starting teleport..."
teleport start --config=/etc/teleport.yaml &
TPID=$!

echo "[teleport] Waiting for auth service to initialize..."
READY=0
for i in $(seq 1 60); do
    if ! kill -0 "$TPID" 2>/dev/null; then
        echo "[teleport] teleport process exited early"
        wait "$TPID"
        exit 1
    fi

    if teleport status --config=/etc/teleport.yaml 2>/dev/null | grep -q "Cluster"; then
        READY=1
        break
    fi

    sleep 2
done

if [ "$READY" = "1" ]; then
    if ! tctl --config=/etc/teleport.yaml users ls 2>/dev/null | grep -q "^admin"; then
        echo "[teleport] Creating admin user..."
        tctl --config=/etc/teleport.yaml users add admin \
            --roles=access,editor \
            --logins=root \
            2>&1 | tee /var/lib/teleport/admin-invite.txt || true
        echo "[teleport] Invite URL saved to /var/lib/teleport/admin-invite.txt"
    fi
else
    echo "[teleport] auth service did not become ready in time"
fi

echo "[teleport] Ready. Web UI: http://10.3.0.60:3080"
wait "$TPID"
