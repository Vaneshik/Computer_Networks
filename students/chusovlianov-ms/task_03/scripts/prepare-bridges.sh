#!/usr/bin/env bash
# Create Linux bridge interfaces required by ContainerLab topology.
# Must be run before every `clab deploy` — bridges disappear after `wsl --shutdown`.
set -euo pipefail

for br in br-uplink br-edge br-dmz br-int; do
  if ip link show "$br" >/dev/null 2>&1; then
    echo "[ok]   $br already exists"
  else
    sudo ip link add "$br" type bridge
    echo "[created] $br"
  fi
  sudo ip link set "$br" up
done

echo ""
ip link show type bridge | grep -E "^[0-9]+: br-" | awk '{print "[up]  "$2}'
