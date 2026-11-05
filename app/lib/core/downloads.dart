import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'errors.dart';
import 'http_follow.dart';
import 'library.dart';
import 'models.dart';

enum DownloadState { queued, downloading, done, failed }

class DownloadInfo {
  DownloadInfo(
    this.state, {
    this.path = '',
    this.bytes = 0,
    this.total = -1,
    this.error,
    this.at = 0,
  });

  DownloadState state;
  String path;
  int bytes; // received so far, or the file size once done
  int total; // -1 when the server does not say
  String? error;
  int at; // when it finished, ms since epoch

  double? get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : null;
}

/// Downloads episodes for offline listening, and applies the auto-download and auto-delete rules.
///
/// Downloads belong to this device only; nothing here syncs. Files are written as `.part` first
/// and resumed after an interruption when the server allows it.
class DownloadManager extends ChangeNotifier {
  DownloadManager(
    this.library, {
    http.Client? client,
    this._directory,
    this._indexFile,
    this._networkAllowed,
    this._watchNetwork = true,
  }) : _http = client ?? http.Client();

  final Library library;

  /// Called when an episode has finished downloading (desktop notifications use it).
  void Function(String id)? onFinished;
  final http.Client _http;
  final Directory? _directory;
  File? _indexFile;
  final Future<bool> Function()? _networkAllowed;
  final bool _watchNetwork;

  final Map<String, DownloadInfo> _items = {};
  final Map<String, Episode> _episodes = {}; // what is queued or running
  final List<String> _pending = [];
  final Set<String> _active = {};
  final Set<String> _cancelled = {};
  final Set<String> _declined =
      {}; // episodes the user removed by hand: do not auto-download again
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;
  Timer? _sweepTimer;
  StreamSubscription<Object?>? _netSub;
  bool _pumping = false;
  bool _disposed = false;
  String _signature = '';

  /// Set by the player: true while this episode is the one being listened to.
  bool Function(String id)? isInUse;

  // ---- reading state -------------------------------------------------------

  DownloadInfo? infoOf(String id) => _items[id];
  bool isDownloaded(String id) => _items[id]?.state == DownloadState.done;
  bool isBusy(String id) =>
      _items[id]?.state == DownloadState.queued ||
      _items[id]?.state == DownloadState.downloading;

  /// The local file, if this episode is downloaded and the file is still there.
  String? pathOf(String id) {
    final i = _items[id];
    if (i == null || i.state != DownloadState.done) return null;
    if (!File(i.path).existsSync()) {
      _items.remove(id);
      _saveSoon();
      return null;
    }
    return i.path;
  }

  List<String> get doneIds => [
    for (final e in _items.entries)
      if (e.value.state == DownloadState.done) e.key,
  ];
  List<String> get activeIds => [
    for (final e in _items.entries)
      if (e.value.state == DownloadState.downloading) e.key,
  ];
  List<String> get queuedIds => List.of(_pending);
  List<String> get failedIds => [
    for (final e in _items.entries)
      if (e.value.state == DownloadState.failed) e.key,
  ];
  int get doneCount => doneIds.length;

  /// True while anything is downloading or waiting its turn.
  bool get busy => _active.isNotEmpty || _pending.isNotEmpty;
  int get totalBytes => _items.values
      .where((i) => i.state == DownloadState.done)
      .fold(0, (a, i) => a + i.bytes);

  /// Everything the downloads screen lists: running first, then waiting, failed, finished (newest first).
  List<String> get allIds {
    final done =
        _items.entries
            .where((e) => e.value.state == DownloadState.done)
            .toList()
          ..sort((a, b) => b.value.at.compareTo(a.value.at));
    return [...activeIds, ..._pending, ...failedIds, ...done.map((e) => e.key)];
  }

  // ---- setup ----------------------------------------------------------------

  /// Loads what was downloaded before, starts watching the library for the auto rules, and
  /// starts the periodic clean-up. Call once after the library has loaded.
  Future<void> start() async {
    _indexFile ??= File(
      p.join((await getApplicationSupportDirectory()).path, 'downloads.json'),
    );
    await _load();
    library.onNewEpisodes = handleNewEpisodes;
    library.addListener(_onLibrary);
    _sweepTimer = Timer.periodic(const Duration(minutes: 10), (_) => sweep());
    if (_watchNetwork) {
      try {
        _netSub = Connectivity().onConnectivityChanged.listen((_) => _pump());
      } catch (e) {
        debugPrint('connectivity: $e');
      }
    }
    reconcile();
  }

