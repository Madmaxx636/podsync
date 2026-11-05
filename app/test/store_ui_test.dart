import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/directory.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:podsync/ui/settings.dart';
import 'package:podsync/ui/store_view.dart';
import 'package:provider/provider.dart';

import 'directory_test.dart' show FakeStore;
import 'downloads_ui_test.dart' as dl;
import 'fixtures.dart';

const feedXml =
    '<rss version="2.0"><channel><title>Name 3</title><item><title>Pilot</title><guid>p1</guid><enclosure url="http://a/1.mp3"/></item></channel></rss>';

class StoreRig {
  StoreRig(this.lib, this.store, this.fake);
  final Library lib;
  final StoreController store;
  final FakeStore fake;
}

Future<StoreRig> pumpStore(
  WidgetTester tester,
  Widget home, {
  bool eink = false,
  Size size = const Size(1300, 900),
  double ratio = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final fake = FakeStore();
  // Feed addresses answer with a small feed; everything else is the store.
  final storeClient = fake.client();
  final lib = Library(
    client: MockClient(
      (r) async => r.url.host == 'feeds.test'
          ? http.Response(feedXml, 200)
          : http.Response('', 404),
    ),
  )..einkMode = eink;
  final store = StoreController(StoreDirectory(client: storeClient), lib);
  final player = PlayerController(lib);
  await tester.pumpWidget(
    MultiProvider(
      providers: testProviders(lib, player: player, store: store),
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  return StoreRig(lib, store, fake);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('desktop store', () {
    testWidgets('opens on the charts: covers, then a ranked list', (
      tester,
    ) async {
      await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      expect(find.text('Podcasts'), findsWidgets);
      expect(find.text('Top Podcasts'), findsOneWidget);
      expect(find.text('Top Charts'), findsOneWidget);
      expect(find.text('All Categories'), findsOneWidget);
      expect(
        find.text('Name 3'),
        findsNWidgets(2),
      ); // once as a cover, once in the chart
      expect(find.text('Name 1'), findsNWidgets(2));
      expect(find.text('Name 2'), findsNothing); // had no feed address
      expect(find.text('1'), findsWidgets); // rank numbers
      expect(find.text('Subscribe'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Subscribe pill subscribes and turns into Subscribed', (
      tester,
    ) async {
      final rig = await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      await tester.tap(find.text('Subscribe').first);
      await settle(tester);
      expect(rig.lib.isSubscribed('https://feeds.test/3.xml'), isTrue);
      expect(find.text('Subscribed'), findsWidgets);
      expect(rig.lib.episodesOf('https://feeds.test/3.xml'), hasLength(1));
    });

    testWidgets('searching shows results, and clearing returns to the charts', (
      tester,
    ) async {
      final rig = await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'history');
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // typing pauses, then it searches
      await settle(tester);
      expect(
        rig.fake.urls.any(
          (u) => u.path == '/search' && u.queryParameters['term'] == 'history',
        ),
        isTrue,
      );
      expect(find.text('Results for “history”'), findsOneWidget);
      expect(find.text('Hit'), findsOneWidget);
      expect(find.text('Top Charts'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await settle(tester);
      expect(find.text('Top Charts'), findsOneWidget);
    });

    testWidgets('a category changes the chart and the title', (tester) async {
      final rig = await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      await tester.tap(find.text('All Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comedy'));
      await settle(tester);
      expect(rig.fake.urls.any((u) => u.path.contains('genre=1303')), isTrue);
      expect(find.text('Top Comedy'), findsOneWidget);
      expect(find.text('Comedy'), findsWidgets);
    });

    testWidgets('pasting a feed address subscribes straight away', (
      tester,
    ) async {
      final rig = await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'https://feeds.test/99.xml',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(rig.lib.isSubscribed('https://feeds.test/99.xml'), isTrue);
    });

    testWidgets('an unreachable store says so and Try Again recovers', (
      tester,
    ) async {
      final rig = await pumpStore(tester, const DesktopShell());
      rig.fake.status = 503;
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      expect(find.text('The store could not be reached'), findsOneWidget);
      expect(find.textContaining('503'), findsOneWidget);
      rig.fake.status = 200;
      await tester.tap(find.text('Try Again'));
      await settle(tester);
      expect(find.text('Top Charts'), findsOneWidget);
    });

    testWidgets(
      'clicking a cover opens its podcast page at once, and the page survives going back',
      (tester) async {
        final rig = await pumpStore(tester, const DesktopShell());
        await tester.tap(find.text('Find Podcasts'));
        await settle(tester);
        await tester.tap(find.text('Name 3').first);
        await settle(tester);
        expect(
          find.text('Subscribe'),
          findsWidgets,
        ); // the page's own Subscribe button
        expect(
          find.text('Pilot'),
          findsOneWidget,
        ); // the episode list loaded in the background
        expect(rig.lib.isSubscribed('https://feeds.test/3.xml'), isFalse);

        await tester.tap(find.byTooltip('Go back'));
        await settle(tester);
        expect(
          find.text('Top Charts'),
          findsOneWidget,
        ); // same page as before, not a blank one
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets('right-click on a cover gives the podcast menu', (
      tester,
    ) async {
      await pumpStore(tester, const DesktopShell());
      await tester.tap(find.text('Find Podcasts'));
      await settle(tester);
      await tester.tap(find.text('Name 3').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Go to Podcast'), findsOneWidget);
      expect(find.text('Copy Feed URL'), findsOneWidget);
      expect(find.text('Subscribe'), findsWidgets);
    });

    testWidgets(
      'the store country setting changes which charts are asked for',
      (tester) async {
        final rig = await pumpStore(tester, const DesktopShell());
        rig.lib.setSetting('storeCountry', 'gb');
        await tester.tap(find.text('Find Podcasts'));
        await settle(tester);
        expect(
          rig.fake.urls.any((u) => u.path.startsWith('/gb/rss/toppodcasts')),
          isTrue,
        );
      },
    );
  });

  group('phone store', () {
    const size = Size(1080, 2200);

    testWidgets('Add podcast shows the charts with ranks and subscribe pills', (
      tester,
    ) async {
      final rig = await pumpStore(
        tester,
        const Scaffold(body: AddPodcastView()),
        size: size,
        ratio: 3,
      );
      await settle(tester);
      expect(find.text('Top podcasts'), findsOneWidget);
      expect(find.text('Name 3'), findsOneWidget);
      expect(find.text('Name 1'), findsOneWidget);
      await tester.tap(find.text('Subscribe').first);
      await settle(tester);
      expect(rig.lib.isSubscribed('https://feeds.test/3.xml'), isTrue);
    });

    testWidgets('search and the category picker work on the phone', (
      tester,
    ) async {
      final rig = await pumpStore(
        tester,
        const Scaffold(body: AddPodcastView()),
        size: size,
        ratio: 3,
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'news');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Results for “news”'), findsOneWidget);
      expect(find.text('Hit'), findsOneWidget);

      await tester.tap(find.text('All Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await settle(tester);
      expect(
        rig.fake.urls.any(
          (u) => u.path == '/search' && u.queryParameters['genreId'] == '1487',
        ),
        isTrue,
      );
    });

    testWidgets('e-ink: the chart is paged, never scrolled', (tester) async {
      await pumpStore(
        tester,
        const MobileShell(),
        eink: true,
        size: const Size(1080, 1440),
        ratio: 3,
      );
      await tester.tap(find.text('Add'));
      await settle(tester);
      // The search field scrolls its own text sideways; no list may scroll up and down.
      expect(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
        findsNothing,
      );
      expect(find.text('Name 3'), findsOneWidget);
      expect(find.textContaining('1 / '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('downloads dropdown', () {
    testWidgets(
      'empty state, then running, failed and finished downloads with their buttons',
      (tester) async {
        final rig = await dl.pump(tester, const DesktopShell());
        expect(find.byTooltip('Downloads'), findsOneWidget);
        await tester.tap(find.byTooltip('Downloads'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Nothing downloading'), findsOneWidget);
        await tester.tapAt(const Offset(5, 500)); // click outside to close
        await tester.pumpAndSettle();

        rig.dm.download(rig.lib.episodes[dl.two]!);
        await dl.downloadAndWait(tester, rig);
        await tester.tap(find.byTooltip('Downloads'));
        await tester.pumpAndSettle();
        // Only what is in flight is listed; a finished download is not.
        expect(find.text('RECENTLY DOWNLOADED'), findsNothing);
        expect(find.byTooltip('Delete download'), findsNothing);
        expect(find.textContaining('Nothing downloading'), findsOneWidget);
        expect(rig.dm.isDownloaded(dl.two), isTrue);
        await tester.pump(const Duration(milliseconds: 600));
      },
    );

    testWidgets('failed downloads show why and can be retried or dismissed', (
      tester,
    ) async {
      final rig = await dl.pump(tester, const DesktopShell());
      final dir = Directory.systemTemp.createTempSync('podsync_dd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final failing = DownloadManager(
        rig.lib,
        client: MockClient.streaming(
          (r, b) async => http.StreamedResponse(Stream.value([]), 500),
        ),
        directory: Directory('${dir.path}/f'),
        indexFile: File('${dir.path}/i.json'),
        watchNetwork: false,
        networkAllowed: () async => true,
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: testProviders(rig.lib, downloads: failing),
          child: const MaterialApp(home: DesktopShell()),
        ),
      );
      await tester.pump();
      failing.download(rig.lib.episodes[dl.two]!);
      for (var i = 0; i < 100 && failing.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump();
      expect(find.text('!'), findsOneWidget); // the badge flags the failure

      await tester.tap(find.byTooltip('Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(failing.failedIds, isEmpty);
      failing.dispose();
    });

    testWidgets(
      'Show All opens the Downloads screen; the button can be hidden',
      (tester) async {
        final rig = await dl.pump(tester, const DesktopShell());
        await tester.tap(find.byTooltip('Downloads'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show All'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Nothing downloaded yet'), findsOneWidget);

        rig.lib.setSetting('uiDownloadsButton', false);
        await tester.pump();
        expect(find.byTooltip('Downloads'), findsNothing);
      },
    );
  });

  testWidgets('the Settings page offers the store country', (tester) async {
    final rig = await pumpStore(
      tester,
      const Scaffold(body: SettingsPane(initial: 'Library and feeds')),
      size: const Size(1300, 2600),
    );
    expect(find.text('Podcast store country'), findsOneWidget);
    rig.lib.setSetting('storeCountry', 'de');
    await tester.pump();
    expect(find.text('de'), findsOneWidget);
  });
}
