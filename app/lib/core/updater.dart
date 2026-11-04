import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'errors.dart';
import 'library.dart';

/// Where releases are published. A separate public repository, so the apps need no login.
const releasesRepo = 'Madmaxx636/podsync-releases';

/// A newer release the app could install.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.assetUrl,
    this.sumsUrl,
  });
  final String version;
  final String notes;
  final String pageUrl;
  final Uri? assetUrl; // the installer, APK or archive for this platform
  final Uri? sumsUrl;
}

/// True when [a] is a newer version than [b] ("v0.2.0" and "0.2.0" both work).
bool isNewerVersion(String a, String b) {
  List<int> parts(String v) {
    final core = v
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split(RegExp(r'[+-]'))
        .first;
    return core.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// The asset name that installs PodSync on this platform, or null if there is none.
String? updateAssetName() {
  if (Platform.isWindows) return 'PodSync-Setup-x64.exe';
  if (Platform.isAndroid) return 'PodSync-android.apk';
  if (Platform.isLinux) return 'PodSync-linux-x64.tar.gz';
  return null;
}

/// Looks for new releases, downloads the installer, checks it and starts it.
class UpdateController extends ChangeNotifier {
  UpdateController(
    this.lib, {
    http.Client? client,
    String? currentVersion,
    this.assetName,
    this.install$ = _platformInstall,
    this.prepare = _platformPrepare,
    this.tempDir,
  }) : _client = client ?? http.Client(),
       current = currentVersion ?? '';

  final Library lib;
  final http.Client _client;
  final String? assetName;
  final Future<void> Function(String path) install$;

  /// Null when installing can go ahead, otherwise what the person has to do first.
  final Future<String?> Function() prepare;

  /// Where downloads go; defaults to the system temp folder.
  final Directory? tempDir;

  String current;
  UpdateInfo? available;
  bool checking = false;
  double? progress; // 0..1 while downloading
  String? error;
  String? message; // result of the last manual check, e.g. "You are up to date"
  bool _offered = false;

  bool get downloading => progress != null;
  bool get canInstall => (assetName ?? updateAssetName()) != null;

  Future<void> init() async {
    if (current.isEmpty) {
      try {
        current = (await PackageInfo.fromPlatform()).version;
      } catch (_) {
        current = '0.0.0';
      }
    }
    notifyListeners();
  }

  /// True once per run when there is an update the person has not skipped.
  bool takeOffer() {
    final a = available;
    if (a == null || _offered || lib.settings.updateSkipped == a.version) {
      return false;
    }
    return _offered = true;
  }

  void skipThisVersion() {
    final a = available;
    if (a == null) return;
    lib.setSetting('updateSkipped', a.version);
    notifyListeners();
  }

  /// Asks GitHub for the latest release. A quiet check stays silent unless there is news.
  Future<void> check({bool manual = false}) async {
    if (checking) return;
    checking = true;
    error = null;
    message = null;
    notifyListeners();
    try {
      final r = await _client
          .get(
            Uri.https('api.github.com', '/repos/$releasesRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw HttpException('GitHub answered ${r.statusCode}');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );
      if (tag.isNotEmpty && isNewerVersion(tag, current)) {
        Uri? asset, sums;
        final want = assetName ?? updateAssetName();
        for (final a in (j['assets'] as List? ?? const [])) {
          final name = a['name'] as String? ?? '';
          final url = Uri.tryParse(a['browser_download_url'] as String? ?? '');
          if (name == want) asset = url;
          if (name == 'SHA256SUMS.txt') sums = url;
        }
        available = UpdateInfo(
          version: tag,
          notes: (j['body'] as String? ?? '').trim(),
          pageUrl:
              j['html_url'] as String? ??
              'https://github.com/$releasesRepo/releases',
          assetUrl: asset,
          sumsUrl: sums,
        );
      } else {
        available = null;
        if (manual) message = 'PodSync $current is the latest version';
      }
    } catch (e) {
      if (manual) error = 'Could not check for updates: ${cleanError(e)}';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Downloads the installer, checks it against the published checksum, then runs it.
  Future<void> install() async {
    final a = available;
    if (a == null || a.assetUrl == null || progress != null) return;
    error = null;
    final blocked = await prepare();
    if (blocked != null) {
      error = blocked;
      notifyListeners();
      return;
    }
    progress = 0;
    notifyListeners();
    try {
      final dir = tempDir ?? await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'update-${a.version}-${p.basename(a.assetUrl!.path)}'),
      );
      final expected = await _expectedSum(a);
      // A finished, matching download from an earlier try is reused instead of fetched again.
      final reuse =
          file.existsSync() &&
          sha256.convert(await file.readAsBytes()).toString() == expected;
      if (!reuse) {
        final res = await _client.send(
          http.Request('GET', a.assetUrl!)..followRedirects = true,
        );
        if (res.statusCode != 200) {
          throw HttpException('download answered ${res.statusCode}');
        }
        final total = res.contentLength ?? 0;
        var got = 0;
        final sink = file.openWrite();
        final digest = AccumulatorSink<Digest>();
        final hasher = sha256.startChunkedConversion(digest);
        await for (final chunk in res.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress = got / total;
            notifyListeners();
          }
        }
        await sink.close();
        hasher.close();
        if (digest.events.single.toString() != expected) {
          await file.delete();
          throw const FormatException(
            'the download does not match its checksum',
          );
        }
      }
      progress = 1;
      notifyListeners();
      await install$(file.path);
    } on PlatformException catch (e) {
      error = e.message ?? 'Update failed';
    } catch (e) {
      error = 'Update failed: ${cleanError(e)}';
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  /// The checksum SHA256SUMS.txt publishes for this release's installer. The download must
  /// match it, so a damaged or swapped file is never run.
  Future<String> _expectedSum(UpdateInfo a) async {
    final sums = a.sumsUrl;
    if (sums == null) {
      throw const FormatException('the release has no checksum file');
    }
    final r = await _client.get(sums).timeout(const Duration(seconds: 20));
    final name = p.basename(a.assetUrl!.path);
    for (final line in const LineSplitter().convert(utf8.decode(r.bodyBytes))) {
      final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$')
          .firstMatch(line.trim());
      if (m != null && m.group(2) == name) return m.group(1)!.toLowerCase();
    }
    throw const FormatException(
      'the checksum file does not list this download',
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

const _channel = MethodChannel('dev.podsync/update');

/// Where the Linux build is installed: the folder holding the running program.
Directory get _linuxInstallDir => File(Platform.resolvedExecutable).parent;

Future<String?> _platformPrepare() async {
  if (Platform.isAndroid) {
    final ok = (await _channel.invokeMethod<bool>('prepare')) ?? false;
    return ok
        ? null
        : 'Allow PodSync to install updates in the settings page that just opened, then tap Install again.';
  }
  if (Platform.isLinux) {
    try {
      final probe = File(p.join(_linuxInstallDir.path, '.update-probe'));
      probe.writeAsStringSync('');
      probe.deleteSync();
    } catch (_) {
      return 'PodSync is installed in a folder you cannot write to. Download the new version from the releases page and install it over this one.';
    }
  }
  return null;
}

/// Windows: run the installer quietly (it closes and restarts the app). Android: hand the
/// APK to the system installer, which asks for one confirmation. Linux: unpack the new
/// version over the install folder and start it.
Future<void> _platformInstall(String path) async {
  if (Platform.isWindows) {
    await Process.start(path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/CLOSEAPPLICATIONS',
      '/RELAUNCH=1',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  } else if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('install', {'path': path});
  } else if (Platform.isLinux) {
    final dir = _linuxInstallDir.path;
    final r = await Process.run('tar', [
      '-xzf',
      path,
      '-C',
      dir,
      '--strip-components=1',
    ]);
    if (r.exitCode != 0) {
      throw ProcessException('tar', [], '${r.stderr}'.trim(), r.exitCode);
    }
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  } else {
    throw UnsupportedError('Updates install by hand on this system');
  }
}

/// Tiny helper so the hash can be read after the stream ends.
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T data) => events.add(data);
  @override
  void close() {}
}
