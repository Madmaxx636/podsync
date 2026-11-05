#!/usr/bin/env bash
# Adds PodSync to a Caddy that is ALREADY running in Docker on this machine (the one that owns
# ports 80/443 for your other apps). It never edits your existing lines: it appends one new site
# block, checks the result with Caddy itself, reloads, and puts the old file back if anything fails.
#   ./scripts/caddy-add.sh [--host podsync.myname.duckdns.org] [--port 8095]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=""; PORT=""
while [ $# -gt 0 ]; do case "$1" in
  --host) HOST="${2:?}"; shift;; --port) PORT="${2:?}"; shift;;
  *) echo "usage: $0 [--host NAME] [--port N]"; exit 1;; esac; shift; done
say() { printf '%s\n' "$*"; }
die() { printf 'STOPPED: %s\n' "$*" >&2; exit 1; }

# ---- 1. find the Caddy container: image has "caddy" and it owns 80/443 (host network or published) ----
caddy=""
while read -r name image; do
  [[ "${image,,}" == *caddy* ]] || continue
  mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$name")
  pub=$(docker inspect -f '{{range $p,$b := .HostConfig.PortBindings}}{{if eq $p "443/tcp"}}{{range $b}}{{.HostIp}}|{{end}}{{end}}{{end}}' "$name")
  if [ "$mode" = host ] || [[ "$pub" == "|"* ]] || [[ "$pub" == "0.0.0.0|"* ]] || [[ "$pub" == "::|"* ]]; then caddy="$name"; break; fi
done < <(docker ps --format '{{.Names}} {{.Image}}')
[ -n "$caddy" ] || die "no running Caddy container owning ports 80/443 was found (docker ps)."
mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$caddy")
say "Found Caddy: container '$caddy' (network: $mode)"

