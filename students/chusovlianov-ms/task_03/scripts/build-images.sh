#!/usr/bin/env bash
# Build local Docker images that embed iproute2 / tools missing in upstream images.
# Run once; re-run only if Dockerfiles change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="$SCRIPT_DIR/../images"

echo "==> Building local/client-tools:3.19"
docker build -t local/client-tools:3.19 "$IMAGES_DIR/client"

echo "==> Building local/coredns-ip:1.11.1"
docker build -t local/coredns-ip:1.11.1 "$IMAGES_DIR/coredns"

echo "==> Building local/oauth2-proxy-ip:v7.6.0"
docker build -t local/oauth2-proxy-ip:v7.6.0 "$IMAGES_DIR/oauth2-proxy"

echo "==> Building local/keycloak-ip:24.0"
docker build -t local/keycloak-ip:24.0 "$IMAGES_DIR/keycloak"

echo ""
echo "Built images:"
docker image ls --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" \
  | grep -E "local/(client-tools|coredns-ip|oauth2-proxy-ip|keycloak-ip)"
