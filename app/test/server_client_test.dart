import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';

void main() {
  http.Client server(
    Map<String, (int, String)> routes,
    List<http.Request> seen,
  ) => MockClient((req) async {
    seen.add(req);
    final r = routes['${req.method} ${req.url.path}'];
    return r == null ? http.Response('', 404) : http.Response(r.$2, r.$1);
  });

  test('the server\'s own sentence is shown, not raw JSON', () async {
    final lib = Library(
      client: server({
        'POST /api/login': (401, '{"error":"invalid credentials"}'),
      }, []),
    );
    await expectLater(
      lib.signIn('http://s', 'lane', 'wrong password'),
      throwsA(
        predicate((e) => e.toString() == 'Exception: invalid credentials'),
      ),
    );
    expect(lib.signedIn, isFalse);
  });

  test('registration problems read as sentences', () async {
    final lib = Library(
      client: server({
        'POST /api/register': (
          403,
          '{"error":"registration is turned off on this server; ask its owner to add you"}',
        ),
      }, []),
    );
    await expectLater(
      lib.signIn('http://s', 'lane', 'correct horse', register: true),
      throwsA(predicate((e) => e.toString().contains('turned off'))),
    );
  });

  test('a non-JSON or empty answer still gives a useful message', () async {
    var lib = Library(client: server({'POST /api/login': (502, '')}, []));
    await expectLater(
      lib.signIn('http://s', 'a', 'b'),
      throwsA(predicate((e) => e.toString().contains('HTTP 502'))),
    );
    lib = Library(
      client: server({'POST /api/login': (500, 'Bad gateway')}, []),
    );
    await expectLater(
      lib.signIn('http://s', 'a', 'b'),
      throwsA(predicate((e) => e.toString().contains('Bad gateway'))),
    );
  });

  test('signing in stores the session; signing out tells the server and then forgets it', () async {
    final seen = <http.Request>[];
    final lib = Library(
      client: server({
        'POST /api/login': (200, '{"token":"abc123"}'),
        'POST /api/sync': (200, jsonEncode({'seq': 0, 'changes': []})),
        'POST /api/logout': (204, ''),
      }, seen),
    );
    await lib.signIn('http://s/', 'lane', 'correct horse');
    expect(lib.signedIn, isTrue);
    expect(lib.token, 'abc123');
    lib.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(lib.signedIn, isFalse);
    final logout = seen.where((r) => r.url.path == '/api/logout').single;
    expect(logout.headers['Authorization'], 'Bearer abc123');
  });

  test('signing out still works when the server cannot be reached', () async {
    final lib = Library(
      client: MockClient(
        (r) async => r.url.path == '/api/login'
            ? http.Response('{"token":"t"}', 200)
            : throw http.ClientException('offline'),
      ),
    );
    await lib.signIn('http://s', 'lane', 'correct horse');
    lib.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(lib.signedIn, isFalse);
  });

  test('a signed-out server session ends sync with a clear message', () async {
    final lib = Library(
      client: server({
        'POST /api/login': (200, '{"token":"t"}'),
        'POST /api/sync': (401, '{"error":"not signed in"}'),
      }, []),
    );
    await lib.signIn('http://s', 'lane', 'correct horse');
    await lib.sync();
    expect(lib.signedIn, isFalse);
    expect(lib.syncError, contains('sign in again'));
  });

  test('after a server restore, the device uploads everything the old backup lacked', () async {
    final bodies = <Map<String, dynamic>>[];
    var restored = false;
    final lib = Library(
      client: MockClient((req) async {
        if (req.url.path == '/api/login') {
          return http.Response('{"token":"t"}', 200);
        }
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(sent);
        // First sync: the server is far behind what this device remembers (seq 0, no data).
        // Later syncs: normal.
        final seq = restored ? 3 : 0;
        return http.Response(jsonEncode({'seq': seq, 'changes': []}), 200);
      }),
    );
    lib.podcasts['https://x/feed'] = Podcast(
      feedUrl: 'https://x/feed',
      title: 'X',
      updatedAt: 5,
    );
    await lib.signIn(
      'http://s',
      'lane',
      'correct horse',
    ); // device already held a podcast
    expect(bodies.last['since'], 0);

    // The device syncs on happily, with the server at seq 3...
    restored = true;
    lib.setFavorite('https://x/feed|e', true);
    await lib.sync();
    // ...then the server comes back from an older backup, at seq 0.
    restored = false;
    bodies.clear();
    await lib.sync();
    await Future<void>.delayed(
      const Duration(milliseconds: 50),
    ); // the follow-up sync
    final resent = [for (final b in bodies) ...(b['changes'] as List)]
        .map((c) => '${c['type']}|${c['key']}')
        .toSet();
    expect(resent, containsAll({'sub|https://x/feed', 'fav|https://x/feed|e'}));
  });
}
