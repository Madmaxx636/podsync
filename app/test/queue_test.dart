import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';

const feed = 'http://a.test/feed.xml';

/// A library with five queued episodes of different dates, lengths and titles.
Library makeLibrary() {
  final lib = Library();
  lib.podcasts[feed] = Podcast(feedUrl: feed, title: 'Show');
  lib.podcasts['http://b.test/f'] = Podcast(
    feedUrl: 'http://b.test/f',
    title: 'Alpha',
  );
  void add(
    String guid,
    String title,
    int published,
    int minutes, {
    String f = feed,
  }) {
    final e = Episode(
      feedUrl: f,
      guid: guid,
      title: title,
      audioUrl: 'u$guid',
      published: published,
      durationMs: minutes * 60000,
    );
    lib.episodes[e.id] = e;
  }

  add('a', 'Charlie', 300, 30);
  add('b', 'alpha', 100, 10);
  add('c', 'Echo', 500, 50);
  add('d', 'Bravo', 200, 20, f: 'http://b.test/f');
  add('e', 'Delta', 400, 40);
  lib.queue = [
    for (final g in ['a', 'b', 'c', 'd', 'e'])
      g == 'd' ? 'http://b.test/f|d' : '$feed|$g',
  ];
  return lib;
}

List<String> guids(Library lib) => [
  for (final id in lib.queue) id.split('|').last,
];

