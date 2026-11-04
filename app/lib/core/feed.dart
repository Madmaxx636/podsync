import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'models.dart';

class ParsedFeed {
  final Podcast podcast;
  final List<Episode> episodes;
  ParsedFeed(this.podcast, this.episodes);
}

Future<ParsedFeed> fetchFeed(
  String feedUrl, {
  http.Client? client,
  String? username,
  String? password,
  Duration timeout = const Duration(seconds: 30),
  String userAgent = 'PodSync/0.1',
}) async {
  final c = client ?? http.Client();
  final res = await c
      .get(
        Uri.parse(feedUrl),
        headers: {
          'User-Agent': userAgent,
          'Accept': 'application/rss+xml, application/xml, text/xml, */*',
          if (username != null && username.isNotEmpty)
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$username:${password ?? ''}'))}',
        },
      )
      .timeout(timeout);
  if (res.statusCode != 200) {
    throw Exception('Feed returned HTTP ${res.statusCode}');
  }
  return parseFeed(feedUrl, utf8.decode(res.bodyBytes, allowMalformed: true));
}

ParsedFeed parseFeed(String feedUrl, String body) {
  final doc = XmlDocument.parse(body);
  final channel = doc.findAllElements('channel').firstOrNull;
  if (channel == null) throw const FormatException('Not an RSS feed');

  String text(XmlElement e, String name) =>
      e.childElements
          .where((x) => x.name.qualified == name)
          .firstOrNull
          ?.innerText
          .trim() ??
      '';
  String attr(XmlElement e, String name, String a) =>
      e.childElements
          .where((x) => x.name.qualified == name)
          .firstOrNull
          ?.getAttribute(a) ??
      '';

  var image = attr(channel, 'itunes:image', 'href');
  if (image.isEmpty) {
    final img = channel.childElements
        .where((x) => x.name.local == 'image')
        .firstOrNull;
    image = img == null ? '' : text(img, 'url');
  }

  final podcast = Podcast(
    feedUrl: feedUrl,
    title: text(channel, 'title'),
    author: text(channel, 'itunes:author'),
    description: stripHtml(text(channel, 'description')),
    imageUrl: image,
    link: text(channel, 'link'),
    language: text(channel, 'language'),
  );

  final episodes = <Episode>[];
  for (final item in channel.findElements('item')) {
    final enclosure = item.childElements
        .where((x) => x.name.local == 'enclosure')
        .firstOrNull;
    final url = enclosure?.getAttribute('url') ?? '';
    if (url.isEmpty) continue;
    final title = text(item, 'title');
    var guid = text(item, 'guid');
    if (guid.isEmpty) guid = url;
    final epImage = attr(item, 'itunes:image', 'href');
    final desc = text(item, 'content:encoded').isNotEmpty
        ? text(item, 'content:encoded')
        : (text(item, 'description').isNotEmpty
              ? text(item, 'description')
              : text(item, 'itunes:summary'));
    episodes.add(
      Episode(
        feedUrl: feedUrl,
        guid: guid,
        title: title,
        audioUrl: url,
        description: stripHtml(desc),
        published: parseRfc822(text(item, 'pubDate')),
        durationMs: parseDuration(text(item, 'itunes:duration')),
        imageUrl: epImage.isNotEmpty ? epImage : image,
        link: text(item, 'link'),
        fileSize: int.tryParse(enclosure?.getAttribute('length') ?? '') ?? 0,
        mimeType: enclosure?.getAttribute('type') ?? '',
      ),
    );
  }
  return ParsedFeed(podcast, episodes);
}

/// itunes:duration is "SS", "MM:SS" or "HH:MM:SS".
int parseDuration(String s) {
  if (s.isEmpty) return 0;
  final parts = s.split(':').map((p) => double.tryParse(p.trim())).toList();
  if (parts.any((p) => p == null)) return 0;
  var seconds = 0.0;
  for (final p in parts) {
    seconds = seconds * 60 + p!;
  }
  return (seconds * 1000).round();
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// Tolerant RFC 822 parser ("Tue, 3 Jun 2008 11:05:30 +0200"); returns 0 on failure.
int parseRfc822(String s) {
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([+-]\d{4}|[A-Za-z]+)?',
  ).firstMatch(s);
  if (m == null) {
    return DateTime.tryParse(s)?.millisecondsSinceEpoch ?? 0;
  }
  final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
  if (month == 0) return 0;
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  var t = DateTime.utc(
    year,
    month,
    int.parse(m.group(1)!),
    int.tryParse(m.group(4) ?? '') ?? 0,
    int.tryParse(m.group(5) ?? '') ?? 0,
    int.tryParse(m.group(6) ?? '') ?? 0,
  );
  final tz = m.group(7);
  if (tz != null && RegExp(r'^[+-]\d{4}$').hasMatch(tz)) {
    final sign = tz[0] == '-' ? -1 : 1;
    final offset = Duration(
      hours: int.parse(tz.substring(1, 3)),
      minutes: int.parse(tz.substring(3, 5)),
    );
    t = sign > 0 ? t.subtract(offset) : t.add(offset);
  }
  return t.millisecondsSinceEpoch;
}

String stripHtml(String html) {
  var s = html
      .replaceAll(
        RegExp(r'<\s*(br|/p|/li|/div)\s*/?>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', '’');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// iTunes directory search (public, no key needed).
Future<List<SearchResult>> searchDirectory(
  String term, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.get(
    Uri.https('itunes.apple.com', '/search', {
      'media': 'podcast',
      'entity': 'podcast',
      'limit': '30',
      'term': term,
    }),
  );
  if (res.statusCode != 200) {
    throw Exception('Search failed (HTTP ${res.statusCode})');
  }
  final results = (jsonDecode(res.body)['results'] as List);
  return [
    for (final r in results)
      if (r['feedUrl'] != null)
        SearchResult(
          r['feedUrl'],
          r['collectionName'] ?? '',
          r['artistName'] ?? '',
          r['artworkUrl600'] ?? r['artworkUrl100'] ?? '',
        ),
  ];
}
