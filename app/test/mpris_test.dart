// Run under a D-Bus session to exercise the real bus:  dbus-run-session -- flutter test test/mpris_test.dart
// Without one (CI), the test skips itself.
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/mpris.dart';
import 'package:podsync/core/player.dart';

import 'fixtures.dart';

class _CountingPlayer extends PlayerController {
  _CountingPlayer(super.library);
  final calls = <String>[];
  @override
  Future<void> toggle() async => calls.add('toggle');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> skipBack() async => calls.add('skipBack');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hasBus =
      (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;

  test(
    'MPRIS: media keys and playerctl-style calls reach the player',
    () async {
      final lib = Library();
      importAntennaPodBackup(lib, makeAntennaPodBackup());
      final player = _CountingPlayer(lib)
        ..current = lib.episodes['http://a.test/feed.xml|guid-2'];
      final service = MprisService(
        player: player,
        lib: lib,
        onRaise: () {},
        onQuit: () {},
      );
      await service.start();

      final client = DBusClient.session();
      final remote = DBusRemoteObject(
        client,
        name: 'org.mpris.MediaPlayer2.podsync',
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
      );
      const iface = 'org.mpris.MediaPlayer2.Player';
      await remote.callMethod(iface, 'PlayPause', []);
      await remote.callMethod(iface, 'Next', []);
      await remote.callMethod(iface, 'Previous', []);
      expect(player.calls, ['toggle', 'next', 'skipBack']);

      final status = await remote.getProperty(iface, 'PlaybackStatus');
      expect(
        status.asString(),
        'Paused',
      ); // an episode is loaded and not playing
      final meta = (await remote.getProperty(
        iface,
        'Metadata',
      )).asStringVariantDict();
      expect(meta['xesam:title']?.asString(), 'Ep Two');
      final identity = await remote.getProperty(
        'org.mpris.MediaPlayer2',
        'Identity',
      );
      expect(identity.asString(), 'PodSync');

      await client.close();
      await service.stop();
    },
    skip: hasBus ? false : 'needs a D-Bus session (dbus-run-session)',
  );
}
