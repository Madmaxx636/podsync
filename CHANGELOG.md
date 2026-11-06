# Changelog

## 0.11.0 - 2026-11-06

Android.

- Tabs: Settings > Interface > Navigation. Put the tab bar at the top or the bottom, and choose which tabs show and in what order (drag to reorder, untick to remove one, for example Episodes). Tabs you remove move into the three-dot menu in the top corner. That menu replaces the old More tab, on colour and e-ink screens alike, and lists Downloads, Statistics and Settings.
- Long-press an episode for a list of actions in groups (play and queue, download, favourite and played, other) with Rating at the bottom, instead of a grid of buttons on e-ink. "Select several" starts multi-select.
- Multi-select: tap more episodes to add them, then use the bar at the bottom: Queue or Unqueue, Download or Remove, Played or Unplayed, Favorite, and More (Play next, move to top or bottom, remove downloads, clear). Back clears the selection.
- Interface size: Settings > Appearance has an Interface size slider (50% to 250%) that scales everything on the phone, and Text size is now a slider (70% to 200%). Both change by exactly 1% with the - and + buttons.
- Player bar at the bottom: Settings > Interface > Player bar sets its size (small, medium, large, extra large; the large sizes put the buttons on a second, bigger row) and lets you choose its buttons (skip back, play, skip forward, next) and their order.
- Player screen: choose which buttons show under the seek bar and their order, and raise them up from the bottom edge (Settings > Interface > Player screen).
- Cast: the cast icon on the player screen lists Chromecasts, Google TVs and other Cast devices on your Wi-Fi and plays the episode there from where you are. Play, pause, seek and skip then control the TV, the episode moves on through Up Next, and "Play on this device instead" brings it back.
- Android Auto: PodSync shows up in the car with Up Next, New episodes, Downloaded and Podcasts (each with its episodes) and plays from them.
- Statistics (Subscriptions, Years and Downloads pages with a gauge and monthly bars) now on the phone too.

## 0.10.0 - 2026-11-06

- Up Next: the column headings no longer re-sort the queue; the order is only what you set by dragging or with Move to Top / Bottom. Time left now counts down while the episode plays. New Starts at and Ends at columns show the clock time each episode would begin and end, at each podcast's playback speed (Tomorrow or the weekday is added when it is not today). Turn them on or off in the column menu, View > Columns and Settings.
- Selecting several episodes: Ctrl-click, Shift-click or Ctrl+A in any episode list. A bar appears under the list with Add to / Remove from Up Next, Move to top and bottom (Up Next), Download, Delete downloads, Mark played or unplayed and Favorite for the whole selection; the right-click menu still works on it too.
- Sizes: Settings > Appearance has an Interface size slider (50% to 250%) and a Text size slider (70% to 200%), each with - and + buttons that change it by exactly 1%, the number beside the slider and a reset. New Scale with the window option makes everything grow and shrink with the window width.
- Statistics redone with three pages: Subscriptions (a gauge with your total listening time split between your three biggest podcasts and the rest, and a ranked list with bars), Years (time played per month as bars coloured by year, with the total for each year) and Downloads (a gauge with the total size and the size per podcast).

## 0.9.1 - 2026-11-06

- Android notification: the back and forward buttons now use your own skip lengths from Settings (5 to 90 seconds), with the number drawn on the button and in its label, and they update when you change the setting. The notification keeps the cover, episode title and podcast name, play/pause and next, and its seek bar.
- Android widgets: the back and forward buttons on the Now Playing widget show your skip lengths, and it now shows time played and time left. The small play/pause widget is now a control strip with the cover, episode and podcast, back, play/pause and forward.

## 0.9.0 - 2026-11-05

- Customize Toolbar: right-click the top bar (or View > Customize Toolbar…) to edit it. Drag the parts into any order (anything left of the display sits on its left, anything right of it on its right), tick them on or off, and size them with sliders: bar height, button size, display width, search width and volume width. Reset puts it all back; Done closes the editor. Choices are kept per device.
- Mini player redone like iTunes': a square window with the cover filling it, the title across the top, and a dark translucent panel at the bottom with rewind, play/pause, fast-forward, next and a scrubber with both times. It also no longer breaks when the window manager refuses to move or maximize the window, and it restores a maximized window when you go back.

