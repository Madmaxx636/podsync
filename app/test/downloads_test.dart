import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/downloads.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';

const feed = 'http://feeds.test/show.xml';

/// 10 KB of recognisable bytes per episode.
List<int> audio(String name) =>
    List.generate(10240, (i) => (name.codeUnitAt(0) + i) & 0xff);

class Env {
  Env() {
    dir = Directory.systemTemp.createTempSync('podsync_dl');
    lib = Library(client: MockClient(feedHandler));
    lib.podcasts[feed] = Podcast(feedUrl: feed, title: 'The Show');
    dm = DownloadManager(
      lib,
      client: MockClient.streaming(audioHandler),
      directory: Directory('${dir.path}/files'),
      indexFile: File('${dir.path}/index.json'),
      networkAllowed: () async => networkOk,
      watchNetwork: false,
    );
  }

  late final Directory dir;
  late final Library lib;
  late final DownloadManager dm;
  bool networkOk = true;
  final requests = <String>[]; // "GET /a.mp3 range=bytes=5-"
  final failing = <String>{}; // audio paths answering 500
  final slow = <String>{}; // audio paths that stream slowly
  final ignoreRange = <String>{};
  Completer<void>? gate; // when set, audio responses wait for it
  var feedItems = <int>[1];

  Future<http.Response> feedHandler(http.Request r) async => http.Response(
    '<rss version="2.0"><channel><title>The Show</title>${[for (final n in feedItems) '<item><title>Ep $n</title><guid>g$n</guid><pubDate>${n.toString().padLeft(2, '0')} Nov 2023 10:00:00 +0000</pubDate><enclosure url="http://audio.test/$n.mp3" type="audio/mpeg"/></item>'].join()}</channel></rss>',
    200,
  );

