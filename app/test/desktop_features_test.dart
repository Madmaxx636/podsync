import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/desktop_table.dart';
import 'package:podsync/ui/desktop_toolbar.dart';
import 'package:podsync/ui/mini_player.dart';
import 'package:podsync/ui/zoom.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

const one = 'http://a.test/feed.xml|guid-1',
    two = 'http://a.test/feed.xml|guid-2';

Future<(Library, PlayerController)> pump(
  WidgetTester tester, {
  bool playing = false,
}) async {
  tester.view.physicalSize = const Size(1300, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final path = makeAntennaPodBackup();
  final lib = Library();
  importAntennaPodBackup(lib, path);
  File(path).parent.deleteSync(recursive: true);
  final player = PlayerController(lib);
  if (playing) player.current = lib.episodes[two];
  await tester.pumpWidget(
    MultiProvider(
      providers: testProviders(lib, player: player),
      child: const MaterialApp(home: DesktopShell()),
    ),
  );
  await tester.pump();
  return (lib, player);
}

Future<void> openMenu(WidgetTester tester, String menu, String item) async {
  await tester.tap(find.text(menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('volume', () {
    testWidgets('slider, speaker button and mouse wheel change the volume', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      final slider = find.descendant(
        of: find.byType(VolumeControl),
        matching: find.byType(Slider),
      );
      expect(lib.settings.volume, 1.0);

      // A drag starts where you press (the middle, 50%) and moves from there.
      await tester.drag(slider, const Offset(-20, 0));
      await tester.pump();
      expect(lib.settings.volume, lessThan(0.5));
      expect(lib.settings.volume, greaterThan(0.0));

      // Clicking the speaker mutes; the slider drops to zero but the level is remembered.
      final level = lib.settings.volume;
      await tester.tap(
        find.descendant(
          of: find.byType(VolumeControl),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      expect(lib.settings.muted, isTrue);
      expect(lib.settings.volume, level);
      expect(tester.widget<Slider>(slider).value, 0.0);

      // Dragging while muted unmutes.
      await tester.drag(slider, const Offset(20, 0));
      await tester.pump();
      expect(lib.settings.muted, isFalse);

      // Mouse wheel over the control nudges it up.
      final before = lib.settings.volume;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(slider)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
      await tester.pump();
      expect(lib.settings.volume, greaterThan(before));
      await tester.pumpAndSettle(
        const Duration(seconds: 2),
      ); // let the hover tooltip's timer finish
    });

    testWidgets('volume stays between 0 and 1 and is a device setting', (
      tester,
    ) async {
      final (lib, player) = await pump(tester);
      player.setVolume(5);
      expect(lib.settings.volume, 1.0);
      player.changeVolume(-3);
      expect(lib.settings.volume, 0.0);
      player.changeVolume(0.25);
      expect(lib.settings.volume, 0.25);
      expect(player.effectiveVolume, 0.25);
      player.toggleMute();
      expect(player.effectiveVolume, 0.0);
    });
  });

  group('menu bar', () {
    testWidgets('has the iTunes menus and the View menu toggles panes', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      for (final m in ['File', 'Edit', 'View', 'Controls', 'Account', 'Help']) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      expect(
        find.text('Library'),
        findsNWidgets(2),
      ); // the sidebar heading and the tab
      await openMenu(tester, 'View', 'Show Sidebar');
      expect(lib.settings.showSidebar, isFalse);
      expect(find.text('Library'), findsOneWidget); // only the tab is left

      await openMenu(tester, 'View', 'Show Details Pane');
      expect(lib.settings.showDetails, isTrue);
      expect(find.text('Select an episode to see its details'), findsOneWidget);
    });

    testWidgets('Controls menu changes volume and sorts Up Next', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      lib.setSetting('volume', 0.5);
      await openMenu(tester, 'Controls', 'Increase Volume');
      expect(lib.settings.volume, closeTo(0.6, 0.001));

      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Up Next').first,
      ); // the menu entry is built before the sidebar's
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort By'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release Date, Oldest First'));
      await tester.pumpAndSettle();
      expect(lib.queue, [one, two]);
      expect(lib.canUndoQueue, isTrue);

      await openMenu(tester, 'Edit', 'Undo Sort Up Next');
      expect(lib.queue, [two, one]);
    });
  });

  group('Up Next', () {
    testWidgets(
      'header shows totals; sort, shuffle, remove played and undo work',
      (tester) async {
        final (lib, _) = await pump(tester);
        await tester.tap(find.text('Up Next').first); // sidebar
        await tester.pumpAndSettle();
        expect(find.textContaining('2 episodes'), findsWidgets);
        expect(find.textContaining('ends about'), findsOneWidget);

        await tester.tap(find.byTooltip('Sort Up Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Release date, oldest first'));
        await tester.pumpAndSettle();
        expect(lib.queue, [one, two]);
        expect(find.text('Up Next sorted'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(lib.queue, [two, one]);

        // Ep One is played in the fixture, so "Remove Played" takes just that one out.
        await tester.tap(find.text('Remove Played'));
        await tester.pumpAndSettle();
        expect(lib.queue, [two]);
        await tester.tap(find.textContaining('Undo Remove Played'));
        await tester.pumpAndSettle();
        expect(lib.queue, [two, one]);

        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(lib.queue, isEmpty);
        expect(find.text('Nothing queued'), findsOneWidget);
      },
    );

    testWidgets(
      'column headings do not sort Up Next, and it has Starts at and Ends at',
      (tester) async {
        final (lib, _) = await pump(tester);
        await tester.tap(find.text('Up Next').first);
        await tester.pumpAndSettle();
        final before = [...lib.queue];
        await tester.tap(find.text('Release Date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Name'));
        await tester.pumpAndSettle();
        expect(lib.queue, before);
        expect(find.text('Starts at'), findsOneWidget);
        expect(find.text('Ends at'), findsOneWidget);
      },
    );

    testWidgets('dragging a row\'s handle reorders the queue', (tester) async {
      final (lib, _) = await pump(tester);
      await tester.tap(find.text('Up Next').first);
      await tester.pumpAndSettle();
      expect(lib.queue, [two, one]);
      final handle = find.byIcon(Icons.drag_indicator).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(lib.queue, [one, two]);
    });

    testWidgets('Alt+Down moves the selected episode down', (tester) async {
      final (lib, _) = await pump(tester);
      await tester.tap(find.text('Up Next').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ep Two'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(lib.queue, [one, two]);
      await tester.pump(
        const Duration(milliseconds: 400),
      ); // let the row's double-click timer expire
    });

    testWidgets('the Up Next popover lists the queue and clears it', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      await tester.tap(find.byTooltip('Up Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 episodes ·'), findsOneWidget);
      expect(find.text('Ep Two'), findsWidgets);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(lib.queue, isEmpty);
      expect(find.text('Nothing queued'), findsOneWidget);
      expect(find.textContaining('Undo Clear Up Next'), findsOneWidget);
    });

    testWidgets('"Starts in" counts down through the queue', (tester) async {
      final (lib, _) = await pump(tester);
      lib.setProgress(two, 300000, 1200000); // 15 min left of Ep Two
      await tester.tap(find.text('Up Next').first);
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);
      // 15 min left of Ep Two, but this podcast plays at 1.5x, so Ep One starts 10 minutes from now.
      expect(find.text('10 m'), findsWidgets);
      expect(lib.queueStartOffsets[1], const Duration(minutes: 10));
    });
  });

  group('table features', () {
    testWidgets(
      'click a star to rate; right-click headings to choose columns',
      (tester) async {
        final (lib, _) = await pump(tester);
        expect(find.text('Rating'), findsOneWidget);
        Finder inTable(IconData icon) => find.descendant(
          of: find.byType(EpisodeTable),
          matching: find.byIcon(icon),
        );
        await tester.tap(
          inTable(Icons.star_border).at(2),
        ); // third star of the first row (Ep Two)
        await tester.pump();
        expect(lib.ratingOf(two), 3);
        await tester.tap(
          inTable(Icons.star).at(2),
        ); // clicking the same star clears it
        await tester.pump();
        expect(lib.ratingOf(two), 0);

        await tester.tap(find.text('Rating'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Release Date').last);
        await tester.pumpAndSettle();
        expect(lib.settings.colDate, isFalse);
        expect(find.text('Release Date'), findsNothing);
      },
    );

    testWidgets('rating from the context menu applies to the whole selection', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      await tester.tap(find.text('Ep Two'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Ep One'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tap(find.text('Ep One'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Rating'), findsWidgets);
      final menuStars = find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.byIcon(Icons.star_border),
      );
      await tester.tap(menuStars.at(3)); // four stars
      await tester.pumpAndSettle();
      expect(lib.ratingOf(one), 4);
      expect(lib.ratingOf(two), 4);
    });

    testWidgets('details pane follows the selection and acts on it', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      lib.setSetting('showDetails', true);
      await tester.pump();
      expect(find.text('Select an episode to see its details'), findsOneWidget);
      await tester.tap(find.text('Ep Two'));
      await tester.pump();
      expect(
        find.text('NOTES'),
        findsNothing,
      ); // fixture has no notes for this one
      expect(find.text('CHAPTERS'), findsOneWidget);
      expect(find.text('Intro'), findsOneWidget);
      expect(
        find.text('Remove from Up Next'),
        findsOneWidget,
      ); // it is queued in the fixture
      await tester.tap(find.text('Remove from Up Next'));
      await tester.pump();
      expect(lib.queue, [one]);
      expect(find.text('Add to Up Next'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('window, zoom and columns', () {
    testWidgets('the cover in the top bar opens the mini player, and back', (
      tester,
    ) async {
      await pump(tester, playing: true);
      expect(find.byType(MiniPlayerView), findsNothing);
      await tester.tap(find.byTooltip('Open the mini player'));
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayerView), findsOneWidget);
      expect(find.byType(EpisodeTable), findsNothing);
      await tester.tap(find.byTooltip('Back to the full window').last);
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayerView), findsNothing);
      expect(find.byType(EpisodeTable), findsOneWidget);
    });

    testWidgets('the artwork pane can be hidden from its corner button', (
      tester,
    ) async {
      final (lib, _) = await pump(tester, playing: true);
      await tester.tap(
        find.byTooltip('Hide the artwork (View menu brings it back)'),
      );
      await tester.pump();
      expect(lib.settings.showArtworkPane, isFalse);
    });

    testWidgets('dragging a column edge resizes it and the width is kept', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      final before = tester.getSize(find.text('Release Date')).width;
      // The Release Date column's left edge is the last resize handle in the heading row.
      final handles = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      final date = handles.last;
      await tester.drag(date, const Offset(-60, 0));
      await tester.pump();
      expect(lib.settings.colWidthMap['date'], greaterThan(128 + 30));
      expect(before, greaterThan(0));
      // Double-click the edge to put it back.
      await tester.tap(handles.last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handles.last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(lib.settings.colWidthMap.containsKey('date'), isFalse);
    });

    testWidgets('Ctrl and the plus, minus and 0 keys zoom the window', (
      tester,
    ) async {
      final (lib, _) = await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      expect(lib.settings.zoom, closeTo(1.2, 0.001));
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      expect(lib.settings.zoom, closeTo(1.1, 0.001));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      expect(lib.settings.zoom, 1.0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(Zoom.min, lessThan(1));
    });
  });

  group('window chrome', () {
    testWidgets(
      'dragging the sidebar edge resizes it and the width is remembered',
      (tester) async {
        final (lib, _) = await pump(tester);
        // The sidebar's edge is the first resize handle on screen (the table's column edges follow).
        final edge = find
            .byWidgetPredicate(
              (w) =>
                  w is MouseRegion &&
                  w.cursor == SystemMouseCursors.resizeColumn,
            )
            .first;
        expect(lib.settings.sidebarWidth, 200.0);
        await tester.drag(edge, const Offset(60, 0));
        await tester.pump();
        expect(lib.settings.sidebarWidth, closeTo(260, 1));
        await tester.drag(edge, const Offset(-400, 0));
        await tester.pump();
        expect(lib.settings.sidebarWidth, 140.0); // never narrower than usable
      },
    );

    testWidgets(
      'artwork pane shows what is playing, and the LCD time flips between left and total',
      (tester) async {
        final (lib, _) = await pump(tester, playing: true);
        expect(find.text('Nothing playing'), findsNothing);
        expect(lib.settings.lcdRemaining, isTrue);
        expect(
          find.text('20:00'),
          findsNothing,
        ); // the total length is not shown while counting down
        await tester.tap(find.text('Ep Two').first);
        await tester.pump();
        // Flip the right-hand time with a click.
        final lcdTime = find
            .descendant(of: find.byType(Lcd), matching: find.byType(InkWell))
            .last;
        await tester.tap(lcdTime);
        await tester.pump();
        expect(lib.settings.lcdRemaining, isFalse);
      },
    );

    testWidgets(
      'with nothing playing the artwork pane says so; it can be hidden',
      (tester) async {
        final (lib, _) = await pump(tester);
        expect(find.text('Nothing playing'), findsOneWidget);
        await openMenu(tester, 'View', 'Show Artwork Pane');
        expect(lib.settings.showArtworkPane, isFalse);
        expect(find.text('Nothing playing'), findsNothing);
        await openMenu(tester, 'View', 'Show Status Bar');
        expect(find.textContaining('hours'), findsNothing);
      },
    );
  });
}
