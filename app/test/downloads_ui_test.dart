import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:podsync/ui/settings.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

const one = 'http://a.test/feed.xml|guid-1',
    two = 'http://a.test/feed.xml|guid-2';

class Rig {
  Rig(this.lib, this.dm, this.player, this.dir);
  final Library lib;
  final DownloadManager dm;
  final PlayerController player;
  final Directory dir;
}

Future<Rig> pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1300, 850),
  double ratio = 1,
  bool eink = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final path = makeAntennaPodBackup();
  final lib = Library();
  importAntennaPodBackup(lib, path);
  File(path).parent.deleteSync(recursive: true);
  lib.einkMode = eink;
  final dir = Directory.systemTemp.createTempSync('podsync_ui_dl');
  addTearDown(() => dir.deleteSync(recursive: true));
  final dm = DownloadManager(
    lib,
    client: MockClient.streaming(
      (r, body) async => http.StreamedResponse(
        Stream.value(List.filled(5000, 1)),
        200,
        contentLength: 5000,
      ),
    ),
    directory: Directory('${dir.path}/files'),
    indexFile: File('${dir.path}/index.json'),
    watchNetwork: false,
    networkAllowed: () async => true,
  );
  final player = PlayerController(lib, downloads: dm);
  await tester.pumpWidget(
    MultiProvider(
      providers: testProviders(lib, player: player, downloads: dm),
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  return Rig(lib, dm, player, dir);
}

/// Downloads start inside the test's fake-time zone, so they only advance when the test pumps.
/// Alternate real waiting (file IO) with pumping until nothing is running.
Future<void> downloadAndWait(WidgetTester tester, Rig rig) async {
  for (var i = 0; i < 300 && rig.dm.busy; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  group('desktop', () {
    testWidgets(
      'the settings gear is gone but Settings is still one click away',
      (tester) async {
        await pump(tester, const DesktopShell());
        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(find.byTooltip('Settings'), findsNothing);
        await tester.tap(find.text('Settings and Sync'));
        await tester.pump();
        expect(find.text('Appearance'), findsWidgets);
      },
    );

    testWidgets(
      'sidebar shows counts, and Up Next shows episodes and total playtime',
      (tester) async {
        final rig = await pump(tester, const DesktopShell());
        final sidebar = find.byType(ListView).first;
        Finder count(String n) =>
            find.descendant(of: sidebar, matching: find.text(n));
        expect(count('1'), findsWidgets); // 1 podcast, 1 unplayed episode
        expect(count('2'), findsOneWidget); // 2 in Up Next
        await tester.tap(find.text('Up Next').first);
        await tester.pumpAndSettle();
        // Ep Two is 20 min and Ep One 10 min.
        expect(
          find.textContaining('2 episodes  ·  30 m total'),
          findsOneWidget,
        ); // header
        expect(
          find.textContaining('2 episodes, 30 m total'),
          findsOneWidget,
        ); // status bar
        rig.lib.removeFromQueue(one);
        await tester.pump();
        expect(
          find.textContaining('1 episodes  ·  20 m total'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'download from the menu, see it in the table, in Downloads, and delete it',
      (tester) async {
        final rig = await pump(tester, const DesktopShell());
        await tester.tap(find.text('Ep Two'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Download'));
        await tester.pump();
        await downloadAndWait(tester, rig);
        expect(rig.dm.isDownloaded(two), isTrue);
        expect(find.byIcon(Icons.offline_pin), findsOneWidget);

        // The sidebar counts it and the Downloads screen lists it with its size.
        await tester.tap(find.text('Downloads').first);
        await tester.pumpAndSettle();
        expect(find.text('Ep Two'), findsOneWidget);
        expect(find.textContaining('4.9 KB'), findsWidgets);
        expect(find.textContaining('1 downloaded'), findsWidgets);

        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        expect(rig.dm.isDownloaded(two), isFalse);
        expect(find.textContaining('Nothing downloaded yet'), findsOneWidget);
        await tester.pump(
          const Duration(milliseconds: 600),
        ); // let the index save timer finish
      },
    );

    testWidgets(
      'the cloud icon downloads, and "Downloaded" filters the Episodes list',
      (tester) async {
        final rig = await pump(tester, const DesktopShell());
        expect(find.textContaining('Downloaded (0)'), findsOneWidget);
        await tester.tap(find.byTooltip('Download').first);
        await tester.pump();
        await downloadAndWait(tester, rig);
        expect(find.textContaining('Downloaded (1)'), findsOneWidget);

        await tester.tap(find.textContaining('Downloaded (1)'));
        await tester.pump();
        expect(find.text('Ep Two'), findsOneWidget);
        expect(find.text('Ep One'), findsNothing);

        await tester.tap(find.textContaining('Favorites (0)'));
        await tester.pump();
        expect(find.textContaining('No favorites episodes'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 600));
      },
    );

    testWidgets('a podcast can override auto-download and auto-delete', (
      tester,
    ) async {
      final rig = await pump(tester, const DesktopShell());
      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(GridView),
          matching: find.text('My Tech'),
        ),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Info'));
      await tester.pumpAndSettle();
      expect(find.text('Download new episodes'), findsOneWidget);
      expect(find.text('Delete after playing'), findsOneWidget);
      // The fixture podcast had AntennaPod's per-feed auto-download switched off: imported as "Never".
      expect(
        rig.lib.podcasts['http://a.test/feed.xml']!.extra['autoDownloadNew'],
        2,
      );
      expect(find.text('Never'), findsOneWidget);

      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        rig.lib.podcasts['http://a.test/feed.xml']!.extra['autoDownloadNew'],
        1,
      );
    });

    testWidgets('Statistics shows listening time', (tester) async {
      final rig = await pump(tester, const DesktopShell());
      rig.lib.setProgress(two, 5 * 60000, 20 * 60000);
      await tester.tap(find.text('Statistics').first);
      await tester.pumpAndSettle();
      expect(find.text('listened'), findsOneWidget);
      expect(find.text('By podcast'), findsOneWidget);
      expect(find.textContaining('listened · 1 of 2 played'), findsOneWidget);
    });

    testWidgets('sleep timer from the toolbar and the Controls menu', (
      tester,
    ) async {
      final rig = await pump(tester, const DesktopShell());
      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();
      expect(rig.player.sleepRemaining, const Duration(minutes: 30));
      expect(find.byIcon(Icons.bedtime), findsOneWidget);
      expect(find.text('30:00'), findsOneWidget);

      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sleep Timer ('));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End of Episode'));
      await tester.pumpAndSettle();
      expect(rig.player.sleepAtEpisodeEnd, isTrue);
      expect(rig.player.sleepRemaining, isNull);
      rig.player.cancelSleepTimer();
      await tester.pump();
    });

    testWidgets('Downloads settings group is there with its controls', (
      tester,
    ) async {
      final rig = await pump(tester, const Scaffold(body: SettingsPane()));
      await tester.tap(find.text('Downloads'));
      await tester.pump();
      for (final t in [
        'Download Up Next automatically',
        'Download new episodes',
        'Delete after playing',
        'Wi-Fi only',
        'Keep favorites',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Download Up Next automatically'));
      await tester.pump();
      expect(rig.lib.settings.autoDownloadQueue, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('phone', () {
    testWidgets('More has Downloads and Statistics; the bar counts Up Next', (
      tester,
    ) async {
      await pump(
        tester,
        const MobileShell(),
        size: const Size(1080, 2200),
        ratio: 3,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('2'),
        ),
        findsOneWidget,
      ); // Up Next count
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Statistics'), findsOneWidget);
      await tester.tap(find.text('Statistics'));
      await tester.pumpAndSettle();
      expect(find.text('listened'), findsOneWidget);
    });

    testWidgets(
      'e-ink: downloads and statistics are paged and reachable from the More tab',
      (tester) async {
        final rig = await pump(
          tester,
          const MobileShell(),
          size: const Size(1080, 1440),
          ratio: 3,
          eink: true,
        );
        rig.dm.download(rig.lib.episodes[two]!);
        await downloadAndWait(tester, rig);

        await tester.tap(find.byTooltip('More sections'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Downloads').last);
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsNothing);
        expect(find.text('Ep Two'), findsOneWidget);

        await tester.tap(find.byTooltip('More sections'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Statistics').last);
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsNothing);
        expect(find.text('Listened'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 600));
      },
    );

    testWidgets('episode menu can download, and the player has a sleep timer', (
      tester,
    ) async {
      final rig = await pump(
        tester,
        const MobileShell(),
        size: const Size(1080, 2200),
        ratio: 3,
      );
      await tester.longPress(find.text('Ep Two'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump(); // not pumpAndSettle: the progress ring animates while it downloads
      await downloadAndWait(tester, rig);
      expect(rig.dm.isDownloaded(two), isTrue);
      expect(find.byIcon(Icons.offline_pin), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('player screen offers the sleep timer', (tester) async {
      final rig = await pump(
        tester,
        const PlayerScreen(),
        size: const Size(1080, 2200),
        ratio: 3,
      );
      rig.player.current = rig.lib.episodes[two];
      await tester.pumpWidget(
        MultiProvider(
          providers: testProviders(
            rig.lib,
            player: rig.player,
            downloads: rig.dm,
          ),
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Sleep timer'), findsOneWidget);
    });
  });
}
