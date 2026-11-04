import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A podcast as the store lists it.
class StorePodcast {
  const StorePodcast({
    required this.id,
    required this.feedUrl,
    required this.title,
    required this.author,
    required this.imageUrl,
    this.genre = '',
    this.summary = '',
  });

  final int id;
  final String feedUrl;
  final String title;
  final String author;
  final String imageUrl;
  final String genre;
  final String summary;
}

class StoreGenre {
  const StoreGenre(this.id, this.name);
  final int id;
  final String name;
}

/// The categories of Apple's podcast directory.
const storeGenres = [
  StoreGenre(1301, 'Arts'),
  StoreGenre(1321, 'Business'),
  StoreGenre(1303, 'Comedy'),
  StoreGenre(1304, 'Education'),
  StoreGenre(1483, 'Fiction'),
  StoreGenre(1511, 'Government'),
  StoreGenre(1512, 'Health & Fitness'),
  StoreGenre(1487, 'History'),
  StoreGenre(1305, 'Kids & Family'),
  StoreGenre(1502, 'Leisure'),
  StoreGenre(1310, 'Music'),
  StoreGenre(1489, 'News'),
  StoreGenre(1314, 'Religion & Spirituality'),
  StoreGenre(1533, 'Science'),
  StoreGenre(1324, 'Society & Culture'),
  StoreGenre(1545, 'Sports'),
  StoreGenre(1318, 'Technology'),
  StoreGenre(1488, 'True Crime'),
  StoreGenre(1309, 'TV & Film'),
];

/// Apple's public podcast directory: search, top charts and categories. Results are kept for a
/// while so browsing back and forth does not hit the network each time.
class StoreDirectory {
  StoreDirectory({
    http.Client? client,
    this.country = 'us',
    this.userAgent = 'PodSync/0.1',
  }) : _http = client ?? http.Client();

  /// Two-letter store country, e.g. "us", "gb", "de". Changes which charts you see.
  String country;
  String userAgent;
  final http.Client _http;
  final Map<String, ({DateTime at, List<StorePodcast> items})> _cache = {};
  static const _ttl = Duration(minutes: 15);

  List<StorePodcast>? _fresh(String key) {
    final c = _cache[key];
    return c != null && DateTime.now().difference(c.at) < _ttl ? c.items : null;
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final res = await _http
        .get(url, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpException('The podcast store answered HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Unexpected answer from the podcast store');
    }
    return body;
  }

  /// A bigger cover than the 100-pixel one the charts hand out.
  static String bigger(String url) => url.replaceFirstMapped(
    RegExp(r'/\d+x\d+(bb)?\.(jpg|png)$'),
    (m) => '/600x600bb.${m[2]}',
  );

  StorePodcast? _fromSearch(Map<String, dynamic> r) {
    final feed = r['feedUrl'];
    if (feed is! String || feed.isEmpty) return null;
    return StorePodcast(
      id: (r['collectionId'] as num?)?.toInt() ?? 0,
      feedUrl: feed,
      title: (r['collectionName'] ?? r['trackName'] ?? '') as String,
      author: (r['artistName'] ?? '') as String,
      imageUrl: (r['artworkUrl600'] ?? r['artworkUrl100'] ?? '') as String,
      genre: (r['primaryGenreName'] ?? '') as String,
    );
  }

  /// Podcasts matching [term], most relevant first. Optionally limited to one category.
  Future<List<StorePodcast>> search(
    String term, {
    int limit = 40,
    int? genreId,
  }) async {
    final q = term.trim();
    if (q.isEmpty) return const [];
    final key = 'search|$country|$genreId|$limit|${q.toLowerCase()}';
    final cached = _fresh(key);
    if (cached != null) return cached;
    final json = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'media': 'podcast',
        'entity': 'podcast',
        'limit': '$limit',
        'country': country,
        'term': q,
        if (genreId != null) 'genreId': '$genreId',
      }),
    );
    final items = [
      for (final r in (json['results'] as List? ?? []))
        ?_fromSearch(Map<String, dynamic>.from(r)),
    ];
    _cache[key] = (at: DateTime.now(), items: items);
    return items;
  }

  /// The top podcasts, overall or in one category, in chart order.
  Future<List<StorePodcast>> top({int? genreId, int limit = 30}) async {
    final key = 'top|$country|$genreId|$limit';
    final cached = _fresh(key);
    if (cached != null) return cached;
    final json = await _getJson(
      Uri.parse(
        'https://itunes.apple.com/$country/rss/toppodcasts/limit=$limit${genreId == null ? '' : '/genre=$genreId'}/json',
      ),
    );
    var entries = (json['feed'] as Map?)?['entry'];
    if (entries is Map) {
      entries = [entries]; // a one-entry chart is not wrapped in a list
    }
    final ranked = <int, Map<String, dynamic>>{};
    for (final e in (entries as List? ?? [])) {
      final m = Map<String, dynamic>.from(e);
      final id = int.tryParse(
        ((m['id'] as Map?)?['attributes'] as Map?)?['im:id']?.toString() ?? '',
      );
      if (id != null) ranked[id] = m;
    }
    // Charts carry names and covers but not feed addresses; one lookup resolves them all.
    final feeds = await _lookup(ranked.keys.toList());
    final items = <StorePodcast>[];
    for (final entry in ranked.entries) {
      final found = feeds[entry.key];
      if (found == null) {
        continue; // no feed address, so it cannot be subscribed to
      }
      final images = (entry.value['im:image'] as List?) ?? const [];
      final chartImage = images.isEmpty
          ? ''
          : ((images.last as Map)['label'] ?? '') as String;
      items.add(
        StorePodcast(
          id: entry.key,
          feedUrl: found.feedUrl,
          title: found.title.isNotEmpty
              ? found.title
              : (((entry.value['im:name'] as Map?)?['label']) ?? '') as String,
          author: found.author.isNotEmpty
              ? found.author
              : (((entry.value['im:artist'] as Map?)?['label']) ?? '')
                    as String,
          imageUrl: found.imageUrl.isNotEmpty
              ? found.imageUrl
              : bigger(chartImage),
          genre: found.genre.isNotEmpty
              ? found.genre
              : ((((entry.value['category'] as Map?)?['attributes'])
                            as Map?)?['label'] ??
                        '')
                    as String,
          summary:
              (((entry.value['summary'] as Map?)?['label']) ?? '') as String,
        ),
      );
    }
    _cache[key] = (at: DateTime.now(), items: items);
    return items;
  }

  Future<Map<int, StorePodcast>> _lookup(List<int> ids) async {
    final out = <int, StorePodcast>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final json = await _getJson(
        Uri.https('itunes.apple.com', '/lookup', {
          'id': chunk.join(','),
          'entity': 'podcast',
          'country': country,
        }),
      );
      for (final r in (json['results'] as List? ?? [])) {
        final p = _fromSearch(Map<String, dynamic>.from(r));
        if (p != null) out[p.id] = p;
      }
    }
    return out;
  }

  void clearCache() => _cache.clear();
}
