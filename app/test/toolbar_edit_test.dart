import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/settings.dart';
import 'package:podsync/ui/desktop_toolbar.dart';

import 'desktop_features_test.dart' show pump, openMenu;

void main() {
  test(
    'the saved order is cleaned up: unknown names dropped, missing ones last',
    () {
      final s = AppSettings()
        ..set('toolbarOrder', 'search,bogus,display,search,volume');
      expect(s.toolbarItems, [
        'search',
        'display',
        'volume',
        'transport',
        'upnext',
        'downloads',
        'sleep',
        'speed',
      ]);
    },
  );

  testWidgets(
    'Customize Toolbar shows the editor; sliders and ticks change the bar',
    (tester) async {
      final (lib, _) = await pump(tester);
      expect(find.text('Customize Toolbar'), findsNothing);
      await openMenu(tester, 'View', 'Customize Toolbar…');
      expect(find.text('Customize Toolbar'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DesktopToolbar)).height,
        greaterThan(58),
      );

      // Tick Speed off in the editor: the speed button leaves the bar.
      expect(find.text('1.0×'), findsOneWidget);
      lib.setSetting('uiSpeed', false);
      await tester.pump();
      expect(find.text('1.0×'), findsNothing);

      // Taller bar
      lib.setSetting('toolbarHeight', 80);
      await tester.pump();
      expect(tester.getSize(find.byType(Lcd)).height, 72);

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(lib.settings.toolbarHeight, 58);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.text('Customize Toolbar'), findsNothing);
    },
  );
}
