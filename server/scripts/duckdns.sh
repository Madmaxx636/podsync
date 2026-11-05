#!/usr/bin/env bash
# Keeps a DuckDNS name pointed at this network's public IP (skip if your router or another
# updater already does that). `--cron` runs it every 5 minutes.
#   DUCKDNS_DOMAIN=yourname DUCKDNS_TOKEN=xxxx ./scripts/duckdns.sh [--cron]
set -euo pipefail
: "${DUCKDNS_DOMAIN:?set DUCKDNS_DOMAIN (the part before .duckdns.org)}"
: "${DUCKDNS_TOKEN:?set DUCKDNS_TOKEN}"
if [ "${1:-}" = "--cron" ]; then
  line="*/5 * * * * DUCKDNS_DOMAIN=$DUCKDNS_DOMAIN DUCKDNS_TOKEN=$DUCKDNS_TOKEN $(cd "$(dirname "$0")" && pwd)/duckdns.sh >/dev/null 2>&1"
  ( crontab -l 2>/dev/null | grep -vF "duckdns.sh"; echo "$line" ) | crontab -
  echo "Scheduled every 5 minutes."; exit 0
fi
curl -fs "https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" ; echo