# ---- 2. find its Caddyfile on the host ----
cfg_in=$(docker inspect -f '{{join .Config.Cmd " "}}' "$caddy" | sed -n 's/.*--config[= ]\([^ ]*\).*/\1/p')
[ -n "$cfg_in" ] || cfg_in=/etc/caddy/Caddyfile
cfg_host=""
while read -r src dst; do
  case "$cfg_in" in
    "$dst") cfg_host="$src"; break;;
    "$dst"/*) cfg_host="$src${cfg_in#"$dst"}"; break;;
  esac
done < <(docker inspect -f '{{range .Mounts}}{{.Source}} {{.Destination}}{{"\n"}}{{end}}' "$caddy")
[ -n "$cfg_host" ] && [ -f "$cfg_host" ] || die "could not find the Caddyfile on disk ($cfg_in inside the container is not a mounted file). Tell me where it lives and I will add the block by hand."
say "Caddyfile: $cfg_host"
SUDO=""; [ -w "$cfg_host" ] && [ -w "$(dirname "$cfg_host")" ] || SUDO="sudo"

# ---- 3. PodSync port and address ----
if [ -z "$PORT" ]; then
  PORT=$(grep -s '^PODSYNC_PORT=' .env | cut -d= -f2 || true)
  if [ -z "$PORT" ]; then
    for p in $(seq 8095 8120); do ss -ltnH "sport = :$p" 2>/dev/null | grep -q . || { PORT=$p; break; }; done
  fi
fi
[ -n "$PORT" ] || die "no free port found."
if [ -z "$HOST" ]; then
  say ""
  say "Existing site names in your Caddyfile:"
  grep -E '^[A-Za-z0-9*][A-Za-z0-9.*-]*\.[A-Za-z]{2,}[^{]*\{' "$cfg_host" | sed 's/[ {]*$//; s/^/   /' | head -12 || true
  say ""
  say "Pick a NEW address for PodSync. With DuckDNS any name under yours works, for example"
  say "   podsync.<yourname>.duckdns.org"
  read -r -p "Address for PodSync (no https://): " HOST
fi
HOST="${HOST#http://}"; HOST="${HOST#https://}"; HOST="${HOST%%/*}"; HOST="$(echo "$HOST" | tr -d '[:space:]')"
[[ "$HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]] || die "\"$HOST\" is not a valid address like podsync.myname.duckdns.org"
grep -qF "$HOST" "$cfg_host" && die "$HOST already appears in your Caddyfile. Pick a different name, or edit that block by hand."

# ---- 4. start PodSync only on this machine, on that port, trusting the proxy ----
touch .env
# A leftover "podsync" container from an earlier attempt (another folder) would block the name.
stale=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' podsync 2>/dev/null || true)
if [ -n "$stale" ] && [ "$stale" != "$PWD" ]; then
  echo "Removing the old PodSync container left by an earlier attempt in $stale (its data volume is kept)."
  docker rm -f podsync >/dev/null 2>&1 || true
fi
{ grep -vE '^(PODSYNC_PORT|PODSYNC_BIND|PODSYNC_TRUST_PROXY|COMPOSE_FILE)=' .env || true
  echo "PODSYNC_PORT=$PORT"; echo "PODSYNC_BIND=127.0.0.1:"; echo "PODSYNC_TRUST_PROXY=true"; } > .env.new && mv .env.new .env
rm -f docker-compose.https.yml Caddyfile
docker compose up -d
for _ in $(seq 1 30); do curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 1; done
curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null || die "PodSync did not answer on 127.0.0.1:$PORT (docker compose logs podsync)."

if [ "$mode" = host ]; then upstream="127.0.0.1:$PORT"
else
  net=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' podsync | awk '{print $1}')
  docker network connect "$net" "$caddy" 2>/dev/null || true
  upstream="podsync:8080"
  say "Note: Caddy is not on the host network, so it was joined to PodSync's network ($net). If you recreate the Caddy container, run this script again."
fi

# ---- 5. add the block, check it, reload, roll back on any failure ----
bak="$cfg_host.bak-$(date +%F-%H%M%S)"
$SUDO cp -p "$cfg_host" "$bak"
say "Backup of your Caddyfile: $bak"
printf '\n# PodSync (added by caddy-add.sh)\n%s {\n\treverse_proxy %s\n}\n' "$HOST" "$upstream" | $SUDO tee -a "$cfg_host" >/dev/null
rollback() { say "Putting your original Caddyfile back."; $SUDO cp -p "$bak" "$cfg_host"; docker exec "$caddy" caddy reload --config "$cfg_in" --adapter caddyfile >/dev/null 2>&1 || true; }
if ! out=$(docker exec "$caddy" caddy validate --config "$cfg_in" --adapter caddyfile 2>&1); then
  say "$out" | tail -8; rollback; die "Caddy rejected the new block (nothing changed)."
fi
if ! out=$(docker exec "$caddy" caddy reload --config "$cfg_in" --adapter caddyfile 2>&1); then
  say "$out" | tail -8; rollback; die "Caddy could not reload (original restored)."
fi
say "Caddy reloaded."
echo "$HOST" > .caddy-host

# ---- 6. check it (through Caddy, on this machine, so DNS and the router are not involved) ----
sport="${CADDY_HTTPS_PORT:-443}"
say "Checking https://$HOST through Caddy (the certificate can take up to a minute the first time) ..."
ok=0
for _ in $(seq 1 25); do
  if curl -fsk --max-time 8 --resolve "$HOST:$sport:127.0.0.1" "https://$HOST:$sport/api/health" 2>/dev/null | grep -q '"status":"ok"'; then ok=1; break; fi
  sleep 3
done
say ""
if [ $ok = 1 ]; then
  say "DONE. PodSync answers through Caddy."
  say "In the app (Settings > Sync > PodSync server) use:   https://$HOST"
  say "From outside your home that name must also point at this network. With DuckDNS any name under yours does; if it does not open, check the duckdns container is running."
else
  say "PodSync is running and Caddy has the new block, but Caddy did not answer for $HOST yet."
  say "Most likely the HTTPS certificate is still being issued (it needs $HOST to point at this network and ports 80/443 to reach this machine). Try again in a minute:"
  say "   curl -k --resolve $HOST:443:127.0.0.1 https://$HOST/api/health"
  say "Caddy's own log: docker logs $caddy --tail 30"
  say "In the app use: https://$HOST"
fi
