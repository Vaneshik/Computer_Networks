#!/bin/sh
set -e

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Create NAT masquerade table
nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }

# Masquerade INT traffic going out to internet (eth0 = clab mgmt, has real internet)
nft add rule ip nat postrouting oifname eth0 masquerade

# Also masquerade traffic going to br-uplink (for coredns-pub → 8.8.8.8 via nat-gw)
nft add rule ip nat postrouting oifname eth1 masquerade

echo "[nat-gw] NAT rules applied"
