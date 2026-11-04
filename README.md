# PodSync

A podcast app for Android, Linux and Windows. It syncs subscriptions, episode progress, the queue, favorites and playback settings, and it can import an AntennaPod backup and sync with gPodder.

- `server/` — multi-user sync server in Go + SQLite, ready to run in Docker (`cd server && docker compose up -d`). See [server/README.md](server/README.md).
- `app/` — Flutter app. Android uses an AntennaPod-style UI, with an e-ink mode (black and white, paged lists, no scrolling or animation). Linux and Windows use an iTunes-style UI.

## Run

    cd server && docker compose up -d      # or: go run . -addr :8080
    cd app && flutter run -d linux      # or windows / an Android device

On Linux you need `libmpv` installed for playback, plus clang, cmake, ninja and the GTK dev packages to build. Open Settings (Android) or Account (desktop) to sign in.

## Moving over from AntennaPod

In AntennaPod: Settings > Import/Export > Database export. Then in PodSync: Settings > Import > Import AntennaPod backup, and pick the `AntennaPodBackup-<date>.db` file.

What comes across: every podcast (including unsubscribed ones that still have history) with its custom name, tags, speed, skip intro/ending and feed login; every episode with played state and listening position; listening history; the queue in its order; favorites; chapters. Merging is non-destructive: progress only replaces what is older, and an existing queue keeps its place at the front.

What does not: AntennaPod's app settings (they are not in its database export), downloaded audio files, the download log, and local-folder podcasts. OPML import/export is there too, for subscriptions only.

## Sync

Two backends, use either or both:

- **PodSync server** syncs everything. Records are keyed by type and key (`sub`, `progress`, `fav`, `queue`, `setting`); each carries a client timestamp and the newest write wins.
- **gPodder** (gpodder.net or any server speaking the v2 API, such as opodsync) syncs subscriptions and progress, so you can share an account with AntennaPod or gPodder on other devices. It has no queue or favorites. Not supported: the Nextcloud gPodder Sync app, which uses a different API.

gPodder timestamps have one-second resolution, so two devices changing the same episode within the same second may resolve either way.

## Windows

Download `PodSync-Setup-x64.exe` from the latest GitHub Actions run and run it. It installs for your user account (no admin rights needed) and can be removed from Settings > Apps. Windows may warn that the app is from an unknown publisher, because it is not code-signed yet: choose More info, then Run anyway.

## Status

Tested: the server (smoke test), feed parsing, both sync merges, the AntennaPod importer against a database built from AntennaPod's real table definitions, a fake gPodder server with two devices, and widget tests that render the desktop, phone and e-ink screens. Not yet done: building and running on any real platform. Nobody has seen these screens on a device, and playback, background audio and the file pickers are untested. Downloads and offline playback are not built.

## Updates

The apps look for new versions on github.com/Madmaxx636/podsync-releases (Settings > Advanced and about). To publish: push, wait for the Windows, Android, Linux and Server builds, then run `tools/release.sh X.Y.Z`. It downloads the CI builds, writes `SHA256SUMS.txt` and creates the release on both repositories. The checksum file is required; the apps refuse a download that does not match it. Keep `version:` in `app/pubspec.yaml` equal to the release tag.

## Linux

Download `PodSync-linux-x64.tar.gz`, unpack it and run `podsync/install.sh`. It installs for your user (no root) and adds a menu entry. PodSync plays audio with libmpv (`sudo apt install libmpv2` on Debian and Ubuntu). Updates then install from inside the app.