  Future<http.StreamedResponse> audioHandler(
    http.BaseRequest r,
    http.ByteStream body,
  ) async {
    final name = r.url.pathSegments.last;
    requests.add('GET /$name range=${r.headers['Range'] ?? ''}');
    if (gate != null) await gate!.future;
    if (failing.contains(name)) {
      return http.StreamedResponse(Stream.value([]), 500);
    }
    final bytes = audio(name);
    final range = r.headers['Range'];
    var start = 0;
    var status = 200;
    if (range != null && !ignoreRange.contains(name)) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      status = 206;
    }
    final rest = bytes.sublist(start);
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < rest.length; i += 1024) {
        if (slow.contains(name)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        yield rest.sublist(i, (i + 1024).clamp(0, rest.length));
      }
    }

    return http.StreamedResponse(chunks(), status, contentLength: rest.length);
  }

  Episode add(int n, {bool queue = false, String title = ''}) {
    final e = Episode(
      feedUrl: feed,
      guid: 'g$n',
      title: title.isEmpty ? 'Ep $n' : title,
      audioUrl: 'http://audio.test/$n.mp3',
      published: n * 1000,
    );
    lib.episodes[e.id] = e;
    if (queue) lib.queue.add(e.id);
    return e;
  }

  void tearDown() {
    dm.dispose();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late Env env;
  setUp(() => env = Env());
  tearDown(() => env.tearDown());

  group('downloading', () {
    test(
      'saves the file, names it sensibly, and remembers it across restarts',
      () async {
        final e = env.add(1);
        env.dm.download(e);
        expect(env.dm.infoOf(e.id)!.state, isNot(DownloadState.done));
        await env.dm.whenIdle();

        final path = env.dm.pathOf(e.id)!;
        expect(File(path).readAsBytesSync(), audio('1.mp3'));
        expect(path, contains('The Show'));
        expect(path, endsWith('.mp3'));
        expect(File('$path.part').existsSync(), isFalse);
        expect(env.dm.totalBytes, 10240);
        expect(env.dm.isDownloaded(e.id), isTrue);

        await env.dm.saveNow();
        final again = DownloadManager(
          env.lib,
          indexFile: File('${env.dir.path}/index.json'),
          watchNetwork: false,
        );
        await again.start();
        expect(again.isDownloaded(e.id), isTrue);
        expect(again.pathOf(e.id), path);
        again.dispose();
      },
    );

    test('a file deleted behind its back is noticed', () async {
      final e = env.add(1);
      env.dm.download(e);
      await env.dm.whenIdle();
      File(env.dm.pathOf(e.id)!).deleteSync();
      expect(env.dm.pathOf(e.id), isNull);
      expect(env.dm.isDownloaded(e.id), isFalse);
    });

    test('a failed download says why and can be retried', () async {
      final e = env.add(1);
      env.failing.add('1.mp3');
      env.dm.download(e);
      await env.dm.whenIdle();
      expect(env.dm.infoOf(e.id)!.state, DownloadState.failed);
      expect(env.dm.infoOf(e.id)!.error, contains('500'));
      expect(env.dm.failedIds, [e.id]);

      env.failing.clear();
      env.dm.retry(e.id);
      await env.dm.whenIdle();
      expect(env.dm.isDownloaded(e.id), isTrue);
    });

    test('cancelling a running download leaves no file behind', () async {
      final e = env.add(1);
      env.slow.add('1.mp3');
      env.dm.download(e);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(env.dm.activeIds, [e.id]);
      env.dm.cancel(e.id);
      await env.dm.whenIdle();
      expect(env.dm.infoOf(e.id), isNull);
      final leftovers = Directory('${env.dir.path}/files').existsSync()
          ? Directory('${env.dir.path}/files')
                .listSync(recursive: true)
                .whereType<File>()
          : <File>[];
      expect(leftovers, isEmpty);
    });

    test('resumes a partial file when the server supports ranges, and restarts when it does not', () async {
      final e = env.add(1);
      env.dm.download(e);
      await env.dm.whenIdle();
      final path = env.dm.pathOf(e.id)!;
      await env.dm.delete(e.id);
      // Leave 4000 good bytes behind as a .part, as an interrupted download would.
      File('$path.part').writeAsBytesSync(audio('1.mp3').sublist(0, 4000));

      env.requests.clear();
      env.dm.download(e);
      await env.dm.whenIdle();
      expect(env.requests.single, 'GET /1.mp3 range=bytes=4000-');
      expect(File(env.dm.pathOf(e.id)!).readAsBytesSync(), audio('1.mp3'));

      await env.dm.delete(e.id);
      File('$path.part').writeAsBytesSync(
        List.filled(4000, 7),
      ); // garbage the server will not skip past
      env.ignoreRange.add('1.mp3');
      env.dm.download(e);
      await env.dm.whenIdle();
      expect(File(env.dm.pathOf(e.id)!).readAsBytesSync(), audio('1.mp3'));
    });

    test('respects the limit on simultaneous downloads', () async {
      env.lib.setSetting('maxDownloads', 1);
      final eps = [for (var i = 1; i <= 3; i++) env.add(i)];
      env.gate = Completer<void>();
      env.dm.downloadAll(eps);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(env.dm.activeIds, hasLength(1));
      expect(env.dm.queuedIds, hasLength(2));
      env.gate!.complete();
      await env.dm.whenIdle();
      expect(env.dm.doneCount, 3);
    });

    test('Wi-Fi only: waits on mobile data and goes once allowed', () async {
      final e = env.add(1);
      env.networkOk = false;
      env.dm.download(e);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(env.dm.infoOf(e.id)!.state, DownloadState.queued);
      expect(env.dm.infoOf(e.id)!.error, 'Waiting for Wi-Fi');
      expect(env.requests, isEmpty);

      env.networkOk = true;
      env.dm.resume();
      await env.dm.whenIdle();
      expect(env.dm.isDownloaded(e.id), isTrue);
    });

    test('the Wi-Fi-only setting can be turned off', () async {
      env.networkOk = false;
      env.lib.setSetting('downloadWifiOnly', false);
      final e = env.add(1);
      env.dm.download(e);
      await env.dm.whenIdle();
      expect(env.dm.isDownloaded(e.id), isTrue);
    });

    test('delete, delete played and delete all', () async {
      final eps = [for (var i = 1; i <= 3; i++) env.add(i)];
      env.dm.downloadAll(eps);
      await env.dm.whenIdle();
      env.lib.markAllPlayed([eps[0].id], true);
      expect(await env.dm.deletePlayed(), 1);
      expect(env.dm.doneIds.toSet(), {eps[1].id, eps[2].id});
      await env.dm.deleteAll();
      expect(env.dm.doneCount, 0);
      expect(env.dm.totalBytes, 0);
    });
  });

  group('automatic rules', () {
    setUp(() async {
      await env.dm.start();
    });

    test('Up Next: keeps the next N episodes downloaded, including ones added later', () async {
      for (var i = 1; i <= 4; i++) {
        env.add(i, queue: true);
      }
      env.lib.setSetting('autoDownloadQueueCount', 2);
      env.lib.setSetting('autoDownloadQueue', true);
      await env.dm.whenIdle();
      expect(env.dm.doneIds.toSet(), {'$feed|g1', '$feed|g2'});

      // Playing something to the end moves the window along; adding at the front downloads it too.
      final front = env.add(9);
      env.lib.enqueue(front.id, next: true);
      await env.dm.whenIdle();
      expect(env.dm.isDownloaded(front.id), isTrue);
    });

    test('Up Next count 0 means everything queued', () async {
      for (var i = 1; i <= 4; i++) {
        env.add(i, queue: true);
      }
      env.lib.setSetting('autoDownloadQueueCount', 0);
      env.lib.setSetting('autoDownloadQueue', true);
      await env.dm.whenIdle();
      expect(env.dm.doneCount, 4);
    });

    test('nothing downloads on its own when the setting is off', () async {
      env.add(1, queue: true);
      env.lib.enqueue('$feed|g1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(env.dm.allIds, isEmpty);
    });

    test('an episode you removed by hand is not fetched again while it stays queued', () async {
      final e = env.add(1, queue: true);
      env.lib.setSetting('autoDownloadQueue', true);
      await env.dm.whenIdle();
      await env.dm.delete(e.id);
      env.lib.setSetting('muted', true); // any library change
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(env.dm.isDownloaded(e.id), isFalse);
      expect(env.dm.isBusy(e.id), isFalse);
    });

    test('new episodes: global setting, per-podcast override either way, and the per-refresh limit', () async {
      final pc = env.lib.podcasts[feed]!;
      final arrivals = [for (var i = 1; i <= 5; i++) env.add(i)];

      env.dm.handleNewEpisodes(pc, arrivals); // global off
      expect(env.dm.allIds, isEmpty);

      env.lib.setSetting('autoDownloadNew', true);
      env.lib.setSetting('autoDownloadNewLimit', 2);
      env.dm.handleNewEpisodes(pc, arrivals);
      await env.dm.whenIdle();
      expect(env.dm.doneIds.toSet(), {
        '$feed|g5',
        '$feed|g4',
      }); // the newest two

      await env.dm.deleteAll();
      pc.extra['autoDownloadNew'] = 2; // never for this podcast
      env.dm.handleNewEpisodes(pc, arrivals);
      expect(env.dm.allIds, isEmpty);

      env.lib.setSetting('autoDownloadNew', false);
      pc.extra['autoDownloadNew'] = 1; // always for this podcast
      env.dm.handleNewEpisodes(pc, arrivals);
      await env.dm.whenIdle();
      expect(env.dm.doneCount, 2);
    });

    test('a refresh that finds a new episode downloads it', () async {
      env.lib.setSetting('autoDownloadNew', true);
      env.lib.podcasts[feed] = Podcast(feedUrl: feed, title: 'The Show');
      await env.lib.subscribe(
        feed,
      ); // first fetch: everything is new, so nothing is auto-downloaded
      await env.dm.whenIdle();
      expect(env.dm.allIds, isEmpty);
      env.feedItems = [1, 2];
      await env.lib.refreshFeed(feed);
      await env.dm.whenIdle();
      expect(env.dm.doneIds, ['$feed|g2']);
    });

    Future<String> downloaded(int n) async {
      final e = env.add(n);
      env.dm.download(e);
      await env.dm.whenIdle();
      return e.id;
    }

    test(
      'auto-delete as soon as played removes the file; unplayed ones stay',
      () async {
        final a = await downloaded(1);
        final b = await downloaded(2);
        env.lib.setSetting('autoDeleteHours', 0);
        env.lib.markAllPlayed([a], true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(env.dm.isDownloaded(a), isFalse);
        expect(env.dm.isDownloaded(b), isTrue);
      },
    );

    test('auto-delete with a delay waits, favorites and the playing episode are kept', () async {
      final a = await downloaded(1);
      final fav = await downloaded(2);
      final playing = await downloaded(3);
      env.lib.markAllPlayed([a, fav, playing], true);
      env.lib.setFavorite(fav, true);
      env.dm.isInUse = (id) => id == playing;

      env.lib.setSetting('autoDeleteHours', 24); // played just now: too soon
      expect(env.dm.sweep(), 0);

      env.lib.progress[a]!.updatedAt =
          DateTime.now().millisecondsSinceEpoch - 25 * 3600000;
      env.lib.progress[fav]!.updatedAt = env.lib.progress[a]!.updatedAt;
      env.lib.progress[playing]!.updatedAt = env.lib.progress[a]!.updatedAt;
      expect(env.dm.sweep(), 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(env.dm.isDownloaded(a), isFalse);
      expect(env.dm.isDownloaded(fav), isTrue);
      expect(env.dm.isDownloaded(playing), isTrue);

      // Turning "keep favorites" off lets the next clean-up take it.
      env.lib.setSetting('keepFavoriteDownloads', false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(env.dm.isDownloaded(fav), isFalse);
      expect(env.dm.isDownloaded(playing), isTrue); // still being listened to
    });

    test('auto-delete never touches unplayed downloads, and podcasts can override it', () async {
      final a = await downloaded(1);
      env.lib.setSetting('autoDeleteHours', 0);
      env.dm.sweep();
      expect(env.dm.isDownloaded(a), isTrue); // not played

      env.lib.podcasts[feed]!.extra['autoDeleteAction'] =
          2; // never, for this podcast
      env.lib.markAllPlayed([a], true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(env.dm.isDownloaded(a), isTrue);

      env.lib.setSetting('autoDeleteHours', -1); // globally never...
      expect(env.dm.sweep(), 0);
      env.lib.podcasts[feed]!.extra['autoDeleteAction'] =
          1; // ...but always for this podcast
      expect(env.dm.sweep(), 1);
    });
  });
}
