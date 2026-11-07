import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podsync/ui/resize.dart';

import 'desktop_features_test.dart' show pump;

void main() {
  testWidgets('Ctrl-click selects several episodes and the bar acts on them', (
    tester,
  ) async {
    final (lib, _) = await pump(tester);
    await tester.tap(find.text('Up Next').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(' selected'), findsNothing);
    await tester.tap(find.text('Ep Two'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Ep One'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.textContaining(' selected'), findsNothing);
    await tester.tap(find.text('Ep Two'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Ep One'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.tap(find.text('Remove from Up Next'));
    await tester.pumpAndSettle();
    expect(lib.queue, isEmpty);
    expect(find.textContaining(' selected'), findsNothing); // the rows are gone
  });

  testWidgets('the size slider moves by exactly 1% with its buttons', (
    tester,
  ) async {
    final (lib, _) = await pump(tester);
    await tester.tap(find.text('Settings and Sync'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsWidgets);
    await tester.tap(find.byTooltip('Bigger by 1%').first);
    await tester.pumpAndSettle();
    expect(lib.settings.zoom, closeTo(1.01, 0.0001));
    await tester.tap(find.byTooltip('Smaller by 1%').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Smaller by 1%').first);
    await tester.pumpAndSettle();
    expect(lib.settings.zoom, closeTo(0.99, 0.0001));
  });

  testWidgets('Podcasts has the Unplayed, My Podcasts and List views', (
    tester,
  ) async {
    final (_, _) = await pump(tester);
    await tester.tap(find.text('Podcasts'));
    await tester.pumpAndSettle();
    for (final t in ['Unplayed', 'My Podcasts', 'List']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Unplayed: every unplayed episode, with the unplayed count above.
    expect(find.textContaining(' unplayed'), findsWidgets);

    // My Podcasts: Old Episodes shows the played ones; Add All fills Up Next; Done goes back.
    await tester.tap(find.text('My Podcasts'));
    await tester.pumpAndSettle();
    expect(find.text('Old Episodes'), findsOneWidget);
    expect(find.text('Add All'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    await tester.tap(find.text('Old Episodes'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Old Episodes'), findsOneWidget);

    // List: a podcast row opens to show its episodes.
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.text('Release Date'), findsOneWidget);
    expect(find.text('Ep Two'), findsNothing);
    await tester.tap(
      find.textContaining('My Tech').last,
    ); // the sidebar has one too
    await tester.pumpAndSettle();
    expect(find.text('Ep Two'), findsOneWidget);
    expect(find.text('My Stations'), findsNothing);
  });

  testWidgets(
    'the details pane and the My Podcasts column resize by dragging',
    (tester) async {
      final (lib, _) = await pump(tester);
      lib.setSetting('showDetails', true);
      await tester.pump();
      // Details pane: its splitter is the bar at its left edge.
      expect(lib.settings.detailsWidth, 300.0);
      final splitters = find.byType(VerticalSplitter);
      await tester.drag(splitters.last, const Offset(-80, 0));
      await tester.pump();
      expect(lib.settings.detailsWidth, closeTo(380, 21));
      await tester.drag(splitters.last, const Offset(1000, 0));
      await tester.pump();
      expect(lib.settings.detailsWidth, 200.0); // never narrower than usable

      // My Podcasts column.
      await tester.tap(find.text('Podcasts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Podcasts'));
      await tester.pumpAndSettle();
      expect(lib.settings.podsColumnWidth, 230.0);
      final mine = find.byType(VerticalSplitter).at(1); // after the sidebar's
      await tester.drag(mine, const Offset(70, 0));
      await tester.pump();
      expect(lib.settings.podsColumnWidth, closeTo(300, 21));
      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
