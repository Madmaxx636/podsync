# Changelog

## 0.1.0 (unreleased)

First testable build.

- Podcast app for Android, Linux and Windows with an iTunes-style desktop UI and an AntennaPod-style phone UI.
- E-ink mode on Android: black and white, paged lists, no scrolling or animation.
- Sync through a self-hosted PodSync server (subscriptions, progress, queue, favorites, playback settings) and through gPodder (subscriptions and progress).
- Import an AntennaPod database backup or an OPML file.
- Settings for appearance, playback, library, sync, e-ink and desktop layout, plus per-podcast settings.
- Desktop back and forward navigation and right-click menus.
- Volume control: a slider and mute button on the desktop toolbar (mouse wheel works too) and on the phone player.
- Up Next queue overhaul: drag to reorder (whole selections move together), sort by date, title, podcast or time left from the column headings or a menu, shuffle, remove played, move up/down/top/bottom, Alt+arrows, and Undo for every change. Shows episodes, time left, when the queue ends, and when each episode would start.
- Star ratings that sync, with a Rating column and right-click rating.
- More of iTunes on the desktop: menu bar with keyboard shortcuts, Up Next popover, details pane, artwork pane, resizable sidebar, column chooser, time left or total on the LCD, Space to play and pause.
- Downloads: download any episode for offline listening (resumes after interruptions, Wi-Fi only option, simultaneous limit). Optional automatic downloads for the next episodes in Up Next and for new episodes, with per-podcast overrides, and automatic deletion once an episode is played (immediately or after a delay, keeping favorites). Downloaded files play offline. A Downloads screen shows progress, size and clean-up.
- Counts and totals: counts next to Podcasts, Episodes, Up Next, Favorites and Downloads; Up Next shows episode count, total length, time left and when it would finish; a Statistics screen shows listening time overall and per podcast.
- Sleep timer (15 minutes to 90 minutes, or end of episode) with a ten second fade, on the desktop toolbar, Controls menu and phone player.
- Episode filters (all, unplayed, downloaded, in Up Next, favorites) with counts.
- Removed the settings gear from the desktop toolbar; Settings stays in the sidebar, Account menu and Ctrl+,.
- Fixed: buttons inside episode rows reacted late because the row also handles double-clicks.
- Interface settings: show or hide the menu bar, sleep timer, volume, Up Next button, speed, search, back/forward arrows and skip buttons on the desktop toolbar; any sidebar section, the counts and the subscriptions list; the episode filters. On the phone: Downloads and Statistics in the menu, the mini player, the sleep timer, volume and speed on the player, the episode filters and the download icon on rows. Right-click the toolbar or sidebar to toggle items, so a hidden menu bar can always be brought back. Settings itself can never be hidden.
- Keyboard shortcuts no longer depend on the menu bar: they work with it shown, closed or hidden.
- Fixed: the mini player now hides at once when switched off in Settings.

