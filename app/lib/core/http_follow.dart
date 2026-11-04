import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Sends a GET and follows redirects itself, up to [maxHops].
///
/// Podcast links often pass through several tracking and ad services before they reach the file
/// (Podtrac, Chartable, Megaphone, ...), and Dart's own client gives up after five hops. Some of
/// those services also hand out a cookie and redirect in a loop until it comes back, so cookies are
/// kept for the hosts involved. Headers such as Range are sent on every hop.
Future<http.StreamedResponse> sendFollowingRedirects(
  http.Client client,
  Uri url, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 30),
  int maxHops = 30,
}) async {
  final cookies = <String, Map<String, String>>{}; // host -> name -> value
  for (var hop = 0; hop <= maxHops; hop++) {
    final req = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll(headers);
    final jar = cookies[url.host];
    if (jar != null && jar.isNotEmpty) {
      req.headers['Cookie'] = jar.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    final resp = await client.send(req).timeout(timeout);

    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      // Several cookies arrive joined with commas; Expires dates have commas too, so only split before "name=".
      for (final c in setCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
        final pair = c.split(';').first.trim();
        final eq = pair.indexOf('=');
        if (eq > 0) {
          (cookies[url.host] ??= {})[pair.substring(0, eq)] = pair.substring(
            eq + 1,
          );
        }
      }
    }

    final location = resp.headers['location'];
    final redirect =
        const {301, 302, 303, 307, 308}.contains(resp.statusCode) &&
        location != null &&
        location.isNotEmpty;
    if (!redirect) return resp;
    await resp.stream
        .listen((_) {})
        .cancel(); // not interested in the redirect's body
    url = url.resolve(location);
  }
  throw HttpException('Too many redirects (more than $maxHops)', uri: url);
}
