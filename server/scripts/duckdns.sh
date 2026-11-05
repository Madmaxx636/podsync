#!/usr/bin/env bash
# Keeps a DuckDNS name pointed at this network's public IP (skip if your router or another
# updater already does that). The name and token come from the environment or from
# scripts/duckdns.env (written by setup.sh, readable only by you).
#   ./scripts/duckdns.sh [--cron]     --cron runs it every 5 minutes
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$here/duckdns.env" ] && . "$here/duckdns.env"
: "${DUCKDNS_DOMAIN:?set DUCKDNS_DOMAIN (the part before .duckdns.org)}"
: "${DUCKDNS_TOKEN:?set DUCKDNS_TOKEN}"
if [ "${1:-}" = "--cron" ]; then
  umask 077
  printf 'DUCKDNS_DOMAIN=%s\nDUCKDNS_TOKEN=%s\n' "$DUCKDNS_DOMAIN" "$DUCKDNS_TOKEN" > "$here/duckdns.env"
  line="*/5 * * * * $here/duckdns.sh >/dev/null 2>&1"
  ( crontab -l 2>/dev/null | grep -vF "duckdns.sh"; echo "$line" ) | crontab -
  echo "Scheduled every 5 minutes."; exit 0
fi
# An empty ip= makes DuckDNS use the address the request comes from.
curl -fsS "${DUCKDNS_API:-https://www.duckdns.org}/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" ; echo
