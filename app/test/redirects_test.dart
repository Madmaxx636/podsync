import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/errors.dart';
import 'package:podsync/core/feed.dart';
import 'package:podsync/core/http_follow.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';

http.StreamedResponse redirect(
  String to, {
  int code = 302,
  Map<String, String> extra = const {},
}) => http.StreamedResponse(
  Stream.value([]),
  code,
  headers: {'location': to, ...extra},
);

http.StreamedResponse ok(
  List<int> bytes, {
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(bytes),
  200,
  contentLength: bytes.length,
  headers: headers,
);

void main() {
  group('following redirects', () {
    test('a chain longer than the five hops Dart allows by itself', () async {
      final seen = <String>[];
      final client = MockClient.streaming((req, _) async {
        seen.add(req.url.toString());
        expect(
          req.followRedirects,
          isFalse,
          reason: 'we follow them ourselves',
        );
        final n =
            int.tryParse(req.url.pathSegments.last.replaceAll('hop', '')) ?? -1;
        if (n >= 0 && n < 8) {
          return redirect('https://t${n + 1}.test/hop${n + 1}');
        }
        return ok([1, 2, 3]);
      });
      final r = await sendFollowingRedirects(
        client,
        Uri.parse('https://t0.test/hop0'),
      );
      expect(r.statusCode, 200);
      expect(await r.stream.toBytes(), [1, 2, 3]);
      expect(seen, hasLength(9)); // 8 redirects, then the file
    });

    test('relative locations resolve against the current address', () async {
      final client = MockClient.streaming((req, _) async {
        if (req.url.path == '/a/start') return redirect('next');
        if (req.url.path == '/a/next') return redirect('/root.mp3');
        return req.url.path == '/root.mp3'
            ? ok([9])
            : http.StreamedResponse(Stream.value([]), 404);
      });
      final r = await sendFollowingRedirects(
        client,
        Uri.parse('https://x.test/a/start'),
      );
      expect(r.statusCode, 200);
    });

    test('headers like Range are sent on every hop', () async {
      final ranges = <String?>[];
      final client = MockClient.streaming((req, _) async {
        ranges.add(req.headers['Range']);
        return req.url.path == '/go' ? redirect('/file') : ok([1]);
      });
      await sendFollowingRedirects(
        client,
        Uri.parse('https://x.test/go'),
        headers: {'Range': 'bytes=100-', 'User-Agent': 'T'},
      );
      expect(ranges, ['bytes=100-', 'bytes=100-']);
    });

    test(
      'a service that redirects in a loop until it sees its cookie',
      () async {
        var requests = 0;
        final client = MockClient.streaming((req, _) async {
          requests++;
          final cookie = req.headers['Cookie'] ?? '';
          if (cookie.contains('session=abc') && cookie.contains('b=2')) {
            return ok([7]);
          }
          // Cookies arrive comma-joined, and one has an Expires date with a comma in it.
          return redirect(
            'https://track.test/loop',
            extra: {
              'set-cookie': 'session=abc; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/, b=2; HttpOnly',
            },
          );
        });
        final r = await sendFollowingRedirects(
          client,
          Uri.parse('https://track.test/loop'),
        );
        expect(r.statusCode, 200);
        expect(requests, 2);
      },
    );

    test('cookies are only sent to the host that set them', () async {
      final cookiesSeen = <String, String?>{};
      final client = MockClient.streaming((req, _) async {
        cookiesSeen[req.url.host] = req.headers['Cookie'];
        if (req.url.host == 'a.test') {
          return redirect(
            'https://b.test/x',
            extra: {'set-cookie': 'secret=1'},
          );
        }
        return ok([1]);
      });
      await sendFollowingRedirects(client, Uri.parse('https://a.test/start'));
      expect(cookiesSeen['b.test'], isNull);
    });

    test(
      'a genuine loop gives up with a clear message instead of spinning',
      () async {
        var n = 0;
        final client = MockClient.streaming((req, _) async {
          n++;
          return redirect('https://loop.test/again');
        });
        await expectLater(
          sendFollowingRedirects(
            client,
            Uri.parse('https://loop.test/again'),
            maxHops: 10,
          ),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'message',
              contains('Too many redirects'),
            ),
          ),
        );
        expect(n, 11);
      },
    );

    test(
      'non-redirect answers, including errors, come back untouched',
      () async {
        final client = MockClient.streaming(
          (req, _) async => http.StreamedResponse(Stream.value([]), 404),
        );
        final r = await sendFollowingRedirects(
          client,
          Uri.parse('https://x.test/missing'),
        );
        expect(r.statusCode, 404);
      },
    );
  });

  group('error messages', () {
    test('keep the sentence, drop the class name', () {
      expect(
        cleanError(
          http.ClientException(
            'Redirect limit exceeded',
            Uri.parse('https://x.test'),
          ),
        ),
        'Redirect limit exceeded',
      );
      expect(
        cleanError(Exception('Feed returned HTTP 404')),
        'Feed returned HTTP 404',
      );
      expect(
        cleanError(const HttpException('Server answered HTTP 500')),
        'Server answered HTTP 500',
      );
      expect(cleanError(TimeoutException('x')), 'Timed out');
      expect(
        cleanError(const SocketException('Failed host lookup')),
        'Network error: Failed host lookup',
      );
      expect(
        cleanError(StateError('plain words')),
        'Bad state: plain words',
      ); // not an *Exception, left as it is
    });

    test(
      'only the leading prefix is removed, never the middle of a message',
      () {
        expect(
          cleanError(Exception('ClientException: nested')),
          'ClientException: nested',
        );
        expect(
          cleanError(Exception('Could not parse Exception: bad')),
          'Could not parse Exception: bad',
        );
      },
    );
  });

  group('downloads and feeds through long redirect chains', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('podsync_redirect'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('an episode behind eight redirects downloads', () async {
      final client = MockClient.streaming((req, _) async {
        final n = int.tryParse(req.url.pathSegments.last.replaceAll('hop', ''));
        if (req.url.host == 'tracker.test' && n != null && n < 8) {
          return redirect('https://tracker.test/hop${n + 1}');
        }
        if (req.url.host == 'tracker.test') {
          return redirect('https://cdn.test/episode.mp3');
        }
        return ok(List.filled(4000, 5));
      });
      final lib = Library()
        ..podcasts['f'] = Podcast(feedUrl: 'f', title: 'Show');
      final dm = DownloadManager(
        lib,
        client: client,
        directory: Directory('${dir.path}/files'),
        indexFile: File('${dir.path}/i.json'),
        watchNetwork: false,
        networkAllowed: () async => true,
      );
      final e = Episode(
        feedUrl: 'f',
        guid: 'g',
        title: 'Long chain',
        audioUrl: 'https://tracker.test/hop0',
        published: 1,
      );
      lib.episodes[e.id] = e;
      dm.download(e);
      await dm.whenIdle();
      expect(dm.infoOf(e.id)!.error, isNull);
      expect(dm.isDownloaded(e.id), isTrue);
      expect(File(dm.pathOf(e.id)!).lengthSync(), 4000);
      dm.dispose();
    });

    test('a loop that never ends fails with readable words', () async {
      final client = MockClient.streaming(
        (req, _) async => redirect('https://tracker.test/forever'),
      );
      final lib = Library()
        ..podcasts['f'] = Podcast(feedUrl: 'f', title: 'Show');
      final dm = DownloadManager(
        lib,
        client: client,
        directory: Directory('${dir.path}/files'),
        indexFile: File('${dir.path}/i.json'),
        watchNetwork: false,
        networkAllowed: () async => true,
      );
      final e = Episode(
        feedUrl: 'f',
        guid: 'g',
        title: 'Loop',
        audioUrl: 'https://tracker.test/forever',
        published: 1,
      );
      lib.episodes[e.id] = e;
      dm.download(e);
      await dm.whenIdle();
      final info = dm.infoOf(e.id)!;
      expect(info.state, DownloadState.failed);
      expect(info.error, contains('Too many redirects'));
      expect(info.error, isNot(contains('Exception')));
      dm.dispose();
    });

    test('a feed address that redirects several times still loads', () async {
      var hops = 0;
      final client = MockClient.streaming((req, _) async {
        if (hops < 7) {
          hops++;
          return redirect('https://feeds.test/r$hops');
        }
        return ok(
          '<rss><channel><title>Moved</title><item><title>E</title><guid>g</guid><enclosure url="http://a/1.mp3"/></item></channel></rss>'
              .codeUnits,
        );
      });
      final feed = await fetchFeed('https://feeds.test/start', client: client);
      expect(feed.podcast.title, 'Moved');
      expect(feed.episodes, hasLength(1));
    });
  });
}
