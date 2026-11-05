#!/usr/bin/env bash
# Updates the PodSync server to the newest release on GitHub: backs up the data, downloads the
# new server files, rebuilds, restarts, and checks that it answers. Your data, accounts and .env
# are never touched. Changes nothing when you are already up to date.
#   ./scripts/auto-update.sh            update now
#   ./scripts/auto-update.sh --check    only say whether an update exists
#   ./scripts/auto-update.sh --cron     check every night at 04:15
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${PODSYNC_REPO:-Madmaxx636/podsync}"

if [ "${1:-}" = "--cron" ]; then
  line="15 4 * * * cd $(pwd) && ./scripts/auto-update.sh >> auto-update.log 2>&1"
  ( crontab -l 2>/dev/null | grep -vF "auto-update.sh"; echo "$line" ) | crontab -
  echo "Scheduled: $line"; exit 0
fi

echo "[$(date '+%F %T')] checking $REPO"
tag=$(curl -fsS "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || true
[ -n "$tag" ] || { echo "Could not reach GitHub; will try again next time."; exit 1; }
current=$(cat .version 2>/dev/null || echo none)
if [ "$tag" = "$current" ]; then echo "Up to date ($tag)."; exit 0; fi
echo "Newest is $tag (this server: $current)."
[ "${1:-}" = "--check" ] && exit 0

./scripts/backup.sh || echo "(backup failed; continuing)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/$REPO/archive/refs/tags/$tag.tar.gz" | tar -xz -C "$tmp" --strip-components=2 --wildcards '*/server/*'
[ -f "$tmp/Dockerfile" ] || { echo "The download did not contain the server; nothing changed."; exit 1; }
rm -f "$tmp"/*_test.go

# Build first: if the build fails the running server is untouched.
cp -a "$tmp"/. ./.new-server 2>/dev/null || { mkdir -p .new-server && cp -a "$tmp"/. .new-server/; }
( cd .new-server && docker build -q --build-arg VERSION="$tag" -t podsync-server:latest . ) \
  || { echo "The new version did not build; nothing changed."; rm -rf .new-server; exit 1; }
cp -a .new-server/. . && rm -rf .new-server
chmod +x setup.sh scripts/*.sh 2>/dev/null || true
docker compose up -d
port=$(grep -s '^PODSYNC_PORT=' .env | cut -d= -f2 || true); port="${port:-8080}"
ok=0
for _ in $(seq 1 40); do
  if docker compose exec -T podsync podsync-server healthcheck >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ $ok = 1 ]; then echo "$tag" > .version; echo "Updated to $tag."; else echo "The new server did not come up. Look at: docker compose logs podsync (your data is backed up in ./backups)"; exit 1; fi