  Future<void> _load() async {
    final f = _indexFile;
    if (f == null || !await f.exists()) return;
    try {
      for (final x in jsonDecode(await f.readAsString()) as List) {
        final path = x['path'] as String;
        if (await File(path).exists()) {
          _items[x['id']] = DownloadInfo(
            DownloadState.done,
            path: path,
            bytes: x['bytes'] ?? 0,
            total: x['bytes'] ?? 0,
            at: x['at'] ?? 0,
          );
        }
      }
    } catch (e) {
      debugPrint('Could not read downloads.json: $e');
    }
  }

  void _saveSoon() {
    if (_indexFile == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), saveNow);
  }

  Future<void> saveNow() async {
    final f = _indexFile;
    if (f == null) return;
    final data = jsonEncode([
      for (final e in _items.entries)
        if (e.value.state == DownloadState.done)
          {
            'id': e.key,
            'path': e.value.path,
            'bytes': e.value.bytes,
            'at': e.value.at,
          },
    ]);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data);
    await tmp.rename(f.path);
  }

  void _changed({bool force = true}) {
    if (_disposed) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastNotify) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  // ---- actions ---------------------------------------------------------------

  void download(Episode e, {bool auto = false}) {
    final existing = _items[e.id];
    if (existing != null && existing.state != DownloadState.failed) return;
    if (!auto) _declined.remove(e.id);
    _items[e.id] = DownloadInfo(DownloadState.queued);
    _episodes[e.id] = e;
    _pending.add(e.id);
    _changed();
    _pump();
  }

  void downloadAll(Iterable<Episode> eps) {
    for (final e in eps) {
      download(e);
    }
  }

  void retry(String id) {
    final e = _episodes[id] ?? library.episodes[id];
    if (e != null && _items[id]?.state == DownloadState.failed) download(e);
  }

  /// Stops a waiting or running download and throws away what was received.
  void cancel(String id) {
    final info = _items[id];
    if (info == null || info.state == DownloadState.done) return;
    _declined.add(id);
    if (_active.contains(id)) {
      _cancelled.add(id); // the running loop notices and cleans up
      return;
    }
    _pending.remove(id);
    _items.remove(id);
    _episodes.remove(id);
    _deletePart(id);
    _changed();
  }

  void cancelAll() {
    for (final id in [..._pending, ..._active]) {
      cancel(id);
    }
  }

  /// Removes the downloaded file (or a failed attempt).
  Future<void> delete(String id, {bool byUser = true}) async {
    final info = _items.remove(id);
    if (info == null) return;
    if (byUser) _declined.add(id);
    _episodes.remove(id);
    _changed(); // the screen should not wait for the file system
    if (info.path.isNotEmpty) {
      try {
        await File(info.path).delete();
      } on FileSystemException {
        // already gone
      }
    }
    _saveSoon();
    _changed();
  }

  Future<void> deleteAll() async {
    cancelAll();
    for (final id in doneIds) {
      await delete(id);
    }
    for (final id in failedIds) {
      await delete(id);
    }
  }

  /// Deletes downloads of episodes that are already played. Returns how many.
  Future<int> deletePlayed() async {
    final ids = [
      for (final id in doneIds)
        if (library.progressOf(id).played) id,
    ];
    for (final id in ids) {
      await delete(id);
    }
    return ids.length;
  }

  // ---- the queue of downloads -------------------------------------------------

  Future<bool> _network() async {
    if (!library.settings.downloadWifiOnly) return true;
    final custom = _networkAllowed;
    if (custom != null) return custom();
    try {
      final r = await Connectivity().checkConnectivity();
      // Only block when the sole connection is a mobile one; unknown counts as fine.
      return !(r.contains(ConnectivityResult.mobile) &&
          !r.contains(ConnectivityResult.wifi) &&
          !r.contains(ConnectivityResult.ethernet));
    } catch (_) {
      return true;
    }
  }

  /// Starts waiting downloads if there is room and the network now allows it.
  void resume() => _pump();

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      final max = library.settings.maxDownloads.clamp(1, 8);
      while (_active.length < max && _pending.isNotEmpty) {
        if (!await _network()) {
          for (final id in _pending) {
            _items[id]?.error = 'Waiting for Wi-Fi';
          }
          _changed();
          break;
        }
        final id = _pending.removeAt(0);
        _active.add(id);
        _items[id]
          ?..state = DownloadState.downloading
          ..error = null;
        _changed();
        unawaited(
          _run(id).whenComplete(() {
            _active.remove(id);
            _pump();
          }),
        );
      }
    } finally {
      _pumping = false;
    }
  }

  /// Resolves when nothing is downloading or waiting. For tests and "download then play" flows.
  Future<void> whenIdle() async {
    while (_active.isNotEmpty || _pending.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<Directory> _root() async {
    final custom = library.settings.downloadDir;
    if (custom.isNotEmpty) return Directory(custom);
    return _directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'downloads'),
        );
  }

  static String _safe(String s, [int max = 60]) {
    final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), '_').trim();
    return cleaned.isEmpty
        ? 'episode'
        : (cleaned.length > max ? cleaned.substring(0, max).trim() : cleaned);
  }

  /// FNV-1a, stable across runs (unlike String.hashCode), to keep file names unique.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String _extension(Episode e) {
    final fromUrl = p
        .extension(Uri.tryParse(e.audioUrl)?.path ?? '')
        .toLowerCase();
    if (const {
      '.mp3',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.wav',
      '.flac',
      '.mp4',
      '.m4b',
    }.contains(fromUrl)) {
      return fromUrl;
    }
    return switch (e.mimeType.toLowerCase()) {
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'audio/aac' => '.aac',
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/wav' || 'audio/x-wav' => '.wav',
      _ => '.mp3',
    };
  }

  Future<String> _pathFor(Episode e) async {
    final dir = p.join(
      (await _root()).path,
      _safe(
        library.podcastTitle(e.feedUrl).isEmpty
            ? 'Podcast'
            : library.podcastTitle(e.feedUrl),
        40,
      ),
    );
    final date = e.published > 0
        ? DateTime.fromMillisecondsSinceEpoch(e.published)
              .toIso8601String()
              .substring(0, 10)
        : 'undated';
    return p.join(
      dir,
      '$date ${_safe(e.title, 50)} [${_hash(e.id)}]${_extension(e)}',
    );
  }

  void _deletePart(String id) {
    final path = _items[id]?.path ?? '';
    if (path.isEmpty) return;
    try {
      File('$path.part').deleteSync();
    } on FileSystemException {
      // nothing to remove
    }
  }

  Future<void> _run(String id) async {
    final e = _episodes[id];
    final info = _items[id];
    if (e == null || info == null) return;
    IOSink? sink;
    try {
      final path = await _pathFor(e);
      info.path = path;
      await File(path).parent.create(recursive: true);
      final part = File('$path.part');
      var have = await part.exists() ? await part.length() : 0;

      final headers = {
        'User-Agent': library.settings.effectiveUserAgent,
        if (have > 0) 'Range': 'bytes=$have-',
      };
      final timeout = Duration(seconds: library.settings.requestTimeoutSec);
      final resp = await sendFollowingRedirects(
        _http,
        Uri.parse(e.audioUrl),
        headers: headers,
        timeout: timeout,
      );

      if (resp.statusCode == 416 && have > 0) {
        // We already have all of it.
        await resp.stream.drain<void>();
      } else if (resp.statusCode == 200 || resp.statusCode == 206) {
        if (resp.statusCode == 200) {
          have = 0; // the server ignored Range: start over
        }
        info
          ..bytes = have
          ..total = resp.contentLength == null
              ? -1
              : resp.contentLength! + have;
        sink = part.openWrite(
          mode: have > 0 ? FileMode.append : FileMode.write,
        );
        await for (final chunk in resp.stream.timeout(
          const Duration(seconds: 60),
        )) {
          if (_cancelled.contains(id)) break;
          sink.add(chunk);
          info.bytes += chunk.length;
          _changed(force: false);
        }
        await sink.close();
        sink = null;
        if (_cancelled.remove(id)) {
          try {
            await part.delete();
          } on FileSystemException {
            // nothing to remove
          }
          _items.remove(id);
          _episodes.remove(id);
          _changed();
          return;
        }
        if (info.total > 0 && info.bytes < info.total) {
          throw const HttpException('Connection closed early');
        }
      } else {
        throw HttpException('Server answered HTTP ${resp.statusCode}');
      }

      final done = File(path);
      if (await done.exists()) await done.delete();
      await part.rename(path);
      // Read the size first: the state must only flip to done once everything else is settled.
      final size = await done.length();
      info
        ..bytes = size
        ..total = size
        ..error = null
        ..at = DateTime.now().millisecondsSinceEpoch
        ..state = DownloadState.done;
      _episodes.remove(id);
      _saveSoon();
      onFinished?.call(id);
    } catch (err) {
      await sink?.close();
      info
        ..state = DownloadState.failed
        ..error = cleanError(err);
      _cancelled.remove(id);
    }
    _changed();
  }

  // ---- automatic rules -----------------------------------------------------------

  void _onLibrary() {
    final s = library.settings;
    final queue = library.queue;
    final upcoming = s.autoDownloadQueue
        ? (s.autoDownloadQueueCount <= 0
                  ? queue
                  : queue.take(s.autoDownloadQueueCount))
              .join(',')
        : '';
    final playedDownloads = doneIds
        .where((id) => library.progressOf(id).played)
        .length;
    final sig =
        '$upcoming|${s.autoDownloadQueue}|${s.autoDeleteHours}|${s.keepFavoriteDownloads}|$playedDownloads';
    if (sig == _signature) return;
    _signature = sig;
    reconcile();
  }

  /// Applies "keep the next Up Next episodes downloaded" and the auto-delete rule.
  void reconcile() {
    final s = library.settings;
    // Episodes that left the queue may be auto-downloaded again if they come back.
    _declined.removeWhere((id) => !library.queue.contains(id));
    if (s.autoDownloadQueue) {
      final eps = library.queueEpisodes;
      for (final e
          in s.autoDownloadQueueCount <= 0
              ? eps
              : eps.take(s.autoDownloadQueueCount)) {
        if (_items.containsKey(e.id) ||
            _declined.contains(e.id) ||
            library.progressOf(e.id).played) {
          continue;
        }
        download(e, auto: true);
      }
    }
    sweep();
  }

  /// Per-podcast override of auto-delete: AntennaPod's codes, 0 = use the global setting, 1 = always, 2 = never.
  int _deleteHoursFor(Podcast? pc) {
    final global = library.settings.autoDeleteHours;
    switch (pc?.extra['autoDeleteAction']) {
      case 1:
        return global < 0 ? 0 : global;
      case 2:
        return -1;
    }
    return global;
  }

  /// Deletes downloads of played episodes once their delay has passed. Returns how many.
  int sweep() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var removed = 0;
    for (final id in doneIds) {
      final pr = library.progressOf(id);
      if (!pr.played) continue;
      final e = library.episodes[id];
      final hours = _deleteHoursFor(
        e == null ? null : library.podcasts[e.feedUrl],
      );
      if (hours < 0) continue;
      if (library.settings.keepFavoriteDownloads && library.isFavorite(id)) {
        continue;
      }
      if (isInUse?.call(id) ?? false) continue;
      if (now - pr.updatedAt < hours * 3600000) continue;
      unawaited(delete(id, byUser: false));
      removed++;
    }
    return removed;
  }

  /// A refresh found new episodes. Download the newest few, if this podcast should.
  void handleNewEpisodes(Podcast pc, List<Episode> arrivals) {
    // 0 = follow the global setting, 1 = always for this podcast, 2 = never.
    final wanted = switch (pc.extra['autoDownloadNew']) {
      1 => true,
      2 => false,
      _ => library.settings.autoDownloadNew,
    };
    if (!wanted) return;
    final newest =
        ([...arrivals]..sort((a, b) => b.published.compareTo(a.published)))
            .take(library.settings.autoDownloadNewLimit.clamp(1, 50));
    for (final e in newest) {
      download(e, auto: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    library.removeListener(_onLibrary);
    if (library.onNewEpisodes == handleNewEpisodes) {
      library.onNewEpisodes = null;
    }
    _saveTimer?.cancel();
    _sweepTimer?.cancel();
    _netSub?.cancel();
    super.dispose();
  }
}
