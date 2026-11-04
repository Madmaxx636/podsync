import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/core/settings.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/pal.dart';
import 'package:podsync/ui/settings.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

const feedUrl = 'http://a.test/feed.xml';

String rss(List<int> days) =>
    '''<?xml version="1.0"?><rss version="2.0"><channel><title>Show</title>
${[for (final d in days) '<item><title>Ep $d</title><guid>g$d</guid><pubDate>${d.toString().padLeft(2, '0')} Nov 2023 10:00:00 +0000</pubDate><enclosure url="http://a.test/$d.mp3" type="audio/mpeg"/></item>'].join()}
</channel></rss>''';

Library libWithFeed(List<int> Function() days) =>
    Library(client: MockClient((req) async => http.Response(rss(days()), 200)));

double luminance(Color c) => c.computeLuminance();
double contrast(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
}

Widget app(Library lib, Widget home, {ThemeMode mode = ThemeMode.light}) =>
    MultiProvider(
      providers: testProviders(lib),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: mode,
        home: home,
      ),
    );

void main() {
  group('settings model', () {
    test('every default round-trips through JSON; unknown keys and wrong types are ignored', () {
      final s = AppSettings();
      s.set('accent', 0xFFE91E63);
      s.set('textScale', 1.3);
      final copy = AppSettings(jsonDecode(jsonEncode(s.toJson())));
      expect(copy.accent, 0xFFE91E63);
      expect(copy.textScale, 1.3);
      final messy = AppSettings({
        'textScale': 2,
        'themeMode': 5,
        'nonsense': true,
        'colDate': 'yes',
      });
      expect(messy.textScale, 2.0); // int from JSON becomes a double
      expect(messy.themeMode, 'system'); // wrong type ignored
      expect(messy.colDate, isTrue);
    });

    test(
      'only synced settings are sent to the server and accepted from it',
      () {
        final lib = Library();
        lib.setSetting('smartRewindSec', 10); // synced
        lib.setSetting('accent', 0xFF000000); // this device only
        final record = lib.exportBackup(); // sanity: backup holds both
        expect(jsonDecode(record)['settings']['accent'], 0xFF000000);

        final other = Library();
        other.applyRemote([
          {
            'type': 'setting',
            'key': 'prefs',
            'updated_at': 5,
            'deleted': false,
            'data': {
              'speed': 1.5,
              'more': {'smartRewindSec': 15, 'accent': 1, 'hidePlayed': true},
            },
          },
        ]);
        expect(other.settings.smartRewindSec, 15);
        expect(other.settings.hidePlayed, isTrue);
        expect(
          other.settings.accent,
          AppSettings.defaults['accent'],
        ); // device-only values never arrive
        expect(other.speed, 1.5);
      },
    );

    test(
      'resetSettings restores defaults; wipeAll clears data and sign-ins',
      () async {
        final lib = Library()..token = 't';
        lib.setSetting('themeMode', 'dark');
        lib.podcasts['x'] = Podcast(feedUrl: 'x');
        lib.resetSettings();
        expect(lib.settings.themeMode, 'system');
        expect(lib.podcasts, isNotEmpty);
        await lib.wipeAll();
        expect(lib.podcasts, isEmpty);
        expect(lib.signedIn, isFalse);
      },
    );

    test('backup restores data but leaves secrets out and keeps this device signed in', () {
      final a = Library()
        ..token = 'secret-token'
        ..gPass = 'gpw';
      a.podcasts[feedUrl] = Podcast(
        feedUrl: feedUrl,
        title: 'Show',
        password: 'feedpw',
      );
      a.episodes['$feedUrl|g1'] = Episode(
        feedUrl: feedUrl,
        guid: 'g1',
        title: 'One',
        audioUrl: 'http://a.test/1.mp3',
      );
      a.setProgress('$feedUrl|g1', 5000, 60000);
      a.setFavorite('$feedUrl|g1', true);
      a.queue = ['$feedUrl|g1'];
      final json = a.exportBackup();
      expect(json, isNot(contains('secret-token')));
      expect(json, isNot(contains('feedpw')));
      expect(json, isNot(contains('gpw')));

      final b = Library()..token = 'my-token';
      b.restoreBackup(json);
      expect(b.token, 'my-token');
      expect(b.podcasts[feedUrl]!.title, 'Show');
      expect(b.progressOf('$feedUrl|g1').positionMs, 5000);
      expect(b.isFavorite('$feedUrl|g1'), isTrue);
      expect(b.queue, ['$feedUrl|g1']);
      expect(() => b.restoreBackup('{"hello": 1}'), throwsFormatException);
    });
  });

  group('settings change behaviour', () {
    test('episode order setting flips every list', () {
      final lib = Library();
      lib.podcasts[feedUrl] = Podcast(feedUrl: feedUrl);
      for (final d in [1, 2, 3]) {
        final e = Episode(
          feedUrl: feedUrl,
          guid: 'g$d',
          title: 'E$d',
          audioUrl: 'u$d',
          published: d,
        );
        lib.episodes[e.id] = e;
      }
      expect(lib.episodesOf(feedUrl).map((e) => e.published), [3, 2, 1]);
      lib.setSetting('sortOldestFirst', true);
      expect(lib.episodesOf(feedUrl).map((e) => e.published), [1, 2, 3]);
      expect(lib.allEpisodes.map((e) => e.published), [1, 2, 3]);
    });

    test('new episodes go to the queue per the global setting, and a podcast can override it', () async {
      var days = [10];
      final lib = libWithFeed(() => days);
      await lib.subscribe(feedUrl);
      days = [10, 12];
      await lib.refreshFeed(feedUrl);
      expect(lib.queue, isEmpty); // default: do nothing

      lib.setSetting('newEpisodesAction', 1);
      days = [10, 12, 14];
      await lib.refreshFeed(feedUrl);
      expect(lib.queue, ['$feedUrl|g14']);

      lib.setSetting('newEpisodesAction', 2); // front of the queue
      days = [10, 12, 14, 16];
      await lib.refreshFeed(feedUrl);
      expect(lib.queue, ['$feedUrl|g16', '$feedUrl|g14']);

      lib.updatePodcastSettings(
        feedUrl,
        newEpisodesAction: 3,
      ); // this podcast says do nothing
      days = [10, 12, 14, 16, 18];
      await lib.refreshFeed(feedUrl);
      expect(lib.queue, isNot(contains('$feedUrl|g18')));
    });

    test('episodes-to-keep drops old episodes but never ones you have started, queued or favorited', () async {
      final lib = libWithFeed(() => [1, 2, 3, 4, 5, 6]);
      await lib.subscribe(feedUrl);
      lib.setProgress('$feedUrl|g1', 1000, 5000);
      lib.setFavorite('$feedUrl|g2', true);
      lib.enqueue('$feedUrl|g3');
      lib.setSetting('maxEpisodesPerFeed', 2);
      await lib.refreshFeed(feedUrl);
      expect(lib.episodesOf(feedUrl).map((e) => e.guid).toSet(), {
        'g6',
        'g5',
        'g1',
        'g2',
        'g3',
      });
    });

    test('date format setting changes how dates are shown', () {
      final lib = Library();
      lib.setSetting('dateStyle', 'iso');
      expect(currentDateStyle, 'iso');
      lib.setSetting('dateStyle', 'mdy');
      expect(currentDateStyle, 'mdy');
    });
  });

  group('settings screens', () {
    test('palettes keep text readable on their backgrounds', () {
      for (final pal in [Pal.light, Pal.dark]) {
        expect(contrast(pal.text, pal.bg), greaterThan(7));
        expect(contrast(pal.text, pal.stripe), greaterThan(7));
        expect(contrast(pal.text, pal.sidebar), greaterThan(7));
        expect(contrast(pal.muted, pal.bg), greaterThan(4.5));
        expect(contrast(pal.muted, pal.sidebar), greaterThan(4.5));
        expect(contrast(pal.text, pal.toolbarTop), greaterThan(4.5));
        expect(contrast(pal.text, pal.toolbarBottom), greaterThan(4.5));
        expect(contrast(Colors.white, pal.selected), greaterThan(3.5));
      }
    });

    testWidgets(
      'desktop renders in dark mode without errors, with the settings pane',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final lib = libWithFeed(() => [1, 2]);
        await lib.subscribe(feedUrl);
        await tester.pumpWidget(
          app(lib, const DesktopShell(), mode: ThemeMode.dark),
        );
        await tester.pump();
        await tester.tap(find.text('Settings and Sync'));
        await tester.pump();
        for (final title in [
          'Appearance',
          'Playback',
          'Library and feeds',
          'Sync',
          'Podcasts',
          'Import and backup',
          'Desktop layout',
          'Advanced and about',
        ]) {
          final entry = find.descendant(
            of: find.byType(SettingsPane),
            matching: find.text(title),
          );
          expect(entry, findsWidgets, reason: 'category $title is listed');
          await tester.tap(entry.first);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: title);
        }
      },
    );

    testWidgets(
      'a toggle and a choice in the settings pane change the setting',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final lib = Library();
        await tester.pumpWidget(app(lib, const Scaffold(body: SettingsPane())));
        await tester.pump();

        await tester.tap(find.text('Compact layout'));
        await tester.pump();
        expect(lib.settings.compact, isTrue);

        await tester.tap(find.text('Theme'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(lib.settings.themeMode, 'dark');

        await tester.tap(find.text('Playback'));
        await tester.pump();
        await tester.tap(find.text('Smart rewind'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10 s').last);
        await tester.pumpAndSettle();
        expect(lib.settings.smartRewindSec, 10);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'phone settings: every group opens, and e-ink pages them without scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final lib = Library();
        lib.setEink(true);
        await tester.pumpWidget(app(lib, const Scaffold(body: SettingsHome())));
        await tester.pump();
        expect(find.byType(Scrollable), findsNothing);
        for (final cat in settingsCategories(
          lib,
          DownloadManager(lib, watchNetwork: false),
          android: Platform.isAndroid,
        )) {
          // Open the group directly, as tapping would.
          await tester.pumpWidget(app(lib, SettingsPage(cat.title)));
          await tester.pump();
          expect(
            find.byType(Scrollable),
            findsNothing,
            reason: '${cat.title} must not scroll in e-ink mode',
          );
          expect(tester.takeException(), isNull, reason: cat.title);
        }
      },
    );
  });
}
