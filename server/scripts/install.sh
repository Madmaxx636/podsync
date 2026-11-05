#!/usr/bin/env bash
# First-time setup: checks Docker, builds and starts the server, waits until it answers, and helps
# you create the first account. Safe to run again.
#   cd server && ./scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v docker >/dev/null || { echo "Docker is not installed. See https://docs.docker.com/engine/install/"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is missing (the 'docker compose' command)."; exit 1; }

PORT="${PODSYNC_PORT:-8080}"
echo "Building and starting PodSync on port $PORT ..."
PODSYNC_PORT="$PORT" docker compose up -d --build

printf "Waiting for the server"
for _ in $(seq 1 30); do
  if curl -fs "http://localhost:$PORT/api/health" >/dev/null 2>&1; then ok=1; break; fi
  printf "."; sleep 1
done
echo
[ "${ok:-0}" = 1 ] || { echo "The server did not answer. Look at: docker compose logs podsync"; exit 1; }
curl -s "http://localhost:$PORT/api/health"; echo

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "PodSync is running. In the app (Settings > Sync > PodSync server) use:"
echo "  http://${ip:-YOUR-SERVER-IP}:$PORT"
echo
read -r -p "Create your account now? Username (blank to skip): " name || name=""
if [ -n "$name" ]; then
  ./scripts/adduser.sh "$name"
fi
echo
echo "Next: ./scripts/backup.sh (and ./scripts/backup.sh --cron to schedule it daily)."
echo "Once everyone has an account, close sign-up: ./scripts/signup.sh off"
