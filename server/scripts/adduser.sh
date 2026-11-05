#!/usr/bin/env bash
# Adds a person (asks for the password). Other commands: list, passwd NAME, delete NAME.
#   ./scripts/adduser.sh alice
#   ./scripts/adduser.sh --list | --passwd alice | --delete alice
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -t 0 ]; then tty=(-it); else tty=(-T); fi      # asks for the password on a terminal
env=(); [ -n "${PODSYNC_PASSWORD:-}" ] && env=(-e PODSYNC_PASSWORD)
case "${1:-}" in
  "" ) echo "usage: $0 NAME | --list | --passwd NAME | --delete NAME"; exit 1;;
  --list) docker compose exec podsync podsync-server user list;;
  --passwd) docker compose exec "${tty[@]}" "${env[@]}" podsync podsync-server user passwd "${2:?name}";;
  --delete)
    read -r -p "Delete ${2:?name} and everything they synced? Type yes: " a
    [ "$a" = yes ] && docker compose exec podsync podsync-server user delete "$2";;
  *) docker compose exec "${tty[@]}" "${env[@]}" podsync podsync-server user add "$1";;
esac