## 0.8.0 - 2026-11-05

- Settings now sync between your devices through the PodSync server (desktop and Android). Synced: theme, accent colour, text size, compact layout, artwork and date format; playback and library options; download rules (auto-download, auto-delete, Wi-Fi only, how many at once); refresh and sync schedules; notifications; the store country. Kept on each device: window layout and zoom, column widths, which buttons are shown, tray and start-up options, the download folder, volume, e-ink options and update choices. A change on one device shows up on the others at their next sync; if both change, the most recent change wins.

## 0.7.1 - 2026-11-05

- Desktop top bar redone to match iTunes' proportions: a shorter bar, round transport buttons close together (play slightly larger), a short volume slider, and a wide centred display with the cover, centred title and podcast, and the scrubber with the time at each end.
- More room between the Up Next, Downloads and sleep timer buttons.

## 0.7.0 - 2026-11-05

- Fixed: after closing PodSync to the tray, clicking its icon on the taskbar or desktop opened a second copy. A second launch now just brings the running window back (Windows and Linux).
- The Downloads dropdown hangs under its own button instead of sitting on top of Up Next, and lists only what is downloading, waiting or failed. Finished downloads are on the Downloads screen (Show All).
- Click the cover in the top bar to open a mini player: a small always-on-top strip with the cover, title, scrubber and transport. Click the cover or the expand button to get the full window back (also View > Mini Player).
- The artwork under the sidebar has a small close button; View > Show Artwork Pane brings it back.
- Sharper, larger text in the top bar, status bar, sidebar and episode table, and a darker secondary text colour.
- Zoom the whole window with Ctrl + mouse wheel, Ctrl + / Ctrl - and Ctrl 0 (also View menu and Settings > Appearance > Zoom, 80% to 200%).
- Episode table columns can be resized by dragging the edge between two headings; double-click the edge to reset. Widths are remembered.
- Desktop settings reorganised: pages grouped under Listening, Library, Display and About, a search box that finds any setting, a title for each page, and Desktop layout split into Window and Episode table sections.

## 0.6.0 - 2026-11-05

- Android notification and lock screen rebuilt: cover art, episode and podcast name, a seek bar, and four buttons: rewind 10 s, play/pause, fast-forward 30 s and next in Up Next (the first three show when it is collapsed). Pressing play with nothing loaded starts Up Next. A proper one-colour status-bar icon.
- Three home-screen widgets: **Now playing** (cover, title, progress, rewind / play-pause / fast-forward / next), **Up Next** (the next four episodes; tap one to play it) and **Play / pause** (one button with the title). They follow light and dark mode and update as you listen. Add them from the launcher's widget list or from Settings > Interface > Home screen widgets.
- Settings > Interface: Open on (the start screen, added in 0.5.4).

## 0.5.4 - 2026-11-05

- New setting, Settings > Interface > Open on: choose the screen PodSync starts on. Phone: Up Next (default), Episodes, Podcasts, Add podcast, Downloads, Statistics. Desktop: Episodes (default), Podcasts, Up Next, Favorites, Recently Played, Downloads, Statistics, Podcast Store. Both also offer "Where I left off", which reopens the last screen you used. It is per device.

## 0.5.3 - 2026-11-05

- Desktop: headphone and keyboard media buttons (Play/Pause, Next, Previous, Stop) now control PodSync on Windows through a direct key hook, so they work even when Windows would have handed them to a browser. PodSync takes the key only while it is what you are listening to (playing, or paused in the last half hour) and leaves it for other apps otherwise. The system media overlay and Linux's MPRIS controls stay as before.
- Each desktop integration step (tray icon, closing to the tray, start at login, notifications, taskbar buttons, media controls) now runs on its own, so one failing step cannot stop the others; Settings > System shows what is Active or why something is not working.
- Release builds on GitHub retry installing system packages instead of hanging.

## 0.5.2 - 2026-11-05

