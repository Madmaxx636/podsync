#!/usr/bin/env bash
# PodSync server setup wizard. One command, a few screens:
#   ./setup.sh
# It checks Docker (and can install it), asks how you want to reach the server, optionally sets up
# DuckDNS and HTTPS, starts everything, creates your account, and schedules backups.
# Uses whiptail dialogs when available; PODSYNC_PLAIN=1 forces plain questions.
# PODSYNC_NO_CRON=1 skips scheduling the DuckDNS update and backups (for testing).
set -euo pipefail
cd "$(dirname "$0")"
TITLE="PodSync server setup"

# ---- tiny UI layer: whiptail screens or plain prompts ------------------------------------------
if command -v whiptail >/dev/null && [ -t 0 ] && [ -z "${PODSYNC_PLAIN:-}" ]; then UI=whiptail; else UI=plain; fi

msg() { # message
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --msgbox "$1" 20 74; else printf '\n%s\n' "$1"; fi
}
yesno() { # question default(y|n)  -> 0 for yes
  if [ $UI = whiptail ]; then
    local d=(); [ "${2:-y}" = n ] && d=(--defaultno)
    whiptail --title "$TITLE" "${d[@]}" --yesno "$1" 14 74
  else
    local a; read -r -p "$1 [${2:-y}] " a || a=""; a="${a:-${2:-y}}"; [[ $a =~ ^[Yy] ]]
  fi
}
ask() { # question default -> echoes the answer
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --inputbox "$1" 12 74 "${2:-}" 3>&1 1>&2 2>&3 || exit 1
  else local a; read -r -p "$1 [${2:-}] " a || exit 1; echo "${a:-${2:-}}"; fi
}
secret() { # question -> echoes the answer
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --passwordbox "$1" 12 74 3>&1 1>&2 2>&3 || exit 1
  else local a; read -r -s -p "$1: " a || exit 1; echo >&2; echo "$a"; fi
}
choose() { # question tag1 text1 tag2 text2 ... -> echoes the tag
  local q="$1"; shift
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --menu "$q" 18 74 6 "$@" 3>&1 1>&2 2>&3 || exit 1
  else
    printf '\n%s\n' "$q" >&2; local i=1 tags=()
    while [ $# -gt 0 ]; do printf '  %d) %s\n' "$i" "$2" >&2; tags+=("$1"); shift 2; i=$((i+1)); done
    local n; read -r -p "Number: " n || exit 1; echo "${tags[$((n-1))]}"
  fi
}
step() { printf '\n==> %s\n' "$1"; }
die() { msg "Stopped: $1"; exit 1; }

# ---- 1. welcome and Docker ---------------------------------------------------------------------
msg "This sets up your own PodSync sync server in Docker.

It will:
  - check that Docker is installed (and offer to install it)
  - start the server
  - create your account
  - optionally put it on the internet under your DuckDNS name with HTTPS
  - schedule daily backups

Nothing is changed until the last confirmation."

if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  if yesno "Docker with Compose is not installed. Install it now with Docker's official script (needs sudo)?" y; then
    step "Installing Docker"
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" || true
    msg "Docker is installed. Log out and back in once so your user may use it, then run ./setup.sh again."
    exit 0
  fi
  die "Docker is required. See https://docs.docker.com/engine/install/"
fi
docker info >/dev/null 2>&1 || die "Docker is installed but not running, or your user may not use it (try: sudo usermod -aG docker \$USER, then log in again)."

# ---- 2. how to reach it -----------------------------------------------------------------------
MODE=$(choose "How will you use the server?" \
  home "At home only (simplest, plain http on your network)" \
  duckdns "Also away from home, with my DuckDNS name (https)")
PORT=8080
if [ $MODE = home ]; then PORT=$(ask "Port to listen on" "8080"); fi

DOMAIN=""; TOKEN=""; EMAIL=""
if [ $MODE = duckdns ]; then
  msg "For access from outside you need:
  1. A DuckDNS name and its token (duckdns.org, shown at the top of your page).
  2. Router port forwarding: TCP 80 and 443 to this machine.
  3. An internet connection that is not behind CGNAT (if your router's WAN address differs from what a 'what is my IP' site shows, this will not work; use Tailscale instead).

The name will point at your home connection and the server will be reachable by anyone who knows it, so sign-ups get switched off at the end."
  while :; do
    DOMAIN=$(ask "Your DuckDNS name (just the first part, e.g. myname)" "$DOMAIN")
    DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"; DOMAIN="${DOMAIN%.duckdns.org}"
    TOKEN=$(secret "Your DuckDNS token (the long code at the top of duckdns.org when you are logged in)")
    TOKEN="$(echo "$TOKEN" | tr -d '[:space:]')"
    if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then msg "Both the name and the token are needed."; continue; fi
    # Check it right away; this also points the name at this connection, which is the goal.
    reply=$(DUCKDNS_DOMAIN="$DOMAIN" DUCKDNS_TOKEN="$TOKEN" ./scripts/duckdns.sh 2>&1 | tail -1 || true)
    [ "$reply" = OK ] && break
    msg "DuckDNS answered \"$reply\" instead of OK.

\"KO\" means the name and token do not belong together. Check that:
  - the name is listed under the account that owns the token
  - you copied the whole token, with nothing extra
  - you entered only the first part of the name (myname, not myname.duckdns.org)

Let's try again."
  done
  EMAIL=$(ask "Email for the HTTPS certificate (Let's Encrypt only uses it for expiry warnings)" "")
  [ -n "$EMAIL" ] || die "No email given."
fi

# ---- 3. account and options -------------------------------------------------------------------
USERNAME=$(ask "Username for your account (3 to 32 letters, numbers, dots, dashes, underscores)" "$USER")
while :; do
  PASS=$(secret "Password for $USERNAME (8 to 72 characters)")
  PASS2=$(secret "Same password again")
  if [ "$PASS" != "$PASS2" ]; then msg "The passwords did not match. Try again."; continue; fi
  if [ ${#PASS} -lt 8 ] || [ ${#PASS} -gt 72 ]; then msg "Passwords are 8 to 72 characters."; continue; fi
  break
done
CLOSE=n; [ $MODE = duckdns ] && CLOSE=y
yesno "Close self-registration now? (Nobody else can make an account; you can add people later with ./scripts/adduser.sh.)" $CLOSE && CLOSE=y || CLOSE=n
yesno "Back up the data every night at 03:30 (kept in ./backups, newest 14)?" y && BACKUP=y || BACKUP=n

SUMMARY="Ready to set up:

  Mode:        $([ $MODE = home ] && echo "home network, port $PORT" || echo "https://$DOMAIN.duckdns.org")
  Account:     $USERNAME
  Sign-up:     $([ $CLOSE = y ] && echo closed || echo open)
  Backups:     $([ $BACKUP = y ] && echo nightly || echo no)

Start now?"
yesno "$SUMMARY" y || { echo "Cancelled, nothing changed."; exit 0; }

# ---- 4. do it ---------------------------------------------------------------------------------
export PODSYNC_PORT="$PORT"
if [ $MODE = duckdns ]; then
  step "Keeping $DOMAIN.duckdns.org up to date"
  export DUCKDNS_DOMAIN="$DOMAIN" DUCKDNS_TOKEN="$TOKEN"
  [ -n "${PODSYNC_NO_CRON:-}" ] || ./scripts/duckdns.sh --cron
fi

./scripts/signup.sh "$([ $CLOSE = y ] && echo off || echo on)" --no-restart >/dev/null
step "Building and starting the server"
if [ $MODE = duckdns ]; then
  ./scripts/https.sh "$DOMAIN.duckdns.org" "$EMAIL"
else
  docker compose up -d --build
fi

step "Waiting for the server"
base="http://localhost:$PORT"; [ $MODE = duckdns ] && base="http://localhost:8080"
ok=0
for _ in $(seq 1 45); do
  if [ $MODE = duckdns ]; then
    docker compose exec -T podsync podsync-server healthcheck >/dev/null 2>&1 && ok=1 && break
  else
    curl -fs "$base/api/health" >/dev/null 2>&1 && ok=1 && break
  fi
  sleep 1
done
[ $ok = 1 ] || die "The server did not start. Look at: docker compose logs podsync"

step "Creating your account"
PODSYNC_PASSWORD="$PASS" ./scripts/adduser.sh "$USERNAME"
[ $BACKUP = y ] && [ -z "${PODSYNC_NO_CRON:-}" ] && ./scripts/backup.sh --cron

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ $MODE = home ]; then
  URL="http://${ip:-YOUR-SERVER-IP}:$PORT"
  EXTRA="Tip: give this machine a fixed IP in your router so the address never changes."
else
  URL="https://$DOMAIN.duckdns.org"
  EXTRA="The certificate is fetched on the first visit and can take a minute. If it does not work, check that the router forwards TCP 80 and 443 to ${ip:-this machine}.
Inside your home the name may not open (some routers cannot loop back), so test it from mobile data first."
fi
msg "PodSync is running.

In the app: Settings > Sync > PodSync server
  Server address:  $URL
  Username:        $USERNAME

$EXTRA

Useful later (in this folder):
  ./scripts/adduser.sh NAME    add a person
  ./scripts/backup.sh          back up now
  ./scripts/update.sh          update the server"
