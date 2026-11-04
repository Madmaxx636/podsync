import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

Future<Library> _loadedLibrary() async {
  final path = makeAntennaPodBackup();
  final lib = Library();
  importAntennaPodBackup(lib, path);
  File(path).parent.deleteSync(recursive: true);
  return lib;
}

Widget _app(Library lib, Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider(create: (_) => PlayerController(lib)),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('desktop shell renders the imported library', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = await _loadedLibrary();

    await tester.pumpWidget(_app(lib, const DesktopShell()));
    await tester.pump();

    // Sidebar sources, and the episode table with the imported episodes.
    for (final label in ['Podcasts', 'Episodes', 'Up Next', 'Favorites', 'Recently Played']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Ep Two'), findsOneWidget);
    expect(find.text('My Tech'), findsWidgets); // custom name wins over the feed title

    await tester.tap(find.text('Up Next'));
    await tester.pump();
    expect(find.text('Ep Two'), findsOneWidget);

    await tester.tap(find.text('Favorites'));
    await tester.pump();
    expect(find.text('Fav Ep'), findsOneWidget);

    await tester.tap(find.text('Recently Played'));
    await tester.pump();
    expect(find.text('Ep Two'), findsOneWidget);

    await tester.tap(find.text('Podcasts'));
    await tester.pump();
    expect(find.text('My Tech'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shell: queue, episodes filters, subscriptions', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final lib = await _loadedLibrary();

    await tester.pumpWidget(_app(lib, const MobileShell()));
    await tester.pump();
    expect(find.text('Ep Two'), findsOneWidget); // queue is the home screen
    expect(find.text('Queue'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Episodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Fav Ep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('e-ink mode: lists are paged and nothing scrolls', (tester) async {
    tester.view.physicalSize = const Size(1080, 1440); // a small e-ink phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final lib = await _loadedLibrary()..einkMode = true;
    // Enough episodes to need several pages.
    final feed = lib.subscriptions.first.feedUrl;
    for (var i = 0; i < 30; i++) {
      final e = Episode(feedUrl: feed, guid: 'extra$i', title: 'Extra $i', audioUrl: 'http://a.test/x$i.mp3', published: 1000 + i);
      lib.episodes[e.id] = e;
    }

    await tester.pumpWidget(_app(lib, const MobileShell()));
    await tester.pump();
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(ListView), findsNothing);

    await tester.tap(find.text('Episodes'));
    await tester.pump();
    expect(find.byType(Scrollable), findsNothing);
    expect(find.textContaining(RegExp(r'^1 / \d+$')), findsOneWidget);
    await tester.tap(find.text('Next  ▶'));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^2 / \d+$')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop back and forward walk through places like iTunes', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = await _loadedLibrary();
    await tester.pumpWidget(_app(lib, const DesktopShell()));
    await tester.pump();

    VoidCallback? onPressed(IconData icon) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed;
    expect(onPressed(Icons.arrow_back_ios_new), isNull, reason: 'nothing to go back to yet');
    expect(onPressed(Icons.arrow_forward_ios), isNull);

    await tester.tap(find.text('Podcasts'));
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);

    // Open a podcast from the grid.
    await tester.tap(find.descendant(of: find.byType(GridView), matching: find.text('My Tech')));
    await tester.pump();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Subscribed'), findsOneWidget);

    // Back returns to the podcast grid, then to the episode list.
    await tester.tap(find.byTooltip('Go back'));
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(onPressed(Icons.arrow_forward_ios), isNotNull);

    await tester.tap(find.byTooltip('Go back'));
    await tester.pump();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Ep Two'), findsOneWidget);
    expect(onPressed(Icons.arrow_back_ios_new), isNull);

    // Forward replays the path; going somewhere new drops what was ahead.
    await tester.tap(find.byTooltip('Go forward'));
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.text('Favorites'));
    await tester.pump();
    expect(onPressed(Icons.arrow_forward_ios), isNull);

    // Keyboard: Alt+Left goes back.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone back button returns to the previous section, then leaves', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final lib = await _loadedLibrary();
    await tester.pumpWidget(_app(lib, const MobileShell()));
    await tester.pump();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscriptions'));
    await tester.pumpAndSettle();
    expect(find.text('Subscriptions'), findsOneWidget); // the app bar title

    await tester.binding.handlePopRoute(); // system back
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Subscriptions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('desktop right-click menus', () {
    Future<Library> pumpDesktop(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = await _loadedLibrary();
      await tester.pumpWidget(_app(lib, const DesktopShell()));
      await tester.pump();
      return lib;
    }

    const one = 'http://a.test/feed.xml|guid-1', two = 'http://a.test/feed.xml|guid-2';

    testWidgets('episode menu offers the iTunes actions and applies them', (tester) async {
      final lib = await pumpDesktop(tester);
      await tester.tap(find.text('Ep Two'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      for (final item in ['Play', 'Play Next', 'Remove from Up Next', 'Mark as Played', 'Add to Favorites', 'Get Info', 'Go to Podcast', 'Copy Episode Link']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      await tester.tap(find.text('Add to Favorites'));
      await tester.pumpAndSettle();
      expect(lib.isFavorite(two), isTrue);

      // Get Info opens a details dialog.
      await tester.tap(find.text('Ep Two'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Info'));
      await tester.pumpAndSettle();
      expect(find.text('Released'), findsOneWidget);
      expect(find.text('2 chapters'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ctrl-click selects several episodes and the menu acts on all of them', (tester) async {
      final lib = await pumpDesktop(tester);
      await tester.tap(find.text('Ep Two'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Ep One'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await tester.tap(find.text('Ep One'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Play 2 Episodes'), findsOneWidget);
      expect(find.text('Get Info'), findsNothing); // single-episode actions drop out
      await tester.tap(find.text('Mark as Played')); // Ep One was already played, Ep Two was not
      await tester.pumpAndSettle();
      expect(lib.progressOf(one).played, isTrue);
      expect(lib.progressOf(two).played, isTrue);
    });

    testWidgets('Up Next menu reorders and clears the queue', (tester) async {
      final lib = await pumpDesktop(tester);
      await tester.tap(find.text('Up Next'));
      await tester.pump();
      expect(lib.queue, [two, one]);

      await tester.tap(find.text('Ep One'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Top of Up Next'));
      await tester.pumpAndSettle();
      expect(lib.queue, [one, two]);

      await tester.tap(find.text('Ep One')); // select, then Delete removes it
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(lib.queue, [two]);

      await tester.tap(find.text('Ep Two'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear Up Next'));
      await tester.pumpAndSettle();
      expect(lib.queue, isEmpty);
    });

    testWidgets('podcast menu on the grid and the sidebar', (tester) async {
      final lib = await pumpDesktop(tester);
      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(GridView), matching: find.text('My Tech')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      for (final item in ['Go to Podcast', 'Refresh Podcast', 'Mark All as Played', 'Get Info', 'Copy Feed URL', 'Unsubscribe']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      await tester.tap(find.text('Mark All as Played'));
      await tester.pumpAndSettle();
      expect(lib.progressOf(two).played, isTrue);

      // Same menu from the sidebar; Go to Podcast navigates there.
      await tester.tap(find.descendant(of: find.byType(ListView).first, matching: find.text('My Tech')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to Podcast'));
      await tester.pumpAndSettle();
      expect(find.text('Subscribed'), findsOneWidget);

      // Unsubscribe from the menu.
      await tester.tap(find.descendant(of: find.byType(ListView).first, matching: find.text('My Tech')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unsubscribe'));
      await tester.pumpAndSettle();
      expect(lib.isSubscribed('http://a.test/feed.xml'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
