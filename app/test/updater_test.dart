import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/updater.dart';

void main() {
  test('versions compare by number, not text', () {
    expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
    expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('0.2.0', '0.2.0'), isFalse);
    expect(isNewerVersion('0.1.9', '0.2.0'), isFalse);
    expect(isNewerVersion('1.0', '0.9.9+4'), isTrue);
  });

  group('update checks', () {
    final apk = utf8.encode('pretend apk bytes');
    final good = sha256.convert(apk).toString();

    MockClient releases({String sum = ''}) => MockClient((r) async {
      switch (r.url.path) {
        case '/repos/Madmaxx636/podsync-releases/releases':
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'v0.3.0',
                'body': 'Faster everything',
                'html_url': 'https://example.test/release',
                'assets': [
                  {
                    'name': 'PodSync-android.apk',
                    'browser_download_url':
                        'https://dl.test/PodSync-android.apk',
                  },
                  {
                    'name': 'SHA256SUMS.txt',
                    'browser_download_url': 'https://dl.test/SHA256SUMS.txt',
                  },
                ],
              },
            ]),
            200,
          );
        case '/PodSync-android.apk':
          return http.Response.bytes(apk, 200);
        case '/SHA256SUMS.txt':
          return http.Response(
            '${sum.isEmpty ? good : sum}  PodSync-android.apk\n',
            200,
          );
      }
      return http.Response('', 404);
    });

    Future<(UpdateController, List<String>)> make(
      MockClient c, {
      String current = '0.2.0',
    }) async {
      final lib = Library();
      final ran = <String>[];
      final up = UpdateController(
        lib,
        client: c,
        currentVersion: current,
        assetName: 'PodSync-android.apk',
        install$: (path) async => ran.add(path),
        prepare: () async => null,
        tempDir: Directory.systemTemp.createTempSync('upd'),
      );
      return (up, ran);
    }

    test('finds a newer release and its installer', () async {
      final (up, _) = await make(releases());
      await up.check();
      expect(up.available?.version, '0.3.0');
      expect(up.available?.notes, 'Faster everything');
      expect(up.available?.assetUrl?.path, '/PodSync-android.apk');
      expect(up.takeOffer(), isTrue);
      expect(up.takeOffer(), isFalse, reason: 'only offered once per run');
    });

    test('says nothing when up to date, and tells a manual check', () async {
      final (up, _) = await make(releases(), current: '0.3.0');
      await up.check();
      expect(up.available, isNull);
      expect(up.message, isNull);
      await up.check(manual: true);
      expect(up.message, contains('latest'));
    });

    test('a failed quiet check is silent, a manual one explains', () async {
      final (up, _) = await make(
        MockClient((r) async => http.Response('', 500)),
      );
      await up.check();
      expect(up.error, isNull);
      await up.check(manual: true);
      expect(up.error, contains('Could not check'));
    });

    test('a skipped version is not offered again', () async {
      final (up, _) = await make(releases());
      await up.check();
      up.skipThisVersion();
      expect(up.takeOffer(), isFalse);
    });

    test('installs only after the checksum matches', () async {
      final (up, ran) = await make(releases());
      await up.check();
      await up.install();
      expect(up.error, isNull);
      expect(ran, hasLength(1));
      expect(up.downloading, isFalse);
    });

    test('a download that does not match its checksum is never run', () async {
      final (up, ran) = await make(releases(sum: 'ab' * 32));
      await up.check();
      await up.install();
      expect(ran, isEmpty);
      expect(up.error, contains('checksum'));
    });

    test('a finished download is reused instead of fetched again', () async {
      var downloads = 0;
      final inner = releases();
      final counting = MockClient((r) async {
        if (r.url.path == '/PodSync-android.apk') downloads++;
        return inner.get(r.url).then((x) => x);
      });
      final dir = Directory.systemTemp.createTempSync('upd');
      final lib = Library();
      final ran = <String>[];
      UpdateController build() => UpdateController(
        lib,
        client: counting,
        currentVersion: '0.2.0',
        assetName: 'PodSync-android.apk',
        install$: (path) async => ran.add(path),
        prepare: () async => null,
        tempDir: dir,
      );
      final one = build();
      await one.check();
      await one.install();
      final two = build();
      await two.check();
      await two.install();
      expect(ran, hasLength(2));
      expect(downloads, 1);
    });
  });

  test('a newer release without this platform\'s installer does not hide an older one that has it', () async {
    final client = MockClient((r) async {
      return http.Response(
        jsonEncode([
          {
            'tag_name': 'v0.5.0',
            'assets': [
              {
                'name': 'PodSync-android.apk',
                'browser_download_url': 'https://dl.test/a.apk',
              },
            ],
          },
          {
            'tag_name': 'v0.4.0',
            'assets': [
              {
                'name': 'PodSync-Setup-x64.exe',
                'browser_download_url': 'https://dl.test/s.exe',
              },
            ],
          },
        ]),
        200,
      );
    });
    final up = UpdateController(
      Library(),
      client: client,
      currentVersion: '0.3.0',
      assetName: 'PodSync-Setup-x64.exe',
      tempDir: Directory.systemTemp.createTempSync('upd'),
    );
    await up.check();
    expect(up.available?.version, '0.4.0');
    expect(up.available?.assetUrl?.path, '/s.exe');
  });
}