- Settings are compact, like AntennaPod's: plain icons, bold titles with a short description, tighter spacing, small headings between groups, and a Search box at the top that finds any setting and lets you change it right there. E-ink pages fit more rows because headings and short rows take less room.
- Per-podcast filter, sort and settings, as on AntennaPod's podcast page. Under the cover: info, Filter, Sort and Settings. Filter episodes with pairs of choices (Played / Not played, Paused / Not paused, Is favorite / Not favorite, Has media / No media, Queued / Not queued, Downloaded / Not downloaded; Confirm or Reset). Sort by title, duration or date, or follow the global order; tapping again flips the direction. The page says "Filtered" while a filter is on.
- A new Podcast settings page: custom name and tags; the episode filter and sort order; playback speed and skip intro/ending; Keep updated (leave this podcast out of "refresh all"), episode notifications, delete after playing, new-episodes action and auto-download; feed login; copy the feed address; unsubscribe. Changes apply at once and sync. The desktop has the same page in a window, with Filter and Sort buttons on a podcast's header.

## 0.5.1 - 2026-11-05

- Settings reorganised: the home screen is grouped under Listening (Playback, Up Next, Downloads), Library (Library and feeds, Podcasts, Sync, Import and backup), Display (Appearance, Interface, E-ink) and About, each page with its own coloured icon; long pages such as Downloads have section headings and thin dividers. E-ink keeps the same layout, black and white and paged.
- With e-ink mode on, the settings that only apply to colour screens (Theme, Accent colour, Compact layout) are hidden. The E-ink page shows just the switch until you turn e-ink on, then its extra options.
- The download folder now works. Tapping it opens a chooser: In PodSync (default), Phone storage, SD card when there is one, or "Choose a folder..." which opens Android's folder picker. Folders outside the app's own storage need Android's All files access; PodSync explains, opens the right Android page, and finishes choosing the folder when you come back. Episodes already downloaded stay where they are. On Windows and Linux it opens the system folder picker.

## 0.5.0 - 2026-11-05

- Fixed: the "Up Next cleared" (and "sorted") banner with an Undo button never went away. It now disappears after six seconds.
- Windows: playback buttons (previous, play/pause, next) in the taskbar preview when you hover over PodSync, plus a progress bar on the taskbar icon. Desktop notifications for new episodes, finished downloads and (optionally) when the next episode starts, shown only while PodSync is not in front. All of it can be switched off in Settings > System.
- Desktop look closer to iTunes 12: a second toolbar row with the joined back/forward control, a menu of places and Library / Store tabs in blue; a joined segmented filter control instead of chips; larger transport buttons and a grey volume slider; a neutral grey sidebar with Title-case headings.

## 0.4.0 - 2026-11-05

- Phone redesign after AntennaPod, one look for both kinds of screen. Colour phones get the bottom bar (Queue, Episodes, Podcasts, Add, More) with counts; e-ink gets browser-style tabs along the top (the selected tab is outlined and open at the bottom), black and white, no animation, paged. Both share the big screen titles, the episode rows (date, size, bold title, time or progress with elapsed and remaining, big round play button), the mini player with a progress line along its top edge, and the player (collapse arrow, favourite, sleep timer, menu, cover, podcast and date, title, Shownotes button, seek bar, speed, rewind, round play button, forward, next).
- E-ink buttons and chips are square-cornered instead of pills.
- Automatic updates: Windows and Linux install a new version at start-up without asking (switch in Settings > Advanced and about); the server updates itself every night from GitHub (`scripts/auto-update.sh`, offered by the setup wizard).
- The repository is public.
- Desktop (Windows and Linux) system integration, under Settings > System: a tray icon with Show, Play/Pause, Skip back, Skip forward, Next and Quit; closing the window can keep PodSync playing from the tray (on by default); start when you sign in, optionally hidden in the tray; and media keys plus the system's now-playing controls (Windows' media overlay and lock screen, Linux's MPRIS: GNOME, KDE, `playerctl`). The Linux .deb now depends on the AppIndicator library for the tray.
- Episode page after AntennaPod: compact header, one plain Play / Delete row (Chapters when there are some), everything else in the top-right menu.
- Desktop speed: the library's episodes are stored in their own file and rewritten only when they change (saving progress every few seconds used to rewrite everything); the position clock redraws twice a second instead of five times; the menu bar and details pane no longer rebuild on every tick; sorting a long episode list works out its sort keys once.

## 0.3.1 - 2026-11-04

