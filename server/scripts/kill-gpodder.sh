#!/usr/bin/env bash
# Kills gPodder (and anything else holding web ports 80/443) on THIS machine, in one go.
#   ./scripts/kill-gpodder.sh            shows the plan, asks once, then does it
#   ./scripts/kill-gpodder.sh --yes      no question (you have been warned)
#   ./scripts/kill-gpodder.sh --dry-run  only show the plan
#   ./scripts/kill-gpodder.sh --name X   also treat container X as gPodder
#
# It backs up the data first (always, to ~/gpodder-backup-DATE), then:
#   - removes every container, volume and image that looks like gPodder (other containers in the
#     same compose project are left alone)
#   - stops (does not delete) containers and services that hold ports 80 and 443
#   - disables gPodder systemd services
set -uo pipefail
YES=0; DRY=0; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1;; --dry-run) DRY=1;; --name) EXTRA+=("${2:?container name}"); shift;;
    *) echo "usage: $0 [--yes] [--dry-run] [--name CONTAINER]"; exit 1;;
  esac; shift
done
PAT='gpodder|mygpo|opodsync|gpodder2go|nextcloud-gpodder'
say() { printf '%s\n' "$*"; }
run() { if [ $DRY = 1 ]; then say "   [dry run] $*"; else "$@" || say "   (that step failed, carrying on)"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

kill_c=(); stop_c=(); volumes=(); images=(); projects=(); units=(); stop_units=(); binds=()

# ---- 1. find everything -----------------------------------------------------------------------
if have docker; then
  while read -r name image; do
    [[ "$name $image" =~ $PAT ]] && kill_c+=("$name")
  done < <(docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null)
  for n in "${EXTRA[@]:-}"; do [ -n "$n" ] && kill_c+=("$n"); done

  # any compose project that has a gPodder container: remove the whole project's gPodder parts
  for c in "${kill_c[@]:-}"; do
    [ -n "$c" ] || continue
    images+=("$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null)")
    p=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null)
    [ -n "$p" ] && projects+=("$p")
    while read -r typ src; do
      [ "$typ" = volume ] && volumes+=("$src")
      [ "$typ" = bind ] && binds+=("$src")
    done < <(docker inspect -f '{{range .Mounts}}{{.Type}} {{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}{{"\n"}}{{end}}' "$c" 2>/dev/null)
  done

  # containers that publish port 80 or 443 (reverse proxies and the like) are stopped, not deleted
  while read -r name ports; do
    [[ "$name" =~ ^podsync$|^server-caddy|^podsync-caddy ]] && continue
    [[ " ${kill_c[*]:-} " == *" $name "* ]] && continue
    [[ "$ports" =~ (:80->|:443->) ]] && stop_c+=("$name")
  done < <(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null)
fi
if have systemctl; then
  while read -r u _; do [[ "$u" =~ $PAT ]] && units+=("$u"); done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null)
  for u in nginx.service apache2.service httpd.service caddy.service lighttpd.service; do
    systemctl is-active --quiet "$u" 2>/dev/null && stop_units+=("$u")
  done
fi
# whatever else still listens on 80/443 (plain processes): shown, never killed
others=$(ss -ltnpH 2>/dev/null | awk '$4 ~ /:(80|443)$/ {print $4"  "$NF}' | sort -u)

uniq_arr() { printf '%s\n' "$@" | awk 'NF && !s[$0]++'; }
mapfile -t kill_c < <(uniq_arr "${kill_c[@]:-}")
mapfile -t stop_c < <(uniq_arr "${stop_c[@]:-}")
mapfile -t volumes < <(uniq_arr "${volumes[@]:-}")
mapfile -t images < <(uniq_arr "${images[@]:-}")
mapfile -t projects < <(uniq_arr "${projects[@]:-}")
mapfile -t binds < <(uniq_arr "${binds[@]:-}")

# ---- 2. show the plan -------------------------------------------------------------------------
say ""
say "=== WHAT WILL HAPPEN ==="
if [ ${#kill_c[@]} -eq 0 ] && [ ${#units[@]} -eq 0 ] && [ ${#stop_c[@]} -eq 0 ] && [ ${#stop_units[@]} -eq 0 ]; then
  say "Nothing that looks like gPodder was found, and nothing known is holding ports 80/443."
  [ -n "$others" ] && { say "But something still listens on 80/443:"; say "$others"; }
  say "If gPodder has an odd name, run:  $0 --name THE_CONTAINER_NAME   (see names with: docker ps -a)"
  exit 0
fi
for c in "${kill_c[@]}"; do say "DELETE container   $c"; done
for v in "${volumes[@]}"; do say "DELETE volume      $v   (its data)"; done
for i in "${images[@]}"; do say "DELETE image       $i"; done
for b in "${binds[@]}"; do say "KEEP  folder       $b   (backed up, left on disk)"; done
for u in "${units[@]}"; do say "DISABLE service    $u"; done
for c in "${stop_c[@]}"; do say "STOP   container   $c   (holds port 80/443; stopped, not deleted)"; done
for u in "${stop_units[@]}"; do say "STOP   service     $u   (holds port 80/443; stopped and disabled)"; done
[ -n "$others" ] && { say ""; say "Not touched (plain programs on 80/443, stop these yourself if they are in the way):"; say "$others"; }
say ""
say "A backup of the data goes to ~/gpodder-backup-<date> first."
say "Make sure you already moved your data into PodSync."
say ""

[ $DRY = 1 ] && { say "(dry run, nothing done)"; exit 0; }
if [ $YES != 1 ]; then
  read -r -p "Type YES (capitals) to do all of this: " a
  [ "$a" = YES ] || { say "Cancelled. Nothing was changed."; exit 1; }
fi

# ---- 3. back up -------------------------------------------------------------------------------
backup="$HOME/gpodder-backup-$(date +%F-%H%M)"
mkdir -p "$backup"
say ""
say "Backing up to $backup ..."
for v in "${volumes[@]}"; do
  docker run --rm -v "$v":/src:ro -v "$backup":/out alpine tar -czf "/out/volume-$v.tar.gz" -C /src . >/dev/null 2>&1 \
    && say "   saved volume $v" || say "   could not back up volume $v"
done
for b in "${binds[@]}"; do
  tar -czf "$backup/folder-$(echo "$b" | tr / _).tar.gz" -C "$b" . 2>/dev/null \
    && say "   saved folder $b" || say "   could not read $b (permissions?)"
done

# ---- 4. kill ----------------------------------------------------------------------------------
say ""
say "Stopping and deleting ..."
for c in "${kill_c[@]}"; do run docker rm -f "$c"; done
for v in "${volumes[@]}"; do run docker volume rm -f "$v"; done
for i in "${images[@]}"; do run docker rmi "$i"; done
for c in "${stop_c[@]}"; do run docker update --restart=no "$c"; run docker stop "$c"; done
for u in "${units[@]}"; do
  f=$(systemctl show -p FragmentPath --value "$u" 2>/dev/null)
  run sudo systemctl disable --now "$u"
  [ -n "$f" ] && [ -f "$f" ] && run sudo rm -f "$f"
done
for u in "${stop_units[@]}"; do run sudo systemctl disable --now "$u"; done
[ ${#units[@]} -gt 0 ] && run sudo systemctl daemon-reload

say ""
say "Done. Ports 80 and 443 now:"
ss -ltnpH 2>/dev/null | awk '$4 ~ /:(80|443)$/ {print "   STILL IN USE: "$4"  "$NF}' | sort -u | grep . || say "   free"
say "Your backup: $backup"
say "Next: ./setup.sh"
