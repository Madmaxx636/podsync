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
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --inputbox "$1" 22 74 "${2:-}" 3>&1 1>&2 2>&3 || exit 1
  else local a; printf '\n%b\n' "$1" >&2; read -r -p "> [${2:-}] " a || exit 1; echo "${a:-${2:-}}"; fi
}
secret() { # question -> echoes the answer
  if [ $UI = whiptail ]; then whiptail --title "$TITLE" --passwordbox "$1" 20 74 3>&1 1>&2 2>&3 || exit 1
  else local a; printf '\n%b\n' "$1" >&2; read -r -s -p "> " a || exit 1; echo >&2; echo "$a"; fi
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
if [ $MODE = home ]; then PORT=$(ask "PORT NUMBER\n\nThe server will be at http://THIS-MACHINE:PORT. Press Enter to keep 8080 unless something else already uses it." "8080"); fi

DOMAIN=""; TOKEN=""; EMAIL=""
if [ $MODE = duckdns ]; then
  msg "For access from outside you need:
  1. A DuckDNS name and its token (duckdns.org, shown at the top of your page).
  2. Router port forwarding: TCP 80 and 443 to this machine.
  3. An internet connection that is not behind CGNAT (if your router's WAN address differs from what a 'what is my IP' site shows, this will not work; use Tailscale instead).

The name will point at your home connection and the server will be reachable by anyone who knows it, so sign-ups get switched off at the end."
  while :; do
    DOMAIN=$(ask "DUCKDNS NAME

Type only the first part of your DuckDNS address.
  Address:  https://myserver.duckdns.org
  You type: myserver

(No https://, no .duckdns.org. If you paste the whole address I will cut it down for you.)" "$DOMAIN")
    DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"
    DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"; DOMAIN="${DOMAIN%.duckdns.org}"
    TOKEN=$(secret "DUCKDNS TOKEN

The long code (looks like 1a2b3c4d-1234-...) shown at the top of duckdns.org when you are logged in, next to the word 'token'.
It is hidden while you type.")
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
  while :; do
    EMAIL=$(ask "YOUR EMAIL ADDRESS (not the website address)

Type an email you read, like you@example.com.
It is only given to Let's Encrypt, the free service that issues the HTTPS padlock certificate. They use it to warn you if the certificate ever fails to renew. It is not an account and nobody else sees it." "")
    EMAIL="$(echo "$EMAIL" | tr -d '[:space:]')"
    if [[ "$EMAIL" =~ ^[^@/:]+@[^@/:]+\.[^@/:]+$ ]]; then break; fi
    msg "\"$EMAIL\" is not an email address. It needs to look like you@example.com (an @ and no https://)."
  done
fi

# ---- 2b. ports 80 and 443 must be free for HTTPS ------------------------------------------------
if [ $MODE = duckdns ]; then
  busy=""
  for p in 80 443; do
    line=$(ss -ltnpH "sport = :$p" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
      who=$(echo "$line" | grep -o 'users:.*' || true)
      [ -n "$who" ] || who="a program run by another user (see: sudo ss -ltnp | grep ':$p ')"
      busy="$busy\n  port $p is used by: $who"
    fi
  done
  # Containers that publish them (ss shows docker-proxy, not the container name).
  boxes=$(docker ps --format '{{.Names}}  {{.Ports}}' 2>/dev/null | grep -E '(:|^)(80|443)->' | grep -v '^podsync' || true)
  if [ -n "$busy" ] || [ -n "$boxes" ]; then
    msg "Ports 80 and 443 are already in use on this machine, so HTTPS cannot start:
$(printf '%b' "$busy")
${boxes:+
Docker containers publishing them:
$boxes
}
Something else (probably a reverse proxy such as Caddy or nginx, which may serve your other apps) already owns them.
You have two choices:
  1. Keep it, choose 'At home only' in this wizard with a free port (like 8095), and add PodSync to that proxy yourself.
  2. Stop it (only if nothing else needs it), then run ./setup.sh again.

Nothing has been changed yet."
    exit 1
  fi
fi

# ---- 3. account and options -------------------------------------------------------------------
USERNAME=$(ask "YOUR PODSYNC USERNAME\n\nThis is what you will type in the app to sign in. 3 to 32 characters: letters, numbers, dots, dashes or underscores. No spaces." "$USER")
while :; do
  PASS=$(secret "PASSWORD for $USERNAME\n\nChoose one now (8 to 72 characters). You will type it in the app. It is hidden while you type.")
  PASS2=$(secret "PASSWORD AGAIN\n\nType the same password once more to be sure.")
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
if ./scripts/adduser.sh --list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$(echo "$USERNAME" | tr A-Z a-z)"; then
  echo "The account $USERNAME already exists (from an earlier run); keeping it. Change its password with ./scripts/adduser.sh --passwd $USERNAME if needed."
else
  PODSYNC_PASSWORD="$PASS" ./scripts/adduser.sh "$USERNAME"
fi
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