- Linux: a .deb package, `PodSync-linux-x64.deb` (`sudo apt install ./PodSync-linux-x64.deb`). It installs to /opt/podsync with a menu entry and icon, and pulls in GTK and libmpv. When PodSync was installed from the .deb, in-app updates download the new .deb, check it, and install it through the system password prompt. The tar.gz install still updates itself without a password.

## 0.3.0 - 2026-11-04

- Linux build: `PodSync-linux-x64.tar.gz` with an install script (installs for your user, adds a menu entry) and in-app updates that unpack the new version over the old one. PodSync needs libmpv for audio (`sudo apt install libmpv2`).
- Now Playing: the current chapter shows under the title, and swiping up (or tapping "Show notes") opens AntennaPod's slide-up panel with the show notes and a tappable chapter list.
- Phone: Copy episode link in the episode menu; on a podcast page, Mark all as played or unplayed and Copy feed address.
- Updates: a finished update download is reused if you tap Install again; the Linux build checks that its folder is writable first.
- Server: GitHub builds, tests and smoke-tests the Docker image on every push and publishes it to GitHub's container registry for each version (`ghcr.io/madmaxx636/podsync-server`). The image reports its version.
- Releasing is now one command, `tools/release.sh X.Y.Z`.

## 0.2.0 - 2026-11-04

- Updates from GitHub. PodSync checks the public releases page when it opens (and once a day while it stays open) and offers a newer version in a dialog: Install, Later, or Skip this version. Windows downloads the installer, checks it against the release's SHA-256 list, installs quietly and restarts PodSync. Android downloads and checks the APK, then hands it to the system installer (it asks once to allow installs from PodSync, then once per update to confirm). A download that does not match its checksum is never run. On Linux the dialog opens the releases page.
- Settings > Advanced and about: the version, a switch for automatic checks, and Check for updates now.
- Releases now live in a public repository, github.com/Madmaxx636/podsync-releases, so the apps need no login to see them.

## 0.1.1 - 2026-11-04

- Now Playing redesigned to match AntennaPod: a collapse arrow, full-width cover, episode and podcast name, seek bar with elapsed and remaining time, and a control row with the speed button, rewind, a large play button, fast-forward and skip.

## 0.1.0 - 2026-11-04

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
- Windows now comes as an installer (`PodSync-Setup-x64.exe`) instead of a zip. It installs for the current user, so it needs no admin rights, adds a Start menu entry (and an optional desktop shortcut) and an uninstaller. Uninstalling keeps your library and downloads.
- Podcast store redesigned like the iTunes Store: a search bar and category menu, top podcasts as covers, a ranked Top Charts list, Subscribe buttons on every podcast, charts per category and per country. The phone has the same charts as a ranked list.
- Downloads dropdown next to Up Next, with live progress, waiting and failed downloads (retry or dismiss) and the latest finished ones.
- Fixed downloads (and feeds) that failed with "Redirect limit exceeded": podcast links that pass through several tracking services are now followed, with cookies, up to 30 hops. Error messages no longer lose words ("ClientRedirect limit exceeded").
- Android: release builds are signed with a fixed key, the app has an icon and is named PodSync, and it asks for the notification permission Android 13 and later need for playback controls. A GitHub Actions workflow builds the APK; each build updates the last one in place.
- Server rebuilt for Docker: a ~20 MB image, `docker compose up -d`, data in one volume. Many people per server with isolated data, an admin command line (`user add/list/passwd/delete`, `backup`), self-registration you can switch off, hashed session tokens, login throttling, per-device sign-out, and password change. See server/README.md.
- The app shows the server's own error sentences and signs out on the server too.

- Tested on an Android 15 emulator in normal and e-ink mode, against a running server (sign-up, sync, streaming, download, offline playback). Fixed what that turned up: the e-ink play button was a black circle with no icon; the Episodes filter chips were cut off ("Offli…") and the selected one was unreadable on e-ink; episode rows with a two-line title and a progress bar overflowed by a few pixels; the page buttons used coloured emoji arrows; the episode screen said "Favorite?".
- A proper empty Up Next screen: says what the queue is for and offers "Find podcasts" (no subscriptions yet) or "Browse episodes".
- The Android APK now includes x86_64 as well as ARM, so it also installs on emulators and Chromebooks.
