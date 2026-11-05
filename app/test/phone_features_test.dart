import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/common.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:podsync/ui/settings.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

const one = 'http://a.test/feed.xml|guid-1',
    two = 'http://a.test/feed.xml|guid-2';

Future<(Library, PlayerController)> pump(
  WidgetTester tester,
  Widget home, {
  bool eink = false,
  bool playing = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final path = makeAntennaPodBackup();
  final lib = Library();
  importAntennaPodBackup(lib, path);
  File(path).parent.deleteSync(recursive: true);
  lib.einkMode = eink;
  final player = PlayerController(lib);
  if (playing) player.current = lib.episodes[two];
  await tester.pumpWidget(
    MultiProvider(
      providers: testProviders(lib, player: player),
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  return (lib, player);
}

void main() {
  testWidgets('queue shows totals; the menu sorts, shuffles and undoes', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell());
    expect(find.textContaining('2 episodes'), findsOneWidget);
    expect(find.textContaining('ends about'), findsOneWidget);

    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort: Release date, oldest first'));
    await tester.pumpAndSettle();
    expect(lib.queue, [one, two]);
    expect(find.text('Queue sorted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(lib.queue, [two, one]);

    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove played episodes'));
    await tester.pumpAndSettle();
    expect(lib.queue, [two]); // Ep One is played in the fixture
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'e-ink: a visible menu button offers move up, down, top and bottom',
    (tester) async {
      final (lib, _) = await pump(tester, const MobileShell(), eink: true);
      expect(find.byType(Scrollable), findsNothing);
      expect(lib.queue, [two, one]);

      await tester.tap(
        find.byTooltip('More').first,
      ); // Ep Two, first in the queue
      await tester.pumpAndSettle();
      expect(find.text('Move up'), findsNothing); // already at the top
      expect(find.text('Move down'), findsOneWidget);
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(lib.queue, [one, two]);

      await tester.tap(find.byTooltip('More').first); // now Ep One
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to bottom'));
      await tester.pumpAndSettle();
      expect(lib.queue, [two, one]);
    },
  );

  testWidgets('the episode menu rates with stars', (tester) async {
    final (lib, _) = await pump(tester, const MobileShell(), eink: true);
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    final stars = find.descendant(
      of: find.byType(StarRating),
      matching: find.byIcon(Icons.star_border),
    );
    await tester.tap(stars.at(3));
    await tester.pumpAndSettle();
    expect(lib.ratingOf(two), 4);
  });

  testWidgets('player screen has a volume slider and a mute button', (
    tester,
  ) async {
    final (lib, player) = await pump(
      tester,
      const PlayerScreen(),
      playing: true,
    );
    final slider = find.byType(Slider).last; // the first slider is the seek bar
    expect(lib.settings.volume, 1.0);
    await tester.tap(slider); // tap the middle
    await tester.pump();
    expect(lib.settings.volume, closeTo(0.5, 0.08));
    expect(find.text('50%'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(lib.settings.muted, isTrue);
    expect(player.effectiveVolume, 0.0);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
  });

  group('settings', () {
    testWidgets(
      'Up Next group sorts and clears with undo; Playback group sets volume',
      (tester) async {
        final (lib, _) = await pump(tester, const SettingsPage('Up Next'));
        await tester.tap(find.text('Sort the queue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Release date, oldest first'));
        await tester.pumpAndSettle();
        expect(lib.queue, [one, two]);

        await tester.scrollUntilVisible(
          find.text('Clear Up Next'),
          200,
        ); // it is near the bottom of the list
        await tester.pump();
        await tester.tap(find.text('Clear Up Next'));
        await tester.pumpAndSettle();
        expect(lib.queue, isEmpty);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(lib.queue, [one, two]);
      },
    );

    testWidgets(
      'Playback group sets the volume and shows any level as a percentage',
      (tester) async {
        final (lib, _) = await pump(tester, const SettingsPage('Playback'));
        await tester.tap(find.text('Volume'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('60%'));
        await tester.pumpAndSettle();
        expect(lib.settings.volume, closeTo(0.6, 0.001));
        expect(find.text('60%'), findsOneWidget);

        // A level set by dragging a slider still reads as a percentage.
        lib.setSetting('volume', 0.673);
        await tester.pump();
        expect(find.text('67%'), findsOneWidget);
      },
    );
  });
}
