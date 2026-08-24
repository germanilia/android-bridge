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
NPM_CONTAINER="nginx-proxy-manager"
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

ssh "$SSH_ALIAS" "docker info >/dev/null && docker network inspect '$NETWORK' >/dev/null && docker inspect '$NPM_CONTAINER' >/dev/null" || {
  echo "Homeserver Docker, '$NETWORK', or '$NPM_CONTAINER' is unavailable. Start Nginx Proxy Manager first." >&2
  exit 1
}

TAILSCALE_DOMAIN="$(ssh "$SSH_ALIAS" "tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"Self\"][\"DNSName\"].rstrip(\".\"))'")"
if [[ ! "$TAILSCALE_DOMAIN" =~ ^[a-z0-9][a-z0-9.-]*\.ts\.net$ ]]; then
  echo "Homeserver does not report a valid Tailscale HTTPS domain." >&2
  exit 1
fi

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
cat > "$TMP_DIR/package/relay-nginx.conf" <<NGINX
# BEGIN ANDROID_BRIDGE_RELAY
server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name $TAILSCALE_DOMAIN;

  ssl_certificate /data/tls/android-bridge-relay/cert.pem;
  ssl_certificate_key /data/tls/android-bridge-relay/key.pem;
  ssl_protocols TLSv1.2 TLSv1.3;

  access_log /data/logs/android-bridge-relay_access.log proxy;
  error_log /data/logs/android-bridge-relay_error.log warn;
  client_max_body_size 2m;

  location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_http_version 1.1;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_pass http://$CONTAINER:$PORT;
  }
}
# END ANDROID_BRIDGE_RELAY
NGINX

ssh "$SSH_ALIAS" "mkdir -p '$DEPLOY_DIR/deployments/homeserver'"
scp -q "$TMP_DIR/package/docker-compose.yml" "$TMP_DIR/package/.env" "$SSH_ALIAS:$DEPLOY_DIR/"
scp -q "$TMP_DIR/package/deployments/homeserver/env.homeserver" \
  "$SSH_ALIAS:$DEPLOY_DIR/deployments/homeserver/env.homeserver"
scp -q "$TMP_DIR/package/relay-nginx.conf" "$SSH_ALIAS:$DEPLOY_DIR/relay-nginx.conf"

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

ssh "$SSH_ALIAS" "set -e; umask 077; mkdir -p '$DEPLOY_DIR/tls'; tailscale cert --min-validity=720h --cert-file '$DEPLOY_DIR/tls/cert.pem' --key-file '$DEPLOY_DIR/tls/key.pem' '$TAILSCALE_DOMAIN' >/dev/null; docker exec '$NPM_CONTAINER' mkdir -p /data/tls/android-bridge-relay; docker cp '$DEPLOY_DIR/tls/cert.pem' '$NPM_CONTAINER:/data/tls/android-bridge-relay/cert.pem'; docker cp '$DEPLOY_DIR/tls/key.pem' '$NPM_CONTAINER:/data/tls/android-bridge-relay/key.pem'; docker cp '$DEPLOY_DIR/relay-nginx.conf' '$NPM_CONTAINER:/tmp/android-bridge-relay.conf'"

# Replace only the managed relay block and preserve other NPM custom configuration.
# shellcheck disable=SC2087
ssh "$SSH_ALIAS" bash <<REMOTE_NPM
set -euo pipefail
docker exec "$NPM_CONTAINER" sh -eu -c '
config=/data/nginx/custom/http.conf
backup=\$(mktemp)
candidate=\$(mktemp)
cp "\$config" "\$backup"
awk '\''
  \$0 == "# BEGIN ANDROID_BRIDGE_RELAY" { skip=1; next }
  \$0 == "# END ANDROID_BRIDGE_RELAY" { skip=0; next }
  !skip { print }
'\'' "\$config" > "\$candidate"
printf "\\n" >> "\$candidate"
cat /tmp/android-bridge-relay.conf >> "\$candidate"
cat "\$candidate" > "\$config"
if ! nginx -t; then
  cat "\$backup" > "\$config"
  exit 1
fi
if ! nginx -s reload; then
  cat "\$backup" > "\$config"
  nginx -s reload
  exit 1
fi
rm -f "\$backup" "\$candidate" /tmp/android-bridge-relay.conf
'
REMOTE_NPM

cat <<SUMMARY
Deployment complete.
One-time setup code: $SETUP_CODE
Store this code privately. It expires after first use or RELAY_SETUP_TTL_SECONDS.
A non-clean redeploy preserves this code and its original expiry. Use --clean-volume before enrollment to rotate it.

Private Tailscale endpoints:
  Mac:     https://$TAILSCALE_DOMAIN
  Android: wss://$TAILSCALE_DOMAIN

NPM routes trusted Tailscale HTTPS to $CONTAINER:$PORT with WebSockets enabled.
SUMMARY
