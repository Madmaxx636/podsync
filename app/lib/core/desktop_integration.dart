import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:smtc_windows/smtc_windows.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'library.dart';
import 'mpris.dart';
import 'player.dart';

/// Windows and Linux system integration: a tray icon, closing to the tray, starting at login, and
/// the system's media controls (media keys, now-playing widgets).
class DesktopIntegration with TrayListener, WindowListener {
  DesktopIntegration(this.lib, this.player);

  final Library lib;
  final PlayerController player;

  bool _trayOn = false;
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _smtcButtons;
  MprisService? _mpris;
  String _settingsKey = '';
  String _playerKey = '';

  static bool get supported => Platform.isWindows || Platform.isLinux;

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
    await _applySettings(first: true);
  }

  // ---- settings ------------------------------------------------------------------------

  void _onSettings() {
    final s = lib.settings;
    final key =
        '${s.trayIcon}|${s.closeToTray}|${s.startAtLogin}|${s.startMinimized}|${s.mediaControls}';
    if (key == _settingsKey) return;
    _applySettings();
  }

  Future<void> _applySettings({bool first = false}) async {
    final s = lib.settings;
    _settingsKey =
        '${s.trayIcon}|${s.closeToTray}|${s.startAtLogin}|${s.startMinimized}|${s.mediaControls}';
    try {
      if (s.trayIcon && !_trayOn) await _showTray();
      if (!s.trayIcon && _trayOn) await _hideTray();
      // Without a tray icon there would be no way back to a hidden window, so closing quits.
      await windowManager.setPreventClose(s.closeToTray && _trayOn);
      await _setStartAtLogin(s.startAtLogin);
      if (s.mediaControls) {
        await _startMedia();
      } else {
        await _stopMedia();
      }
    } catch (e) {
      // None of this is essential; the app works without it.
      // ignore: avoid_print
      print('Desktop integration: $e');
    }
  }

  // ---- window and tray -----------------------------------------------------------------

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
    if (Platform.isWindows && _smtc == null) {
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
    } else if (Platform.isLinux && _mpris == null) {
      final m = MprisService(
        player: player,
        lib: lib,
        onRaise: showWindow,
        onQuit: quit,
      );
      await m.start();
      _mpris = m;
    }
  }

  Future<void> _stopMedia() async {
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
    _playerKey = key;
    _updateTrayMenu();
    _updateSmtc();
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
