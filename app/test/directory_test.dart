import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/directory.dart';

/// A tiny stand-in for Apple's directory.
class FakeStore {
  final urls = <Uri>[];
  int status = 200;

  Map<String, dynamic> chartEntry(int id, String name, String artist) => {
    'im:name': {'label': name},
    'im:artist': {'label': artist},
    'summary': {'label': 'About $name'},
    'category': {
      'attributes': {'label': 'News'},
    },
    'im:image': [
      {'label': 'https://img.test/a/55x55bb.png'},
      {'label': 'https://img.test/a/170x170bb.png'},
    ],
    'id': {
      'attributes': {'im:id': '$id'},
    },
  };

  Map<String, dynamic> result(int id, String name, {String? feed}) => {
    'collectionId': id,
    'collectionName': name,
    'artistName': 'Author $id',
    'feedUrl': feed ?? 'https://feeds.test/$id.xml',
    'artworkUrl600': 'https://img.test/$id/600x600bb.jpg',
    'primaryGenreName': 'News',
  };

  http.Client client() => MockClient((req) async {
    urls.add(req.url);
    if (status != 200) return http.Response('', status);
    final p = req.url.path;
    if (p.contains('/rss/toppodcasts')) {
      return http.Response(
        jsonEncode({
          'feed': {
            'entry': [
              chartEntry(3, 'Third', 'C'),
              chartEntry(1, 'First', 'A'),
              chartEntry(2, 'Second', 'B'),
            ],
          },
        }),
        200,
      );
    }
    if (p == '/lookup') {
      final ids = req.url.queryParameters['id']!
          .split(',')
          .map(int.parse)
          .toList();
      return http.Response(
        jsonEncode({
          'results': [
            for (final id in ids)
              if (id != 2) result(id, 'Name $id'),
          ],
        }),
        200,
      ); // 2 has no feed
    }
    if (p == '/search') {
      return http.Response(
        '  ${jsonEncode({
          'results': [result(10, 'Hit'), result(11, 'No feed', feed: '')],
        })}',
        200,
      );
    }
    return http.Response('', 404);
  });
}

void main() {
  late FakeStore fake;
  late StoreDirectory dir;
  setUp(() {
    fake = FakeStore();
    dir = StoreDirectory(client: fake.client());
  });

  group('top charts', () {
    test('keep chart order, resolve feed addresses, and drop podcasts that have none', () async {
      final top = await dir.top();
      expect(top.map((p) => p.id), [3, 1]); // 2 had no feed address
      expect(top.first.feedUrl, 'https://feeds.test/3.xml');
      expect(top.first.title, 'Name 3');
      expect(top.first.imageUrl, contains('600x600'));
      expect(top.first.genre, 'News');
    });

    test('asks for the right country and category, in one lookup', () async {
      dir.country = 'gb';
      await dir.top(genreId: 1303, limit: 10);
      expect(
        fake.urls.first.toString(),
        'https://itunes.apple.com/gb/rss/toppodcasts/limit=10/genre=1303/json',
      );
      expect(fake.urls.where((u) => u.path == '/lookup'), hasLength(1));
      expect(fake.urls.last.queryParameters['id'], '3,1,2');
    });

    test('results are cached, per country and category', () async {
      await dir.top();
      final before = fake.urls.length;
      await dir.top();
      expect(fake.urls.length, before);
      await dir.top(genreId: 1303);
      expect(fake.urls.length, greaterThan(before));
      dir.country = 'de';
      final again = fake.urls.length;
      await dir.top();
      expect(fake.urls.length, greaterThan(again));
    });

    test('bigger() swaps the cover size', () {
      expect(
        StoreDirectory.bigger('https://x/a/170x170bb.png'),
        'https://x/a/600x600bb.png',
      );
      expect(StoreDirectory.bigger('https://x/a/b.jpg'), 'https://x/a/b.jpg');
    });
  });

  group('search', () {
    test('returns podcasts with feeds, in the order the store gave', () async {
      final r = await dir.search('  news ');
      expect(r.map((p) => p.title), [
        'Hit',
      ]); // the one without a feed is dropped
      expect(fake.urls.single.queryParameters['term'], 'news');
      expect(fake.urls.single.queryParameters['media'], 'podcast');
    });

    test('a category narrows it, and an empty term asks nothing', () async {
      await dir.search('history', genreId: 1487);
      expect(fake.urls.single.queryParameters['genreId'], '1487');
      fake.urls.clear();
      expect(await dir.search('   '), isEmpty);
      expect(fake.urls, isEmpty);
    });
  });

  test('a store error says so plainly', () async {
    fake.status = 503;
    await expectLater(
      dir.top(),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('503'),
        ),
      ),
    );
    await expectLater(dir.search('x'), throwsA(isA<HttpException>()));
  });

  test('every category has a unique id', () {
    expect({for (final g in storeGenres) g.id}.length, storeGenres.length);
    expect(
      storeGenres.map((g) => g.name),
      containsAll(['Comedy', 'News', 'Technology', 'True Crime']),
    );
  });
}
