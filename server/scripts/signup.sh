#!/usr/bin/env bash
# Opens or closes self-registration. Close it once everyone has an account, especially on the internet.
#   ./scripts/signup.sh off | on
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in on) v=true;; off) v=false;; *) echo "usage: $0 on|off"; exit 1;; esac
sed -i "s/PODSYNC_SIGNUP: \"[a-z]*\"/PODSYNC_SIGNUP: \"$v\"/" docker-compose.yml
docker compose up -d
echo "Self-registration is now $1."
