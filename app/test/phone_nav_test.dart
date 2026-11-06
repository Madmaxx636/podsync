import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/ui/common.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:podsync/ui/paged.dart';
import 'package:podsync/ui/selection.dart';

import 'phone_features_test.dart' show pump, one, two;

void main() {
  tearDown(EpisodeSelection.instance.clear);

  testWidgets('tabs can leave the bar and then live in the menu', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell());
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Episodes'),
      ),
      findsOneWidget,
    );
    lib.setSetting('navTabs', 'queue,podcasts,add');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Episodes'),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    await tester.tap(find.text('Episodes'));
    await tester.pumpAndSettle();
    expect(find.text('Episodes'), findsWidgets); // now the screen title
  });

  testWidgets('the tab bar can sit at the top', (tester) async {
    final (lib, _) = await pump(tester, const MobileShell());
    final bottomY = tester.getTopLeft(find.byType(NavigationBar)).dy;
    lib.setSetting('navPosition', 'top');
    await tester.pump();
    final topY = tester.getTopLeft(find.byType(NavigationBar)).dy;
    expect(topY, lessThan(bottomY));
    expect(topY, lessThan(300));
  });

  testWidgets(
    'long-press lists the actions; Select several starts a selection',
    (tester) async {
      final (lib, _) = await pump(tester, const MobileShell());
      await tester.longPress(find.text('Ep Two'));
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Copy episode link'), findsOneWidget);
      await tester.tap(find.text('Select several'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Tapping another episode adds it; the bar acts on both.
      await tester.tap(find.text('Ep One'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(SelectionBar),
          matching: find.text('Played'),
        ),
      );
      await tester.pumpAndSettle();
      expect(lib.progressOf(one).played, isTrue);
      expect(lib.progressOf(two).played, isTrue);
      expect(find.textContaining(' selected'), findsNothing);
    },
  );

  testWidgets('the player bar follows its size and button settings', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell(), playing: true);
    expect(find.byTooltip('Back ${lib.skipBackSec}s'), findsOneWidget);
    final medium = tester.getSize(find.byType(MiniPlayer)).height;
    lib.setSetting('playerBarSize', 'huge');
    await tester.pump();
    expect(tester.getSize(find.byType(MiniPlayer)).height, greaterThan(medium));
    lib.setSetting('playerBarButtons', 'play');
    await tester.pump();
    expect(find.byTooltip('Back ${lib.skipBackSec}s'), findsNothing);
    expect(find.byTooltip('Play'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three dots sit in line with the tab bar, top or bottom', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell());
    double barY() => tester.getCenter(find.byType(NavigationBar)).dy;
    double dotsY() => tester.getCenter(find.byTooltip('Menu')).dy;
    expect((dotsY() - barY()).abs(), lessThan(8)); // bottom
    lib.setSetting('navPosition', 'top');
    await tester.pump();
    expect((dotsY() - barY()).abs(), lessThan(8)); // top
    expect(barY(), lessThan(300));
  });

  testWidgets(
    'long-pressing the tab bar opens the tab editor; dragging reorders',
    (tester) async {
      final (lib, _) = await pump(tester, const MobileShell());
      await tester.longPress(find.byType(NavigationBar));
      await tester.pumpAndSettle();
      expect(find.text('Tabs'), findsOneWidget);
      // Drag Add podcast (last) above Queue (first).
      final handle = find.text('Add podcast');
      await tester.drag(handle, const Offset(0, -400), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final tabs = lib.settings.navTabs;
      expect(tabs.toSet(), {'queue', 'episodes', 'podcasts', 'add'});
    },
  );

  testWidgets('player buttons can be made larger', (tester) async {
    final (lib, _) = await pump(tester, const MobileShell(), playing: true);
    final before = tester
        .getSize(find.byTooltip('Back ${lib.skipBackSec}s'))
        .width;
    lib.setSetting('playerBarButtonPct', 200);
    await tester.pump();
    final after = tester
        .getSize(find.byTooltip('Back ${lib.skipBackSec}s'))
        .width;
    expect(after, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Podcasts can be a grid or a list, with a chosen grid size', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Podcasts'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    final three = tester.getSize(find.byType(Art).first).width;
    await tester.tap(find.byTooltip('Grid size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 per row'));
    await tester.pumpAndSettle();
    expect(lib.settings.gridColumns, 5);
    expect(tester.getSize(find.byType(Art).first).width, lessThan(three));

    await tester.tap(find.byTooltip('Show as a list'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(lib.settings.podcastsViewFor(false), 'list');
    expect(find.byTooltip('Grid size'), findsNothing);
  });

  testWidgets('on e-ink the grid is paged and names each podcast', (
    tester,
  ) async {
    final (lib, _) = await pump(tester, const MobileShell(), eink: true);
    lib.setSetting('podcastsView', 'grid');
    await tester.tap(find.text('Podcasts'));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(PagedGrid<Podcast>), findsOneWidget);
    expect(find.textContaining('/ 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
