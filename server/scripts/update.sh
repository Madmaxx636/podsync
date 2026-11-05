#!/usr/bin/env bash
# Backs up, fetches the newest code and rebuilds. Data lives in the volume, so it survives and
# everyone stays signed in.
#   ./scripts/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/backup.sh
git pull --ff-only
docker compose up -d --build
sleep 3
curl -s "http://localhost:${PODSYNC_PORT:-8080}/api/health"; echo
