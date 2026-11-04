import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/feed.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';

const rss = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>Test Cast</title>
  <itunes:author>Someone</itunes:author>
  <itunes:image href="http://x/art.jpg"/>
  <item>
    <title>Ep 1</title>
    <guid>g1</guid>
    <pubDate>Tue, 3 Jun 2008 11:05:30 +0200</pubDate>
    <itunes:duration>01:02:03</itunes:duration>
    <enclosure url="http://x/1.mp3" type="audio/mpeg"/>
    <description>&lt;p&gt;Hello &amp;amp; bye&lt;/p&gt;</description>
  </item>
  <item><title>No audio</title></item>
</channel></rss>''';

void main() {
  test('parses feed metadata and episodes, skipping items without audio', () {
    final f = parseFeed('http://x/feed', rss);
    expect(f.podcast.title, 'Test Cast');
    expect(f.podcast.imageUrl, 'http://x/art.jpg');
    expect(f.episodes, hasLength(1));
    final e = f.episodes.single;
    expect(e.id, 'http://x/feed|g1');
    expect(e.durationMs, (3600 + 120 + 3) * 1000);
    expect(e.description, 'Hello & bye');
    expect(DateTime.fromMillisecondsSinceEpoch(e.published, isUtc: true), DateTime.utc(2008, 6, 3, 9, 5, 30));
  });

  test('duration formats', () {
    expect(parseDuration('90'), 90000);
    expect(parseDuration('1:30'), 90000);
    expect(parseDuration('bogus'), 0);
  });

  group('sync merge', () {
    Map<String, dynamic> rec(String type, String key, int at, Map data, {bool deleted = false}) =>
        {'type': type, 'key': key, 'updated_at': at, 'deleted': deleted, 'data': data};

    test('newer remote progress wins, older is ignored', () {
      final lib = Library();
      lib.progress['a'] = Progress(positionMs: 500, updatedAt: 100);
      lib.applyRemote([rec('progress', 'a', 50, {'pos': 1})]);
      expect(lib.progress['a']!.positionMs, 500);
      lib.applyRemote([rec('progress', 'a', 200, {'pos': 9000, 'dur': 10000, 'played': false})]);
      expect(lib.progress['a']!.positionMs, 9000);
    });

    test('new subscription is reported for feed fetch; tombstone unsubscribes', () {
      final lib = Library();
      final fresh = lib.applyRemote([rec('sub', 'http://f', 10, {'title': 'F'})]);
      expect(fresh, ['http://f']);
      expect(lib.isSubscribed('http://f'), isTrue);
      lib.applyRemote([rec('sub', 'http://f', 20, {}, deleted: true)]);
      expect(lib.isSubscribed('http://f'), isFalse);
    });

    test('queue replaced only by a newer queue', () {
      final lib = Library()..queue = ['x']..queueUpdatedAt = 100;
      lib.applyRemote([rec('queue', 'main', 90, {'items': ['y']})]);
      expect(lib.queue, ['x']);
      lib.applyRemote([rec('queue', 'main', 110, {'items': ['y', 'z']})]);
      expect(lib.queue, ['y', 'z']);
    });
  });

  test('queue reorder', () {
    final lib = Library()..queue = ['a', 'b', 'c'];
    lib.reorderQueue(0, 3); // drag first item to the end
    expect(lib.queue, ['b', 'c', 'a']);
  });
}
