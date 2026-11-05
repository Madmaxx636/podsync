#!/usr/bin/env bash
# Opens or closes self-registration. Close it once everyone has an account, especially on the internet.
#   ./scripts/signup.sh off | on [--no-restart]
# The choice is kept in .env; --no-restart only records it (for use before the first start).
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in on) v=true;; off) v=false;; *) echo "usage: $0 on|off [--no-restart]"; exit 1;; esac
{ grep -v '^PODSYNC_SIGNUP=' .env 2>/dev/null || true; echo "PODSYNC_SIGNUP=$v"; } > .env.new && mv .env.new .env
[ "${2:-}" = "--no-restart" ] || docker compose up -d
echo "Self-registration is now $1."
