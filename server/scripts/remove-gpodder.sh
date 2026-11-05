#!/usr/bin/env bash
# Finds a gPodder-compatible sync server on THIS machine (gpodder, mygpo, opodsync, gpodder2go ...
# as Docker containers or systemd services), backs up its data, and then stops and deletes it.
# Nothing is removed without your typed confirmation. Move your data to PodSync first.
#   ./scripts/remove-gpodder.sh [--dry-run] [--name CONTAINER]
set -euo pipefail
DRY=0; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1;;
    --name) EXTRA+=("${2:?container name}"); shift;;
    *) echo "usage: $0 [--dry-run] [--name CONTAINER]"; exit 1;;
  esac
  shift
done
run() { if [ $DRY = 1 ]; then echo "[dry run] $*"; else "$@"; fi; }
PAT='gpodder|mygpo|opodsync|gpodder2go|nextcloud-gpodder'

have_docker=1
command -v docker >/dev/null || { have_docker=0; echo "Docker is not installed here, so no gPodder container can be on this machine."; }

# ---- find it ----------------------------------------------------------------------------------
containers=()
if [ $have_docker = 1 ]; then
  while read -r name image; do
    if [[ "$name $image" =~ $PAT ]]; then containers+=("$name"); fi
  done < <(docker ps -a --format '{{.Names}} {{.Image}}')
  if [ ${#EXTRA[@]} -gt 0 ]; then containers+=("${EXTRA[@]}"); fi
fi
units=()
if command -v systemctl >/dev/null; then
  while read -r u _; do
    if [[ "$u" =~ $PAT ]]; then units+=("$u"); fi
  done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null || true)
fi

if [ ${#containers[@]} -eq 0 ] && [ ${#units[@]} -eq 0 ]; then
  echo "Found no gPodder container or service on this machine."
  echo "If it runs under another name: $0 --name CONTAINER_NAME"
  echo "If it runs on another machine, run this script there."
  exit 0
fi

echo "Found:"
volumes=(); binds=(); images=(); dirs=()
for c in "${containers[@]}"; do
  echo "  container  $c  ($(docker inspect -f '{{.Config.Image}} / {{.State.Status}}' "$c"))"
  images+=("$(docker inspect -f '{{.Config.Image}}' "$c")")
  while read -r typ src; do
    if [ "$typ" = volume ]; then volumes+=("$src"); fi
    if [ "$typ" = bind ]; then binds+=("$src"); fi
  done < <(docker inspect -f '{{range .Mounts}}{{.Type}} {{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}{{"\n"}}{{end}}' "$c")
  d=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$c" 2>/dev/null || true)
  if [ -n "$d" ]; then dirs+=("$d"); fi
done
for u in "${units[@]}"; do echo "  service    $u"; done
for v in "${volumes[@]}"; do echo "  data (volume)  $v"; done
for b in "${binds[@]}"; do echo "  data (folder)  $b"; done
for d in "${dirs[@]}"; do echo "  compose folder $d"; done
echo

# ---- make sure the data is safe ---------------------------------------------------------------
read -r -p "Have you already moved your data into PodSync (Settings > Sync, and checked on a second device)? Type yes: " a
[ "$a" = yes ] || { echo "Do that first, then run this again. Nothing was changed."; exit 1; }

backup="gpodder-backup-$(date +%F-%H%M)"
read -r -p "Save a backup of its data to ./$backup first? [Y/n] " a
if [[ ! "${a:-y}" =~ ^[Nn] ]]; then
  run mkdir -p "$backup"
  for v in "${volumes[@]}"; do
    run docker run --rm -v "$v":/src:ro -v "$PWD/$backup":/out alpine tar -czf "/out/volume-$v.tar.gz" -C /src .
  done
  for b in "${binds[@]}"; do
    run tar -czf "$backup/folder-$(echo "$b" | tr / _).tar.gz" -C "$b" . || echo "could not read $b (try with sudo)"
  done
  echo "Backup written to ./$backup (keep it until you are sure you do not need it)."
fi

# ---- stop and delete --------------------------------------------------------------------------
echo
echo "This will STOP and DELETE the containers and services listed above."
read -r -p "Type DELETE to continue: " a
[ "$a" = DELETE ] || { echo "Cancelled, nothing was removed."; exit 1; }

for c in "${containers[@]}"; do run docker rm -f "$c"; done
for u in "${units[@]}"; do
  f=$(systemctl show -p FragmentPath --value "$u" 2>/dev/null || true)
  run sudo systemctl disable --now "$u"
  if [ -n "$f" ] && [ -f "$f" ]; then run sudo rm -f "$f"; fi
done
if [ ${#units[@]} -gt 0 ]; then run sudo systemctl daemon-reload; fi

read -r -p "Also delete its data volumes? [y/N] " a
if [[ "${a:-n}" =~ ^[Yy] ]]; then for v in "${volumes[@]}"; do run docker volume rm "$v"; done; fi
read -r -p "Also remove its images? [y/N] " a
if [[ "${a:-n}" =~ ^[Yy] ]]; then for i in "${images[@]}"; do run docker rmi "$i" || true; done; fi

# Folders on disk are only removed after you retype each path, and never anything short or shared.
for b in "${binds[@]}" "${dirs[@]}"; do
  case "$b" in
    /|/home|/root|/var|/etc|/usr|/opt|"$HOME"|"$HOME"/) echo "Leaving $b alone (too broad)."; continue;;
  esac
  if [ "$(echo "$b" | tr -cd / | wc -c)" -lt 3 ]; then echo "Leaving $b alone (too close to the top of the disk)."; continue; fi
  read -r -p "Delete the folder $b ? Retype the full path to confirm, or press Enter to keep it: " a
  if [ "$a" = "$b" ]; then run rm -rf -- "$b"; fi
done
echo "Done. gPodder is gone from this machine."
echo "If its address (your DuckDNS name) now belongs to PodSync, remove any old reverse-proxy entry for it."
