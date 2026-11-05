import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/ui/download_folder.dart';
import 'package:podsync/ui/settings.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

Widget app(Library lib, Widget home) => MultiProvider(
  providers: testProviders(lib),
  child: MaterialApp(home: home),
);

void main() {
  Future<void> pumpPage(WidgetTester tester, Library lib, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(lib, page));
    await tester.pump();
  }

  testWidgets('colour-only settings disappear when e-ink mode is on', (
    tester,
  ) async {
    final colour = Library();
    await pumpPage(tester, colour, const SettingsPage('Appearance'));
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Accent colour'), findsOneWidget);
    expect(find.text('Compact layout'), findsOneWidget);

    final eink = Library()..setEink(true);
    await pumpPage(tester, eink, const SettingsPage('Appearance'));
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Accent colour'), findsNothing);
    expect(find.text('Compact layout'), findsNothing);
    expect(find.text('Text size'), findsOneWidget); // still relevant
  });

  test('the e-ink page lists its details only while e-ink is on', () {
    final lib = Library();
    List<String> titles() => settingsCategories(
      lib,
      DownloadManager(lib, watchNetwork: false),
      android: true,
    ).firstWhere((c) => c.title == 'E-ink').items.map((i) => i.title).toList();
    expect(titles(), ['E-ink mode']);
    lib.setEink(true);
    expect(titles(), contains('Row size'));
    expect(titles(), contains('Swipe to turn pages'));
  });

  testWidgets('the settings home is grouped under headings', (tester) async {
    await pumpPage(tester, Library(), const Scaffold(body: SettingsHome()));
    for (final h in ['LISTENING', 'LIBRARY', 'DISPLAY']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Playback'), findsOneWidget);
  });

  test('the download folder is named plainly', () {
    expect(downloadFolderLabel(''), 'In PodSync (default)');
    expect(
      downloadFolderLabel('/storage/emulated/0/Podcasts'),
      '…/emulated/0/Podcasts'.replaceFirst('emulated/0/', '0/'),
    );
  });
}
