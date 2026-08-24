#!/usr/bin/env bash
# Fixed local deployment values intentionally expand before SSH execution.
# shellcheck disable=SC2029
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_ALIAS="homeserver"
DEPLOY_DIR="android-bridge-relay"
IMAGE="android-bridge-relay:1.0.0"
CONTAINER="android-bridge-relay"
DOMAIN="relay.homeserver"
PORT="8080"
NETWORK="system_default"
CLEAN_VOLUME=false

usage() {
  echo "Usage: $0 [--clean-volume]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-volume) CLEAN_VOLUME=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v docker >/dev/null || { echo "Docker is not installed locally." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running locally." >&2; exit 1; }
ssh "$SSH_ALIAS" "echo ok" >/dev/null 2>&1 || { echo "Cannot connect through SSH alias '$SSH_ALIAS'." >&2; exit 1; }

REMOTE_ARCH="$(ssh "$SSH_ALIAS" uname -m)"
case "$REMOTE_ARCH" in
  x86_64) PLATFORM="linux/amd64" ;;
  aarch64) PLATFORM="linux/arm64" ;;
  *) echo "Unsupported homeserver architecture: $REMOTE_ARCH" >&2; exit 1 ;;
esac

ssh "$SSH_ALIAS" "docker info >/dev/null && docker network inspect '$NETWORK' >/dev/null" || {
  echo "Homeserver Docker or '$NETWORK' is unavailable. Start Nginx Proxy Manager first." >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
EXISTING_SETUP_CODE=""
if [ "$CLEAN_VOLUME" = "false" ]; then
  EXISTING_SETUP_CODE="$(ssh "$SSH_ALIAS" "test -f '$DEPLOY_DIR/.env' && sed -n 's/^RELAY_SETUP_CODE=//p' '$DEPLOY_DIR/.env'" || true)"
fi
SETUP_CODE="${RELAY_SETUP_CODE:-${EXISTING_SETUP_CODE:-$(openssl rand -base64 32 | tr -d '\n')}}"

echo "Building $IMAGE for $PLATFORM"
docker build --platform "$PLATFORM" -t "$IMAGE" "$ROOT_DIR"
docker save "$IMAGE" | gzip > "$TMP_DIR/android-bridge-relay.tar.gz"

mkdir -p "$TMP_DIR/package/deployments/homeserver"
cp "$ROOT_DIR/docker-compose.homeserver.yml" "$TMP_DIR/package/docker-compose.yml"
cp "$ROOT_DIR/deployments/homeserver/env.homeserver" "$TMP_DIR/package/deployments/homeserver/env.homeserver"
printf 'RELAY_SETUP_CODE=%s\n' "$SETUP_CODE" > "$TMP_DIR/package/.env"

ssh "$SSH_ALIAS" "mkdir -p '$DEPLOY_DIR/deployments/homeserver'"
scp -q "$TMP_DIR/package/docker-compose.yml" "$TMP_DIR/package/.env" "$SSH_ALIAS:$DEPLOY_DIR/"
scp -q "$TMP_DIR/package/deployments/homeserver/env.homeserver" \
  "$SSH_ALIAS:$DEPLOY_DIR/deployments/homeserver/env.homeserver"

# Local expansion intentionally injects generated values into the remote script.
# shellcheck disable=SC2087
ssh "$SSH_ALIAS" bash <<REMOTE_PREPARE
set -euo pipefail
cd $DEPLOY_DIR
if [ "$CLEAN_VOLUME" = "true" ]; then
  docker compose down --remove-orphans --volumes 2>/dev/null || true
else
  docker compose down --remove-orphans 2>/dev/null || true
fi
docker image prune -af >/dev/null 2>&1 || true
REMOTE_PREPARE

scp -q "$TMP_DIR/android-bridge-relay.tar.gz" "$SSH_ALIAS:$DEPLOY_DIR/android-bridge-relay.tar.gz"
ssh "$SSH_ALIAS" "docker load -i '$DEPLOY_DIR/android-bridge-relay.tar.gz' && rm -f '$DEPLOY_DIR/android-bridge-relay.tar.gz'"
ssh "$SSH_ALIAS" "cd '$DEPLOY_DIR' && docker compose up -d"

# Local expansion intentionally injects the fixed deployment path into the remote script.
# shellcheck disable=SC2087
ssh "$SSH_ALIAS" bash <<REMOTE_HEALTH
set -euo pipefail
for attempt in \$(seq 1 60); do
  if docker exec "$CONTAINER" wget -q -O /dev/null "http://127.0.0.1:$PORT/health"; then
    exit 0
  fi
  sleep 2
done
echo "Relay health check timed out after 120 seconds." >&2
exit 1
REMOTE_HEALTH

cat <<SUMMARY
Deployment complete.
One-time setup code: $SETUP_CODE
Store this code privately. It expires after first use or RELAY_SETUP_TTL_SECONDS.
A non-clean redeploy preserves this code and its original expiry. Use --clean-volume before enrollment to rotate it.

NPM configuration:
  Domain:           $DOMAIN
  Scheme:           http
  Forward Hostname: $CONTAINER
  Forward Port:     $PORT
  Websockets:       ON
SUMMARY
