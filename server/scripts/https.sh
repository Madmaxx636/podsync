#!/usr/bin/env bash
# Puts Caddy in front of PodSync for HTTPS with an automatic certificate, and tells the server to
# trust it. Needs: your name pointing at this network, and router ports 80 and 443 forwarded to
# this machine.
#   ./scripts/https.sh yourname.duckdns.org you@example.com
set -euo pipefail
cd "$(dirname "$0")/.."
domain="${1:?usage: $0 DOMAIN EMAIL}"; email="${2:?usage: $0 DOMAIN EMAIL}"
cat > docker-compose.https.yml <<EOF
# Adds HTTPS: docker compose -f docker-compose.yml -f docker-compose.https.yml up -d
services:
  podsync:
    ports: !override []
    expose: ["8080"]
    environment:
      PODSYNC_TRUST_PROXY: "true"
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
volumes:
  caddy-data:
EOF
cat > Caddyfile <<EOF
{
    email $email
}
$domain {
    reverse_proxy podsync:8080
}
EOF
# Every later `docker compose` command in this folder now includes the HTTPS part automatically.
{ grep -v '^COMPOSE_FILE=' .env 2>/dev/null || true; echo "COMPOSE_FILE=docker-compose.yml:docker-compose.https.yml"; } > .env.new && mv .env.new .env
docker compose up -d
echo "Give it a minute for the certificate, then use https://$domain in the app."
