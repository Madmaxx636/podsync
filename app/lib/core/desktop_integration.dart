import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:local_notifier/local_notifier.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'downloads.dart';
import 'library.dart';
import 'models.dart';
import 'mpris.dart';
import 'windows_media_keys.dart';
import 'player.dart';

/// Windows and Linux system integration: a tray icon, closing to the tray, starting at login, and
/// the system's media controls (media keys, now-playing widgets).
class DesktopIntegration with TrayListener, WindowListener {
  DesktopIntegration(this.lib, this.player, {this.downloads});

  final Library lib;
  final PlayerController player;
  final DownloadManager? downloads;

  bool _focused = true;
  bool _notifierReady = false;
  String _lastNotifiedId = '';
  DateTime _lastTaskbarProgress = DateTime.fromMillisecondsSinceEpoch(0);

  bool _trayOn = false;
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _smtcButtons;
  MprisService? _mpris;
  WindowsMediaKeys? _keys;
  DateTime _lastKey = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastKeyCommand = '';
  DateTime _lastPlaying = DateTime.fromMillisecondsSinceEpoch(0);
  String _settingsKey = '';
  String _playerKey = '';

  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// What each part is doing, for Settings > System: 'Active' or why it is not working.
  static final Map<String, String> status = {};

  /// Whether this launch should stay hidden (started at login, with the tray icon to open it).
  static bool startHidden(Library lib, List<String> args) =>
      args.contains('--minimized') &&
      lib.settings.startMinimized &&
      lib.settings.trayIcon;

  /// Call before `runApp`: sets up the window and shows or hides it.
  static Future<void> prepareWindow(Library lib, List<String> args) async {
    await windowManager.ensureInitialized();
    final hidden = startHidden(lib, args);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(minimumSize: const Size(720, 480), skipTaskbar: hidden),
      () async {
        if (hidden) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
  }

  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    lib.addListener(_onSettings);
    player.addListener(_onPlayer);
    // Notifications: new episodes found by a refresh, and finished downloads.
    final previous = lib.onNewEpisodes;
    lib.onNewEpisodes = (podcast, arrivals) {
      previous?.call(podcast, arrivals);
      _notifyNew(podcast, arrivals);
    };
    downloads?.onFinished = _notifyDownloaded;
    await _applySettings(first: true);
  }

  // ---- settings ------------------------------------------------------------------------

  void _onSettings() {
    final s = lib.settings;
    final key =
        '${s.trayIcon}|${s.closeToTray}|${s.startAtLogin}|${s.startMinimized}|${s.mediaControls}|${s.taskbarControls}';
    if (key == _settingsKey) return;
    _applySettings();
  }

