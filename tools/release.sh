#!/bin/bash
# Publishes the builds of the current commit as release vX.Y.Z on the public releases repository
# (the one the apps check for updates) and on this repository.
#   tools/release.sh 0.3.0            all platforms
#   tools/release.sh 0.3.1 --android  Android only: needs just the Android build and ships just
#                                     the APK (the desktop apps ignore a release without their installer)
# Needs: `gh` logged in, CI finished and green for HEAD (Windows, Android, Linux), the
# version in app/pubspec.yaml and a "## X.Y.Z" entry in CHANGELOG.md.
set -euo pipefail
V="${1:?usage: tools/release.sh X.Y.Z [--android]}"
android_only=false; [ "${2:-}" = "--android" ] && android_only=true
if $android_only; then builds=("Android build"); files=(PodSync-android.apk); else builds=("Windows build" "Android build" "Linux build"); files=(PodSync-Setup-x64.exe PodSync-android.apk PodSync-linux-x64.tar.gz PodSync-linux-x64.deb); fi
cd "$(dirname "$0")/.."
HEAD_SHA=$(git rev-parse HEAD)
grep -q "^version: $V+" app/pubspec.yaml || { echo "app/pubspec.yaml is not at version $V"; exit 1; }
grep -q "^## $V" CHANGELOG.md || { echo "CHANGELOG.md has no entry for $V"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first"; exit 1; }
git diff --quiet "origin/$(git branch --show-current)" || { echo "Push your commits first"; exit 1; }

work=$(mktemp -d)
for wf in "${builds[@]}"; do
  id=$(gh run list --commit "$HEAD_SHA" --workflow "$wf" --json databaseId,conclusion -q '.[0]|select(.conclusion=="success")|.databaseId')
  [ -n "$id" ] || { echo "$wf has not finished green for $HEAD_SHA"; exit 1; }
  gh run download "$id" -D "$work/$id"
done
mkdir "$work/out"
for f in "${files[@]}"; do
  src=$(find "$work" -name "$f" | head -1)
  (cd "$(dirname "$src")" && sha256sum -c "$f.sha256")
  cp "$src" "$work/out/"
done
(cd "$work/out" && sha256sum * > SHA256SUMS.txt)
{
  awk -v v="$V" '$0 ~ "^## "v {f=1; next} f && /^## /{exit} f' CHANGELOG.md
  printf '\nSHA-256\n```\n'; cat "$work/out/SHA256SUMS.txt"; printf '```\n'
} > "$work/notes.md"
gh release create "v$V" -R Madmaxx636/podsync-releases --title "PodSync $V" --notes-file "$work/notes.md" "$work"/out/*
gh release create "v$V" --target "$HEAD_SHA" --title "PodSync $V" --notes-file "$work/notes.md" "$work"/out/*
