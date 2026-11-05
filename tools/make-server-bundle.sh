#!/bin/bash
# Packs the server (source, Dockerfile, compose file and every script) into ONE self-extracting
# file you can copy to the machine that will run it:
#   tools/make-server-bundle.sh [output]      then on the server:  bash podsync-server-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-podsync-server-setup.sh}"
tmp=$(mktemp)
(cd server && tar -czf "$tmp" --exclude='*_test.go' --exclude=backups --exclude=.env \
  Dockerfile docker-compose.yml .dockerignore go.mod go.sum *.go README.md setup.sh scripts)
cat > "$out" <<'EOS'
#!/bin/bash
# PodSync server: one-file installer. Unpacks into ./podsync-server and starts the setup wizard.
#   bash podsync-server-setup.sh
set -euo pipefail
dest="${PODSYNC_DIR:-$PWD/podsync-server}"
if [ -e "$dest/setup.sh" ]; then
  echo "$dest already exists; updating its files (your data and .env are kept)."
fi
mkdir -p "$dest"
sed '1,/^__ARCHIVE__$/d' "$0" | tar -xzf - -C "$dest"
chmod +x "$dest/setup.sh" "$dest"/scripts/*.sh
echo "Unpacked to $dest"
cd "$dest"
exec ./setup.sh
exit 0
__ARCHIVE__
EOS
cat "$tmp" >> "$out"
chmod +x "$out"; rm -f "$tmp"
echo "wrote $out ($(du -h "$out" | cut -f1))"
