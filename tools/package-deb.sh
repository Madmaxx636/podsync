#!/bin/sh
# Builds PodSync-linux-x64.deb from the Linux release build. Run from the repository root
# after `flutter build linux --release` in app/.
#   tools/package-deb.sh [output.deb]
# Installs to /opt/podsync with /usr/bin/podsync, a menu entry and an icon. Needs libmpv for audio.
set -e
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' app/pubspec.yaml)
out="${1:-PodSync-linux-x64.deb}"
root=$(mktemp -d)
mkdir -p "$root/opt" "$root/usr/bin" "$root/usr/share/applications" \
         "$root/usr/share/icons/hicolor/512x512/apps" "$root/DEBIAN"
cp -a app/build/linux/x64/release/bundle "$root/opt/podsync"
ln -s /opt/podsync/podsync "$root/usr/bin/podsync"
cp linux-package/podsync-deb.desktop "$root/usr/share/applications/podsync.desktop"
cp linux-package/podsync-512.png "$root/usr/share/icons/hicolor/512x512/apps/podsync.png"
size=$(du -sk "$root/opt" | cut -f1)
cat > "$root/DEBIAN/control" <<EOF
Package: podsync
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Installed-Size: $size
Depends: libgtk-3-0, libmpv2 | libmpv1, libayatana-appindicator3-1 | libappindicator3-1
Maintainer: PodSync <podsync@localhost>
Homepage: https://github.com/Madmaxx636/podsync-releases
Description: Podcast app that syncs through your own server
 PodSync keeps subscriptions, listening progress and the Up Next queue in step across
 Windows, Linux and Android. Imports AntennaPod backups and OPML, syncs with gPodder.
EOF
cat > "$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q /usr/share/applications || true; fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true; fi
exit 0
EOF
chmod 755 "$root/DEBIAN/postinst"
find "$root" -type d -exec chmod 755 {} +
chmod 644 "$root/usr/share/applications/podsync.desktop" "$root/usr/share/icons/hicolor/512x512/apps/podsync.png"
dpkg-deb --root-owner-group -Zxz --build "$root" "$out" >/dev/null
rm -rf "$root"
echo "wrote $out"
