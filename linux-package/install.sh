#!/bin/sh
# Installs PodSync for the current user: copies this folder to ~/.local/share/podsync and adds a
# menu entry. No root needed. Run again after unpacking a newer archive to update by hand.
set -e
here=$(cd "$(dirname "$0")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/podsync"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$dest" "$apps" "$HOME/.local/bin"
cp -a "$here"/. "$dest"/
sed "s|@DEST@|$dest|g" "$here/podsync.desktop" > "$apps/podsync.desktop"
ln -sf "$dest/podsync" "$HOME/.local/bin/podsync"
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "Note: PodSync plays audio with libmpv, which is not installed."
  echo "  Debian/Ubuntu: sudo apt install libmpv2    Fedora: sudo dnf install mpv-libs    Arch: sudo pacman -S mpv"
fi
echo "PodSync installed in $dest. Find it in your applications menu, or run: podsync"
