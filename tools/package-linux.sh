#!/bin/sh
# Packs the Linux release build into PodSync-linux-x64.tar.gz (a single "podsync/" folder holding
# the program, install.sh and the menu entry). Run from the repository root after
# `flutter build linux --release` in app/.
set -e
out="${1:-PodSync-linux-x64.tar.gz}"
stage=$(mktemp -d)
cp -a app/build/linux/x64/release/bundle "$stage/podsync-dir"
mv "$stage/podsync-dir" "$stage/podsync"
cp linux-package/install.sh linux-package/podsync.desktop "$stage/podsync/"
cp app/assets/icon/icon.png "$stage/podsync/podsync.png"
tar -C "$stage" -czf "$out" podsync
rm -rf "$stage"
echo "wrote $out"
