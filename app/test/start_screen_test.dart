import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

Future<Library> pumpShell(
  WidgetTester tester,
  Widget shell,
  Map<String, Object> settings, {
  Size size = const Size(1080, 2200),
  double ratio = 3,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final lib = Library();
  importAntennaPodBackup(lib, makeAntennaPodBackup());
  settings.forEach(lib.setSetting);
  await tester.pumpWidget(
    MultiProvider(
      providers: testProviders(lib),
      child: MaterialApp(home: shell),
    ),
  );
  await tester.pump();
  return lib;
}

void main() {
  group('phone', () {
    testWidgets('opens on Up Next by default', (tester) async {
      await pumpShell(tester, const MobileShell(), {});
      expect(find.text('Queue'), findsWidgets);
      expect(find.text('Ep Two'), findsOneWidget);
    });

    testWidgets('opens on the chosen screen', (tester) async {
      await pumpShell(tester, const MobileShell(), {'startScreen': 'podcasts'});
      expect(find.text('Subscriptions'), findsOneWidget); // the screen header
    });

    testWidgets('"where I left off" remembers the last screen', (tester) async {
      final lib = await pumpShell(tester, const MobileShell(), {
        'startScreen': 'last',
      });
      await tester.tap(find.text('Episodes'));
      await tester.pump();
      expect(lib.settings.lastScreen, 'episodes');
      // A fresh start now opens there.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: testProviders(lib),
          child: const MaterialApp(home: MobileShell()),
        ),
      );
      await tester.pump();
      expect(
        find.text('Unplayed'),
        findsOneWidget,
      ); // the Episodes filter chips
    });
  });

  group('desktop', () {
    testWidgets('opens on Episodes by default', (tester) async {
      await pumpShell(
        tester,
        const DesktopShell(),
        {},
        size: const Size(1300, 900),
        ratio: 1,
      );
      expect(find.text('2 episodes, 0.5 hours'), findsOneWidget);
    });

    testWidgets('opens on the chosen place', (tester) async {
      await pumpShell(
        tester,
        const DesktopShell(),
        {'startScreen': 'queue'},
        size: const Size(1300, 900),
        ratio: 1,
      );
      expect(
        find.text('Starts in'),
        findsOneWidget,
      ); // only Up Next has this column
    });
  });
}