void main() {
  group('queue sorting', () {
    test('by release date, both directions', () {
      final lib = makeLibrary();
      lib.sortQueue(QueueSort.oldestFirst);
      expect(guids(lib), ['b', 'd', 'a', 'e', 'c']);
      lib.sortQueue(QueueSort.newestFirst);
      expect(guids(lib), ['c', 'e', 'a', 'd', 'b']);
    });

    test('by title ignores case; by podcast groups then orders by date', () {
      final lib = makeLibrary();
      lib.sortQueue(QueueSort.title);
      expect(guids(lib), [
        'b',
        'd',
        'a',
        'e',
        'c',
      ]); // alpha Bravo Charlie Delta Echo
      lib.sortQueue(QueueSort.podcast);
      expect(guids(lib), [
        'd',
        'b',
        'a',
        'e',
        'c',
      ]); // Alpha's, then Show's oldest first
    });

    test('by time left uses what is still to hear, not the full length', () {
      final lib = makeLibrary();
      lib.setProgress(
        '$feed|c',
        49 * 60000,
        50 * 60000,
      ); // 50 min episode with 1 min left
      lib.sortQueue(QueueSort.shortest);
      expect(guids(lib).first, 'c');
      lib.sortQueue(QueueSort.longest);
      expect(guids(lib).first, 'e');
    });

    test(
      'keeps the playing episode first and leaves unknown episodes at the end',
      () {
        final lib = makeLibrary();
        lib.queue.add('ghost|missing');
        lib.sortQueue(QueueSort.newestFirst, pinId: '$feed|a');
        expect(guids(lib).first, 'a');
        expect(guids(lib).last, 'missing');
        lib.sortQueue(
          QueueSort.oldestFirst,
          pinId: '$feed|c',
        ); // pin is not first, so it sorts normally
        expect(guids(lib).first, 'b');
      },
    );

    test('shuffle keeps every episode and the pinned one in front', () {
      final lib = makeLibrary();
      lib.shuffleQueue(pinId: '$feed|a');
      expect(guids(lib).first, 'a');
      expect(guids(lib).toSet(), {'a', 'b', 'c', 'd', 'e'});
    });
  });

  group('queue moving', () {
    test('move several items to a spot, keeping their order', () {
      final lib = makeLibrary();
      lib.moveQueueItems(['$feed|b', '$feed|e'], 3); // before "d"
      expect(guids(lib), ['a', 'c', 'b', 'e', 'd']);
      lib.moveQueueItems(['$feed|a'], lib.queue.length); // to the end
      expect(guids(lib), ['c', 'b', 'e', 'd', 'a']);
      lib.moveQueueItems(['$feed|e', 'http://b.test/f|d'], 0); // to the top
      expect(guids(lib), ['e', 'd', 'c', 'b', 'a']);
    });

    test('nudge moves a block one step and stops at the edges', () {
      final lib = makeLibrary();
      lib.nudgeInQueue(['$feed|b', '$feed|c'], -1);
      expect(guids(lib), ['b', 'c', 'a', 'd', 'e']);
      lib.nudgeInQueue(['$feed|b', '$feed|c'], -1);
      expect(guids(lib), ['b', 'c', 'a', 'd', 'e']); // already at the top
      lib.nudgeInQueue(['$feed|e'], 1);
      expect(guids(lib), ['b', 'c', 'a', 'd', 'e']); // already at the bottom
      lib.nudgeInQueue(['$feed|c'], 1);
      expect(guids(lib), ['b', 'a', 'c', 'd', 'e']);
    });

    test('reorder (drag) uses the usual list semantics', () {
      final lib = makeLibrary();
      lib.reorderQueue(0, 3);
      expect(guids(lib), ['b', 'c', 'a', 'd', 'e']);
    });
  });

  group('queue undo', () {
    test('undoes clear, sort, remove and add, newest first, with labels', () {
      final lib = makeLibrary();
      final original = List.of(lib.queue);
      expect(lib.canUndoQueue, isFalse);
      lib.sortQueue(QueueSort.title);
      lib.removeFromQueue('$feed|c');
      lib.clearQueue();
      expect(lib.queue, isEmpty);
      expect(lib.queueUndoLabel, 'Clear Up Next');
      expect(lib.undoQueue(), 'Clear Up Next');
      expect(lib.queueUndoLabel, 'Remove from Up Next');
      lib.undoQueue();
      lib.undoQueue();
      expect(lib.queue, original);
      expect(lib.canUndoQueue, isFalse);
      expect(lib.undoQueue(), isNull);
    });

    test('changes the player makes by itself are not undoable', () {
      final lib = makeLibrary();
      lib.removeFromQueue('$feed|a', undoable: false);
      expect(lib.canUndoQueue, isFalse);
    });

    test('remove played takes only played episodes, and can be undone', () {
      final lib = makeLibrary();
      lib.markAllPlayed(['$feed|b', 'http://b.test/f|d'], true);
      expect(lib.removePlayedFromQueue(), 2);
      expect(guids(lib), ['a', 'c', 'e']);
      lib.undoQueue();
      expect(lib.queue, hasLength(5));
    });
  });

  group('queue timing', () {
    test('remaining time and start offsets follow progress and speed', () {
      final lib = makeLibrary();
      lib.queue = ['$feed|b', '$feed|a']; // 10 min then 30 min
      lib.setProgress('$feed|b', 4 * 60000, 10 * 60000); // 6 min left
      expect(
        lib.remainingOf(lib.episodes['$feed|b']!),
        const Duration(minutes: 6),
      );
      expect(lib.queueRemaining, const Duration(minutes: 36));
      expect(lib.queueStartOffsets, [
        Duration.zero,
        const Duration(minutes: 6),
      ]);

      lib.setPrefs(speed: 2.0); // twice as fast: half the wall-clock time
      expect(lib.queueRemaining, const Duration(minutes: 18));
      expect(lib.queueStartOffsets.last, const Duration(minutes: 3));
    });
  });

  group('ratings', () {
    test('set, clear, and newest rating wins when syncing', () {
      final lib = Library();
      lib.setRatings(['x'], 4);
      expect(lib.ratingOf('x'), 4);
      lib.setRatings(['x'], 0);
      expect(lib.ratingOf('x'), 0);

      final other = Library();
      other.applyRemote([
        {
          'type': 'rate',
          'key': 'x',
          'updated_at': 100,
          'deleted': false,
          'data': {'stars': 5},
        },
      ]);
      expect(other.ratingOf('x'), 5);
      other.applyRemote([
        {
          'type': 'rate',
          'key': 'x',
          'updated_at': 50,
          'deleted': false,
          'data': {'stars': 1},
        },
      ]);
      expect(other.ratingOf('x'), 5); // older write ignored
      other.applyRemote([
        {
          'type': 'rate',
          'key': 'x',
          'updated_at': 200,
          'deleted': true,
          'data': {},
        },
      ]);
      expect(other.ratingOf('x'), 0); // clearing a rating syncs too
    });

    test('ratings survive a backup restore', () {
      final a = Library()..ratings['x'] = Rate(3, 10);
      final b = Library()..restoreBackup(a.exportBackup());
      expect(b.ratingOf('x'), 3);
    });
  });
}
