import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/core/opml.dart';
import 'package:sqlite3/sqlite3.dart';

import 'fixtures.dart';

const _feedXml = '''<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<title>Tech Show</title>
<item><title>Ep One</title><guid>guid-1</guid><pubDate>Tue, 14 Nov 2023 22:13:20 +0000</pubDate><itunes:duration>10:00</itunes:duration><enclosure url="http://a.test/1.mp3" type="audio/mpeg"/></item>
<item><title>Ep Two</title><guid>guid-2</guid><itunes:duration>20:00</itunes:duration><enclosure url="http://a.test/2.mp3" type="audio/mpeg"/></item>
</channel></rss>''';

/// Just enough of the gPodder v2 API to exercise the client: one user, one clock.
class FakeGpodder {
  int clock = 100;
  final subs = <String, int>{};
  final removed = <String, int>{};
  final actions = <Map<String, dynamic>>[];
  int requests = 0;

  http.Client client() => MockClient((req) async {
    requests++;
    if (req.url.host == 'a.test') return http.Response(_feedXml, 200);
    if (req.headers['Authorization'] !=
        'Basic ${base64Encode(utf8.encode('lane:pw'))}') {
      return http.Response('', 401);
    }
    final path = req.url.path;
    final since = int.tryParse(req.url.queryParameters['since'] ?? '') ?? 0;
    if (path.endsWith('/login.json') || path.contains('/devices/')) {
      return http.Response('{}', 200);
    }
    if (path.contains('/subscriptions/')) {
      if (req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'add': [
              for (final e in subs.entries)
                if (e.value > since) e.key,
            ],
            'remove': [
              for (final e in removed.entries)
                if (e.value > since) e.key,
            ],
            'timestamp': clock,
          }),
          200,
        );
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      clock++;
      for (final u in body['add']) {
        subs[u] = clock;
        removed.remove(u);
      }
      for (final u in body['remove']) {
        removed[u] = clock;
        subs.remove(u);
      }
      return http.Response(
        jsonEncode({'timestamp': clock, 'update_urls': []}),
        200,
      );
    }
    if (path.contains('/episodes/')) {
      if (req.method == 'GET') {
        final latest = <String, Map<String, dynamic>>{};
        for (final a in actions.where((a) => a['_clock'] > since)) {
          latest['${a['podcast']}|${a['episode']}'] = a;
        }
        return http.Response(
          jsonEncode({
            'actions': [
              for (final a in latest.values) {...a}..remove('_clock'),
            ],
            'timestamp': clock,
          }),
          200,
        );
      }
      clock++;
      for (final a in jsonDecode(req.body)) {
        actions.add({...Map<String, dynamic>.from(a), '_clock': clock});
      }
      return http.Response(
        jsonEncode({'timestamp': clock, 'update_urls': []}),
        200,
      );
    }
    return http.Response('', 404);
  });
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('AntennaPod backup import', () {
    late String path;
    setUp(() => path = makeAntennaPodBackup());
    tearDown(() => File(path).parent.deleteSync(recursive: true));

    test(
      'imports podcasts, settings, progress, queue, favorites and chapters',
      () {
        final lib = Library();
        final report = importAntennaPodBackup(lib, path);

        expect(report.podcasts, 2);
        expect(report.subscribed, 1);
        expect(report.skippedFeeds, 1);
        expect(report.skippedEpisodes, 1);
        expect(report.episodes, 3);
        expect(report.queued, 2);
        expect(report.favorites, 1);
        expect(report.chapters, 2);

        final tech = lib.podcasts['http://a.test/feed.xml']!;
        expect(tech.subscribed, isTrue);
        expect(tech.displayTitle, 'My Tech');
        expect(tech.speed, 1.5);
        expect(tech.skipIntroSec, 15);
        expect(tech.skipEndingSec, 5);
        expect(tech.tags, ['Tech', 'News']);
        expect(tech.username, 'bob');
        expect(tech.extra['autoDownload'], 0);
        expect(lib.podcasts['http://b.test/feed.xml']!.subscribed, isFalse);
        expect(
          lib.podcasts.containsKey('antennapod_local:/storage/x'),
          isFalse,
        );

        const one = 'http://a.test/feed.xml|guid-1',
            two = 'http://a.test/feed.xml|guid-2';
        expect(lib.progressOf(one).played, isTrue);
        expect(lib.progressOf(one).positionMs, 0);
        expect(lib.progressOf(two).positionMs, 300000);
        expect(lib.progressOf(two).lastPlayedAt, 1700600000000);
        expect(lib.queue, [two, one]); // Queue.id order, not item order
        expect(lib.historyEpisodes.map((e) => e.id), [
          two,
          one,
        ]); // newest listen first

        // The favorite's guid was NULL, so it falls back to the audio URL like the feed parser does.
        expect(lib.favoriteEpisodes.single.audioUrl, 'http://b.test/4.mp3');
        expect(
          lib.favoriteEpisodes.single.id,
          'http://b.test/feed.xml|http://b.test/4.mp3',
        );

        final ep2 = lib.episodes[two]!;
        expect(ep2.durationMs, 1200000);
        expect(ep2.chapters.map((c) => c.title), ['Intro', 'Main']);
        expect(ep2.chapters.last.startMs, 60000);
      },
    );

    test(
      'does not override newer progress, and keeps existing queue order',
      () {
        final lib = Library();
        const two = 'http://a.test/feed.xml|guid-2';
        lib.progress[two] = Progress(
          positionMs: 999000,
          updatedAt: 1800000000000,
        );
        lib.queue = ['other'];
        importAntennaPodBackup(lib, path);
        expect(lib.progressOf(two).positionMs, 999000);
        expect(lib.queue, ['other', two, 'http://a.test/feed.xml|guid-1']);
      },
    );

    test(
      'imported feeds merge with the live feed instead of duplicating episodes',
      () async {
        final lib = Library(client: FakeGpodder().client());
        importAntennaPodBackup(lib, path);
        await lib.refreshFeed('http://a.test/feed.xml');
        expect(lib.episodesOf('http://a.test/feed.xml'), hasLength(2));
        // Chapters from the backup survive the refresh.
        expect(
          lib.episodes['http://a.test/feed.xml|guid-2']!.chapters,
          hasLength(2),
        );
      },
    );

    test('rejects files that are not an AntennaPod backup', () {
      final other = '${File(path).parent.path}/other.db';
      sqlite3.open(other)
        ..execute('CREATE TABLE x (a)')
        ..close();
      expect(
        () => importAntennaPodBackup(Library(), other),
        throwsFormatException,
      );
      File('${File(path).parent.path}/junk.db')
          .writeAsStringSync('not sqlite at all');
      expect(
        () => importAntennaPodBackup(
          Library(),
          '${File(path).parent.path}/junk.db',
        ),
        throwsA(anything),
      );
    });
  });

  test('OPML import keeps folders as tags; export round-trips', () {
    final lib = Library();
    final n = importOpml(lib, '''<opml version="2.0"><head/><body>
      <outline text="Tech"><outline text="A" xmlUrl="http://a.test/feed.xml"/></outline>
      <outline text="B" xmlUrl="http://b.test/feed.xml"/></body></opml>''');
    expect(n, 2);
    expect(lib.podcasts['http://a.test/feed.xml']!.tags, ['Tech']);
    expect(
      buildOpml(lib.subscriptions),
      contains('xmlUrl="http://b.test/feed.xml"'),
    );
  });

  group('gPodder sync', () {
    test('subscriptions and progress flow between two devices', () async {
      final server = FakeGpodder();
      final a = Library(client: server.client());
      final b = Library(client: server.client());
      const url = 'http://a.test/feed.xml';
      const ep = '$url|guid-2';

      // Device A already has the podcast and has listened to 5 minutes.
      a.podcasts[url] = Podcast(
        feedUrl: url,
        title: 'Tech Show',
        updatedAt: 50,
      );
      await a.refreshFeed(url);
      await a.connectGpodder('http://gpodder.test/', 'lane', 'pw');
      a.setProgress(ep, 300000, 1200000);
      await a.sync();
      expect(server.subs.keys, [url]);
      final sent = server.actions.last;
      expect(sent['action'], 'play');
      expect(sent['episode'], 'http://a.test/2.mp3');
      expect(sent['position'], 300);
      expect(sent['total'], 1200);
      expect(
        sent['timestamp'],
        matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$')),
      );

      // Device B signs in: gets the subscription, then the position once the episode is known.
      await b.connectGpodder('http://gpodder.test', 'lane', 'pw');
      await settle();
      expect(b.isSubscribed(url), isTrue);
      expect(b.progressOf(ep).positionMs, 300000);
      expect(b.progressOf(ep).durationMs, 1200000);

      // B finishes the episode and unsubscribes; A sees both. (gPodder timestamps have
      // one-second resolution, so leave a gap after A's own change.)
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      b.markPlayed(ep, true);
      b.unsubscribe(url); // starts its own background sync
      await settle();
      await a.sync();
      await settle();
      expect(a.isSubscribed(url), isFalse);
      expect(a.progressOf(ep).played, isTrue);
    });

    test(
      'an older action from the server does not overwrite newer local progress',
      () async {
        final lib = Library();
        const url = 'http://a.test/feed.xml';
        lib.podcasts[url] = Podcast(feedUrl: url);
        lib.episodes['$url|g'] = Episode(
          feedUrl: url,
          guid: 'g',
          title: 't',
          audioUrl: 'http://a.test/x.mp3',
        );
        lib.progress['$url|g'] = Progress(
          positionMs: 500000,
          updatedAt: 2000000000000,
        );
        lib.applyGpodderActionsForTest([
          {
            'podcast': url,
            'episode': 'http://a.test/x.mp3',
            'action': 'play',
            'position': 10,
            'total': 100,
            'timestamp': '2020-01-01T00:00:00',
          },
        ]);
        expect(lib.progressOf('$url|g').positionMs, 500000);
      },
    );

    test('wrong password gives a readable error', () async {
      final lib = Library(client: FakeGpodder().client());
      await expectLater(
        lib.connectGpodder('http://gpodder.test', 'lane', 'nope'),
        throwsA(
          predicate((e) => e.toString().contains('Wrong username or password')),
        ),
      );
      expect(lib.gpodderEnabled, isFalse);
    });
  });
}