  /// Runs one setup step on its own: a failure is recorded (and shown in Settings > System)
  /// instead of stopping the steps after it.
  Future<void> _step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e, st) {
      status[name] = 'Not working: $e';
      // ignore: avoid_print
      print('Desktop integration ($name): $e\n$st');
    }
  }

  Future<void> _applySettings({bool first = false}) async {
    final s = lib.settings;
    _settingsKey =
        '${s.trayIcon}|${s.closeToTray}|${s.startAtLogin}|${s.startMinimized}|${s.mediaControls}|${s.taskbarControls}';
    await _step('Tray icon', () async {
      if (s.trayIcon && !_trayOn) await _showTray();
      if (!s.trayIcon && _trayOn) await _hideTray();
      status['Tray icon'] = s.trayIcon ? 'Active' : 'Off';
    });
    await _step('Closing the window', () async {
      // Without a tray icon there would be no way back to a hidden window, so closing quits.
      await windowManager.setPreventClose(s.closeToTray && _trayOn);
    });
    await _step('Start at login', () => _setStartAtLogin(s.startAtLogin));
    await _step('Notifications', _setupNotifier);
    await _step('Taskbar buttons', () async {
      _taskbarKey = '';
      await _updateTaskbar();
    });
    await _step('Media controls', () async {
      if (s.mediaControls) {
        await _startMedia();
      } else {
        await _stopMedia();
        status['Media controls'] = 'Off';
      }
    });
  }

  // ---- window and tray -----------------------------------------------------------------

  @override
  void onWindowFocus() => _focused = true;

  @override
  void onWindowBlur() => _focused = false;

  @override
  void onWindowClose() async {
    if (lib.settings.closeToTray && _trayOn) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } else {
      await quit();
    }
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    _taskbarKey = '';
    _updateTaskbar();
  }

  Future<void> quit() async {
    await lib.saveNow();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  Future<void> _showTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icon/tray.ico' : 'assets/icon/tray.png',
    );
    if (Platform.isWindows) await trayManager.setToolTip('PodSync');
    _trayOn = true;
    await _updateTrayMenu();
  }

  Future<void> _hideTray() async {
    _trayOn = false;
    await trayManager.destroy();
  }

  Future<void> _updateTrayMenu() async {
    if (!_trayOn) return;
    final e = player.current;
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show PodSync'),
          MenuItem.separator(),
          MenuItem(
            key: 'toggle',
            label: player.playing ? 'Pause' : 'Play',
            disabled: e == null,
          ),
          MenuItem(key: 'back', label: 'Skip back', disabled: e == null),
          MenuItem(key: 'forward', label: 'Skip forward', disabled: e == null),
          MenuItem(key: 'next', label: 'Next in Up Next'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit PodSync'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'toggle':
        if (player.current != null) player.toggle();
      case 'back':
        player.skipBack();
      case 'forward':
        player.skipForward();
      case 'next':
        player.next();
      case 'quit':
        quit();
    }
  }

  // ---- start at login ------------------------------------------------------------------

  Future<void> _setStartAtLogin(bool on) async {
    final exe = Platform.resolvedExecutable;
    if (Platform.isWindows) {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
      if (on) {
        await Process.run('reg', [
          'add',
          key,
          '/v',
          'PodSync',
          '/t',
          'REG_SZ',
          '/d',
          '"$exe" --minimized',
          '/f',
        ]);
      } else {
        await Process.run('reg', ['delete', key, '/v', 'PodSync', '/f']);
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final dir = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
      final file = File('$dir/autostart/podsync.desktop');
      if (on) {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '[Desktop Entry]\nType=Application\nName=PodSync\n'
          'Exec="$exe" --minimized\nX-GNOME-Autostart-enabled=true\n',
        );
      } else if (await file.exists()) {
        await file.delete();
      }
    }
  }

  // ---- media controls ------------------------------------------------------------------

  Future<void> _startMedia() async {
    if (Platform.isWindows) {
      // 1. The key hook: headphone and keyboard media keys, whichever app Windows would pick.
      if (_keys == null) {
        final keys = WindowsMediaKeys(_mediaKey);
        try {
          if (keys.start()) {
            _keys = keys;
          } else {
            status['Media keys'] =
                'Not working: Windows would not install the key hook';
          }
        } catch (e) {
          status['Media keys'] = 'Not working: $e';
        }
        if (_keys != null) status['Media keys'] = 'Active';
      }
      // 2. The system media overlay and lock screen.
      if (_smtc == null) {
        await SMTCWindows.initialize();
        final smtc = SMTCWindows(
          config: const SMTCConfig(
            playEnabled: true,
            pauseEnabled: true,
            nextEnabled: true,
            prevEnabled: true,
            stopEnabled: true,
            fastForwardEnabled: true,
            rewindEnabled: true,
          ),
        );
        _smtc = smtc;
        _smtcButtons = smtc.buttonPressStream.listen(_smtcPressed);
        await _updateSmtc();
      }
      status['Media controls'] = 'Active (Windows media overlay)';
    } else if (Platform.isLinux && _mpris == null) {
      final m = MprisService(
        player: player,
        lib: lib,
        onRaise: showWindow,
        onQuit: quit,
      );
      await m.start();
      _mpris = m;
      status['Media controls'] =
          'Active (MPRIS: media keys, GNOME/KDE widgets, playerctl)';
    }
  }

  /// A media key seen by the Windows hook. PodSync takes the key when it is what the person is
  /// listening to (playing now, or paused a short while ago) and leaves it for other apps otherwise.
  bool _mediaKey(String command) {
    if (player.playing) _lastPlaying = DateTime.now();
    final mine =
        player.current != null &&
        (player.playing ||
            DateTime.now().difference(_lastPlaying) <
                const Duration(minutes: 30));
    if (!mine) return false;
    // A key can reach us twice (the hook and the system's media session): act once.
    final now = DateTime.now();
    if (command == _lastKeyCommand &&
        now.difference(_lastKey) < const Duration(milliseconds: 400)) {
      return true;
    }
    _lastKey = now;
    _lastKeyCommand = command;
    Future.microtask(() {
      switch (command) {
        case 'playpause':
          player.toggle();
        case 'next':
          player.next();
        case 'previous':
          player.skipBack();
        case 'stop':
          if (player.playing) player.toggle();
      }
    });
    return true;
  }

  Future<void> _stopMedia() async {
    _keys?.stop();
    _keys = null;
    await _smtcButtons?.cancel();
    _smtcButtons = null;
    await _smtc?.dispose();
    _smtc = null;
    await _mpris?.stop();
    _mpris = null;
  }

  void _smtcPressed(PressedButton b) {
    switch (b) {
      case PressedButton.play:
        if (!player.playing && player.current != null) player.toggle();
      case PressedButton.pause:
      case PressedButton.stop:
        if (player.playing) player.toggle();
      case PressedButton.next:
        player.next();
      case PressedButton.previous:
      case PressedButton.rewind:
        player.skipBack();
      case PressedButton.fastForward:
        player.skipForward();
      default:
        break;
    }
  }

  void _onPlayer() {
    final key = '${player.current?.id}|${player.playing}';
    if (key == _playerKey) return;
    if (player.playing) _lastPlaying = DateTime.now();
    final episodeChanged = player.current?.id != _lastNotifiedId;
    _playerKey = key;
    _updateTrayMenu();
    _updateSmtc();
    _updateTaskbar();
    final e = player.current;
    if (e != null && episodeChanged && player.playing) {
      _lastNotifiedId = e.id;
      if (lib.settings.notifyNowPlaying && !_focused) {
        _notify('Now playing', '${e.title}\n${lib.podcastTitle(e.feedUrl)}');
      }
    }
  }

  // ---- notifications -------------------------------------------------------------------

  Future<void> _setupNotifier() async {
    if (_notifierReady) return;
    try {
      await localNotifier.setup(
        appName: 'PodSync',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _notifierReady = true;
    } catch (_) {}
  }

  void _notify(String title, String body) {
    if (!_notifierReady) return;
    final n = LocalNotification(title: title, body: body);
    n.onClick = showWindow;
    n.show();
  }

  void _notifyNew(Podcast podcast, List<Episode> arrivals) {
    if (!lib.settings.notifyNewEpisodes || _focused || arrivals.isEmpty) return;
    final first = arrivals.first.title;
    _notify(
      podcast.displayTitle,
      arrivals.length == 1 ? first : '$first\nand ${arrivals.length - 1} more',
    );
  }

  void _notifyDownloaded(String id) {
    final e = lib.episodes[id];
    if (e == null || !lib.settings.notifyDownloads || _focused) return;
    _notify('Download finished', e.title);
  }

  // ---- Windows taskbar: buttons in the hover preview, progress on the icon ------------

  String _taskbarKey = '';

  Future<void> _updateTaskbar() async {
    if (!Platform.isWindows) return;
    try {
      if (!lib.settings.taskbarControls) {
        if (_taskbarKey != 'off') {
          _taskbarKey = 'off';
          await WindowsTaskbar.resetThumbnailToolbar();
          await WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
        }
        return;
      }
      final e = player.current;
      final key = '${e?.id}|${player.playing}';
      if (key != _taskbarKey) {
        _taskbarKey = key;
        final has = e != null;
        await WindowsTaskbar.setThumbnailToolbar([
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon('assets/icon/tb_prev.ico'),
            'Skip back',
            player.skipBack,
            mode: has ? 0 : ThumbnailToolbarButtonMode.disabled,
          ),
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon(
              player.playing
                  ? 'assets/icon/tb_pause.ico'
                  : 'assets/icon/tb_play.ico',
            ),
            player.playing ? 'Pause' : 'Play',
            () {
              if (player.current != null) player.toggle();
            },
            mode: has ? 0 : ThumbnailToolbarButtonMode.disabled,
          ),
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon('assets/icon/tb_next.ico'),
            'Next in Up Next',
            player.next,
          ),
        ]);
        if (e != null) await WindowsTaskbar.setThumbnailTooltip(e.title);
      }
      // Progress along the taskbar icon, about once a second.
      final now = DateTime.now();
      final total = player.duration.inMilliseconds;
      if (e != null &&
          total > 0 &&
          now.difference(_lastTaskbarProgress) > const Duration(seconds: 1)) {
        _lastTaskbarProgress = now;
        await WindowsTaskbar.setProgressMode(
          player.playing
              ? TaskbarProgressMode.normal
              : TaskbarProgressMode.paused,
        );
        await WindowsTaskbar.setProgress(player.position.inMilliseconds, total);
      } else if (e == null) {
        await WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
      }
    } catch (_) {}
  }

  Future<void> _updateSmtc() async {
    final smtc = _smtc;
    if (smtc == null) return;
    final e = player.current;
    try {
      if (e == null) {
        await smtc.setPlaybackStatus(PlaybackStatus.stopped);
        return;
      }
      await smtc.updateMetadata(
        MusicMetadata(
          title: e.title,
          artist: lib.podcastTitle(e.feedUrl),
          album: lib.podcastTitle(e.feedUrl),
          thumbnail: e.imageUrl.isEmpty ? null : e.imageUrl,
        ),
      );
      await smtc.updateTimeline(
        PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: player.duration.inMilliseconds,
          positionMs: player.position.inMilliseconds,
        ),
      );
      await smtc.setPlaybackStatus(
        player.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    } catch (_) {}
  }
}
