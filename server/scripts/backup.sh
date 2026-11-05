#!/usr/bin/env bash
# Takes a consistent copy of the database while the server runs, into ./backups, and keeps the
# newest 14. `--cron` installs a daily 03:30 job for you.
#   ./scripts/backup.sh [--cron]
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--cron" ]; then
  line="30 3 * * * cd $(pwd) && ./scripts/backup.sh >/dev/null 2>&1"
  ( crontab -l 2>/dev/null | grep -vF "scripts/backup.sh"; echo "$line" ) | crontab -
  echo "Scheduled: $line"; exit 0
fi
mkdir -p backups
name="podsync-$(date +%F-%H%M).db"
docker compose exec -T podsync podsync-server backup "/data/$name"
docker compose cp "podsync:/data/$name" "backups/$name"
docker compose exec -T podsync rm -f "/data/$name"
ls -1t backups/podsync-*.db | tail -n +15 | xargs -r rm --
echo "Saved backups/$name ($(du -h "backups/$name" | cut -f1)). Copy that folder somewhere else too."
