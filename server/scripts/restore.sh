#!/usr/bin/env bash
# Puts a backup back. Stops the server, replaces the database, starts it again. Devices that are
# ahead of the backup send what the server lost.
#   ./scripts/restore.sh backups/podsync-2026-11-04-0330.db
set -euo pipefail
cd "$(dirname "$0")/.."
f="${1:?usage: $0 BACKUP_FILE}"
[ -f "$f" ] || { echo "No such file: $f"; exit 1; }
read -r -p "Replace the current data with $f? Type yes: " a
[ "$a" = yes ] || exit 1
./scripts/backup.sh || true            # keep a copy of what is there now
docker compose stop podsync
cid=$(docker compose ps -aq podsync)
docker cp "$f" "$cid:/data/podsync.db"
docker compose start podsync
echo "Restored from $f."
