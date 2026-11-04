import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/core/player.dart';

const feed = 'http://a.test/feed.xml';

Library makeLibrary() {
  final lib = Library();
  lib.podcasts[feed] = Podcast(feedUrl: feed, title: 'Show');
  lib.podcasts['http://b.test/f'] = Podcast(
    feedUrl: 'http://b.test/f',
    title: 'Other',
    subscribed: false,
  );
  void add(String guid, int minutes, {String f = feed}) {
    final e = Episode(
      feedUrl: f,
      guid: guid,
      title: guid,
      audioUrl: 'u$guid',
      published: minutes,
      durationMs: minutes * 60000,
    );
    lib.episodes[e.id] = e;
  }

  add('a', 10);
  add('b', 20);
  add('c', 30);
  add('x', 60, f: 'http://b.test/f');
  return lib;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // the player talks to platform plugins
  group('counts and listening totals', () {
    test(
      'queue length counts everything; time left counts only what remains',
      () {
        final lib = makeLibrary();
        lib.queue = ['$feed|a', '$feed|b'];
        expect(lib.queueTotalLength, const Duration(minutes: 30));
        lib.setProgress('$feed|b', 5 * 60000, 20 * 60000);
        expect(lib.queueTotalLength, const Duration(minutes: 30));
        expect(lib.queueRemaining, const Duration(minutes: 25));
      },
    );

    test('unplayed, favorite and history counts', () {
      final lib = makeLibrary();
      expect(
        lib.unplayedCount,
        3,
      ); // the unsubscribed podcast's episode does not count
      lib.markAllPlayed(['$feed|a'], true);
      expect(lib.unplayedCount, 2);
      lib.setFavorite('$feed|b', true);
      lib.setFavorite('$feed|c', true);
      lib.setFavorite('$feed|c', false);
      expect(lib.favoriteCount, 1);
      expect(lib.historyCount, 0);
      lib.setProgress('$feed|c', 1000, 30 * 60000);
      expect(lib.historyCount, 1);
    });

    test('statistics add up listening by podcast', () {
      final lib = makeLibrary();
      lib.markAllPlayed(['$feed|a'], true); // 10 min, finished
      lib.setProgress('$feed|b', 8 * 60000, 20 * 60000); // 8 of 20 min
      lib.setProgress(
        'http://b.test/f|x',
        15 * 60000,
        60 * 60000,
      ); // history from an unsubscribed show
      final st = lib.stats();
      expect(st.listened, const Duration(minutes: 33));
      expect(st.length, const Duration(minutes: 120));
      expect(st.played, 1);
      expect(st.inProgress, 2);
      expect(st.episodes, 4);
      expect(st.perPodcast.map((p) => p.title), [
        'Show',
        'Other',
      ]); // most listened first
      expect(st.perPodcast.first.listened, const Duration(minutes: 18));
      expect(st.perPodcast.first.played, 1);
    });

    test(
      'a podcast with nothing listened still shows if you are subscribed',
      () {
        final lib = makeLibrary();
        expect(lib.stats().perPodcast.map((p) => p.title), ['Show']);
      },
    );
  });

  group('sleep timer', () {
    test('counts down, can be extended, and pauses at zero', () {
      fakeAsync((async) {
        final player = PlayerController(makeLibrary());
        player.startSleepTimer(const Duration(minutes: 1));
        expect(player.sleepActive, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(player.sleepRemaining, const Duration(seconds: 30));

        player.extendSleepTimer(const Duration(minutes: 5));
        expect(player.sleepRemaining, const Duration(minutes: 5, seconds: 30));

        async.elapse(const Duration(minutes: 5, seconds: 31));
        async.flushMicrotasks();
        expect(player.sleepRemaining, isNull);
        expect(player.sleepActive, isFalse);
      });
    });

    test('cancelling stops it, and starting a new one replaces the old', () {
      fakeAsync((async) {
        final player = PlayerController(makeLibrary());
        player.startSleepTimer(const Duration(minutes: 10));
        player.startSleepTimer(const Duration(minutes: 2));
        expect(player.sleepRemaining, const Duration(minutes: 2));
        player.cancelSleepTimer();
        expect(player.sleepActive, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(player.sleepRemaining, isNull);
      });
    });

    test('"after this episode" stops the queue from moving on', () async {
      final lib = makeLibrary();
      lib.queue = ['$feed|a', '$feed|b', '$feed|c'];
      final player = PlayerController(lib)..current = lib.episodes['$feed|a'];
      player.sleepAfterEpisode();
      expect(player.sleepActive, isTrue);
      player.episodeCompletedForTest();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(player.current!.guid, 'a'); // did not start Ep b
      expect(player.sleepActive, isFalse);
      expect(lib.progressOf('$feed|a').played, isTrue);
    });
  });
}
