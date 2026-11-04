import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'feed.dart';
import 'gpodder.dart';
import 'models.dart';
import 'settings.dart';

/// All app data: subscriptions, episodes, progress, queue, favorites and
/// settings, plus the bookkeeping for both sync backends (the PodSync server
/// and gPodder). Every mutation of synced data goes through [_touch].
class Library extends ChangeNotifier {
  Library({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  final Map<String, Podcast> podcasts = {};
  final Map<String, Episode> episodes = {};
  final Map<String, Progress> progress = {};
  final Map<String, Flag> favorites = {};
  List<String> queue = [];
  int queueUpdatedAt = 0;

  final AppSettings settings = AppSettings();

  // Synced preferences.
  double speed = 1.0;
  int skipBackSec = 10;
  int skipForwardSec = 30;
  int prefsUpdatedAt = 0;

  // Per-device (not synced).
  bool einkMode = false;

  // PodSync server.
  String serverUrl = '';
  String token = '';
  String username = '';
  int _syncSeq = 0;
  final Map<String, int> _dirty = {}; // "type|key" -> updatedAt when marked

  // gPodder.
  String gServer = '';
  String gUser = '';
  String gPass = '';
  String gDevice = '';
  bool _gRegistered = false;
  int _gSubsSince = 0;
  int _gActionsSince = 0;
  final Map<String, int> _gDirty = {}; // only "sub|..." and "progress|..."
  List<Map<String, dynamic>> _gPending = []; // actions whose episode we don't have yet

  bool syncing = false;
  String? syncError;
  DateTime? lastSync;

  File? _file;
  Timer? _saveTimer;
  Timer? _refreshTimer;
  Timer? _syncTimer;

  // ---- persistence -------------------------------------------------------

  Future<void> load({File? file}) async {
    _file = file ?? File(p.join((await getApplicationSupportDirectory()).path, 'library.json'));
    if (!await _file!.exists()) return;
    try {
      _applyMap(jsonDecode(await _file!.readAsString()) as Map<String, dynamic>, includeAccounts: true);
    } catch (e) {
      debugPrint('Could not read library.json: $e');
    }
  }

  /// Where library data is stored on this device.
  String get dataPath => _file?.path ?? '';

  void _applyMap(Map<String, dynamic> j, {required bool includeAccounts}) {
    for (final x in (j['podcasts'] as List? ?? [])) {
      final pc = Podcast.fromJson(x);
      podcasts[pc.feedUrl] = pc;
    }
    for (final x in (j['episodes'] as List? ?? [])) {
      final e = Episode.fromJson(x);
      episodes[e.id] = e;
    }
    (j['progress'] as Map? ?? {}).forEach((k, v) => progress[k] = Progress.fromJson(v));
    (j['favorites'] as Map? ?? {}).forEach((k, v) => favorites[k] = Flag(v['on'], v['at']));
    queue = List<String>.from(j['queue'] ?? []);
    queueUpdatedAt = j['queueUpdatedAt'] ?? 0;
    speed = (j['speed'] ?? 1.0).toDouble();
    skipBackSec = j['skipBackSec'] ?? 10;
    skipForwardSec = j['skipForwardSec'] ?? 30;
    prefsUpdatedAt = j['prefsUpdatedAt'] ?? 0;
    settings.applyJson(Map<String, dynamic>.from(j['settings'] ?? {}));
    currentDateStyle = settings.dateStyle;
    if (!includeAccounts) return;
    einkMode = j['einkMode'] ?? false;
    serverUrl = j['serverUrl'] ?? '';
    token = j['token'] ?? '';
    username = j['username'] ?? '';
    _syncSeq = j['syncSeq'] ?? 0;
    (j['dirty'] as Map? ?? {}).forEach((k, v) => _dirty[k] = v);
    gServer = j['gServer'] ?? '';
    gUser = j['gUser'] ?? '';
    gPass = j['gPass'] ?? '';
    gDevice = j['gDevice'] ?? '';
    _gRegistered = j['gRegistered'] ?? false;
    _gSubsSince = j['gSubsSince'] ?? 0;
    _gActionsSince = j['gActionsSince'] ?? 0;
    (j['gDirty'] as Map? ?? {}).forEach((k, v) => _gDirty[k] = v);
    _gPending = List<Map<String, dynamic>>.from((j['gPending'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)));
  }

  void _scheduleSave() {
    if (_file == null) return; // nothing to save to (e.g. in tests)
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), saveNow);
  }

  Map<String, dynamic> _toMap({required bool includeAccounts}) => {
      'podcasts': podcasts.values.map((x) {
        final j = x.toJson();
        if (!includeAccounts) j['password'] = '';
        return j;
      }).toList(),
      'episodes': episodes.values.map((x) => x.toJson()).toList(),
      'progress': progress.map((k, v) => MapEntry(k, v.toJson())),
      'favorites': favorites.map((k, v) => MapEntry(k, {'on': v.on, 'at': v.at})),
      'queue': queue,
      'queueUpdatedAt': queueUpdatedAt,
      'speed': speed,
      'skipBackSec': skipBackSec,
      'skipForwardSec': skipForwardSec,
      'prefsUpdatedAt': prefsUpdatedAt,
      'settings': settings.toJson(),
      if (includeAccounts) ...{
        'einkMode': einkMode,
        'serverUrl': serverUrl,
        'token': token,
        'username': username,
        'syncSeq': _syncSeq,
        'dirty': _dirty,
        'gServer': gServer,
        'gUser': gUser,
        'gPass': gPass,
        'gDevice': gDevice,
        'gRegistered': _gRegistered,
        'gSubsSince': _gSubsSince,
        'gActionsSince': _gActionsSince,
        'gDirty': _gDirty,
        'gPending': _gPending,
      },
    };

  Future<void> saveNow() async {
    final f = _file;
    if (f == null) return;
    final data = jsonEncode(_toMap(includeAccounts: true));
    // Write to a temp file first so a crash can't leave a half-written library.
    final tmp = File('${f.path}.tmp');
    await f.parent.create(recursive: true);
    await tmp.writeAsString(data);
    await tmp.rename(f.path);
  }

  // ---- backup, restore, reset ----------------------------------------------

  /// The whole library as JSON for a backup file. Sign-ins and feed passwords are left out.
  String exportBackup() => jsonEncode({'format': 'podsync-backup', 'version': 1, ..._toMap(includeAccounts: false)});

  /// Replaces podcasts, episodes, progress, favorites, queue and settings with a backup's.
  /// This device's sign-ins stay, and everything is queued for upload.
  void restoreBackup(String json) {
    final j = jsonDecode(json);
    if (j is! Map<String, dynamic> || j['format'] != 'podsync-backup') {
      throw const FormatException('This is not a PodSync backup file');
    }
    podcasts.clear();
    episodes.clear();
    progress.clear();
    favorites.clear();
    _applyMap(j, includeAccounts: false);
    for (final s in podcasts.values) {
      _touch('sub', s.feedUrl, s.updatedAt);
    }
    for (final e in progress.entries) {
      _touch('progress', e.key, e.value.updatedAt);
    }
    for (final e in favorites.entries) {
      _touch('fav', e.key, e.value.at);
    }
    queueUpdatedAt = _now();
    prefsUpdatedAt = queueUpdatedAt;
    _touch('queue', 'main', queueUpdatedAt);
    _touch('setting', 'prefs', prefsUpdatedAt);
    _rescheduleTimers();
    _changed();
    sync();
  }

  /// Deletes all local data and sign-ins and resets every setting. Server data is untouched.
  Future<void> wipeAll() async {
    podcasts.clear();
    episodes.clear();
    progress.clear();
    favorites.clear();
    queue = [];
    queueUpdatedAt = 0;
    speed = 1.0;
    skipBackSec = 10;
    skipForwardSec = 30;
    prefsUpdatedAt = 0;
    einkMode = false;
    for (final k in AppSettings.defaults.keys) {
      settings.reset(k);
    }
    currentDateStyle = settings.dateStyle;
    signOut();
    disconnectGpodder();
    _dirty.clear();
    _rescheduleTimers();
    notifyListeners();
    await saveNow();
  }

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Marks a record as needing upload. gPodder only knows subscriptions and progress.
  void _touch(String type, String key, int at, {bool server = true, bool gpodder = true}) {
    if (server) _dirty['$type|$key'] = at;
    if (gpodder && gpodderEnabled && (type == 'sub' || type == 'progress')) _gDirty['$type|$key'] = at;
  }

  // ---- subscriptions -----------------------------------------------------

  List<Podcast> get subscriptions =>
      podcasts.values.where((x) => x.subscribed).toList()
        ..sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));

  bool isSubscribed(String feedUrl) => podcasts[feedUrl]?.subscribed ?? false;

  String podcastTitle(String feedUrl) => podcasts[feedUrl]?.displayTitle ?? '';

  List<Episode> episodesOf(String feedUrl) =>
      _sorted(episodes.values.where((e) => e.feedUrl == feedUrl));

  /// All episodes of subscribed podcasts, newest first.
  List<Episode> get allEpisodes {
    final subs = {for (final s in subscriptions) s.feedUrl};
    return _sorted(episodes.values.where((e) => subs.contains(e.feedUrl)));
  }

  List<Episode> _sorted(Iterable<Episode> eps) => eps.toList()
    ..sort((a, b) => settings.sortOldestFirst ? a.published.compareTo(b.published) : b.published.compareTo(a.published));

  Future<ParsedFeed> _fetch(String feedUrl, {Podcast? pc}) => fetchFeed(
        feedUrl,
        client: _http,
        username: pc?.username,
        password: pc?.password,
        timeout: Duration(seconds: settings.requestTimeoutSec),
        userAgent: settings.effectiveUserAgent,
      );

  Future<void> subscribe(String feedUrl) async {
    final parsed = await _fetch(feedUrl, pc: podcasts[feedUrl]);
    final now = _now();
    final existing = podcasts[feedUrl];
    final pc = existing ?? parsed.podcast;
    if (existing != null) _copyFeedMeta(existing, parsed.podcast);
    pc
      ..subscribed = true
      ..updatedAt = now;
    podcasts[feedUrl] = pc;
    _mergeEpisodes(parsed.episodes);
    _touch('sub', feedUrl, now);
    _changed();
    sync();
  }

  void unsubscribe(String feedUrl) {
    final pc = podcasts[feedUrl];
    if (pc == null) return;
    final now = _now();
    pc
      ..subscribed = false
      ..updatedAt = now;
    _touch('sub', feedUrl, now);
    _changed();
    sync();
  }

  void _copyFeedMeta(Podcast to, Podcast from) {
    to
      ..title = from.title.isNotEmpty ? from.title : to.title
      ..author = from.author
      ..imageUrl = from.imageUrl.isNotEmpty ? from.imageUrl : to.imageUrl
      ..description = from.description
      ..link = from.link
      ..language = from.language;
  }

  void _mergeEpisodes(List<Episode> fresh) {
    for (final e in fresh) {
      final old = episodes[e.id];
      episodes[e.id] = old == null ? e : old.mergedWith(e);
    }
  }

  Future<void> refreshFeed(String feedUrl) async {
    final pc = podcasts[feedUrl];
    final parsed = await _fetch(feedUrl, pc: pc);
    final known = {for (final e in episodes.values) if (e.feedUrl == feedUrl) e.id: e.published};
    if (pc != null) _copyFeedMeta(pc, parsed.podcast);
    _mergeEpisodes(parsed.episodes);
    if (pc != null && pc.subscribed && known.isNotEmpty) _queueNewEpisodes(pc, parsed.episodes, known);
    _pruneEpisodes(feedUrl);
    _applyGpodderActions();
    _changed();
  }

  /// Podcast override (AntennaPod codes: 2 = add to queue, 1 or 3 = nothing), else the global setting.
  int _newEpisodesActionFor(Podcast pc) {
    switch (pc.extra['newEpisodesAction']) {
      case 2:
        return 1;
      case 1:
      case 3:
        return 0;
    }
    return settings.newEpisodesAction;
  }

  void _queueNewEpisodes(Podcast pc, List<Episode> fresh, Map<String, int> known) {
    final action = _newEpisodesActionFor(pc);
    if (action == 0) return;
    final newestKnown = known.values.fold(0, max);
    final arrivals = fresh.where((e) => !known.containsKey(e.id) && e.published >= newestKnown && !progressOf(e.id).played).toList()
      ..sort((a, b) => a.published.compareTo(b.published));
    for (final e in arrivals) {
      if (queue.contains(e.id)) continue;
      action == 2 ? queue.insert(0, e.id) : queue.add(e.id);
    }
    if (arrivals.isNotEmpty) {
      queueUpdatedAt = _now();
      _touch('queue', 'main', queueUpdatedAt);
    }
  }

  /// Applies "episodes to keep per podcast", never dropping anything you have started,
  /// queued or favorited.
  void _pruneEpisodes(String feedUrl) {
    final limit = settings.maxEpisodesPerFeed;
    if (limit <= 0) return;
    final eps = episodesOf(feedUrl)..sort((a, b) => b.published.compareTo(a.published));
    for (final e in eps.skip(limit)) {
      if (queue.contains(e.id) || isFavorite(e.id) || progress.containsKey(e.id)) continue;
      episodes.remove(e.id);
    }
  }

  Future<void> refreshAll() async {
    await Future.wait(subscriptions.map((s) => refreshFeed(s.feedUrl).catchError((Object e) {
          debugPrint('refresh ${s.feedUrl}: $e');
        })));
  }

  /// Changes a podcast's own settings (custom name, speed, skip intro/ending, tags).
  void updatePodcastSettings(String feedUrl, {String? customTitle, double? speed, bool clearSpeed = false, int? skipIntroSec, int? skipEndingSec, int? newEpisodesAction, List<String>? tags}) {
    final pc = podcasts[feedUrl];
    if (pc == null) return;
    if (customTitle != null) pc.customTitle = customTitle;
    if (clearSpeed) pc.speed = null;
    if (speed != null) pc.speed = speed;
    if (skipIntroSec != null) pc.skipIntroSec = skipIntroSec;
    if (skipEndingSec != null) pc.skipEndingSec = skipEndingSec;
    if (newEpisodesAction != null) pc.extra['newEpisodesAction'] = newEpisodesAction;
    if (tags != null) pc.tags = tags;
    pc.updatedAt = _now();
    _touch('sub', feedUrl, pc.updatedAt, gpodder: false);
    _changed();
  }

  // ---- progress, favorites, history ---------------------------------------

  Progress progressOf(String id) => progress[id] ?? Progress();

  void setProgress(String id, int positionMs, int durationMs, {bool? played}) {
    final now = _now();
    final pr = progress.putIfAbsent(id, Progress.new);
    pr
      ..positionMs = positionMs
      ..durationMs = durationMs > 0 ? durationMs : pr.durationMs
      ..isNew = false
      ..lastPlayedAt = now
      ..updatedAt = now;
    if (played != null) pr.played = played;
    _touch('progress', id, now);
    _changed();
  }

  void markPlayed(String id, bool played) {
    final pr = progressOf(id);
    final now = _now();
    final next = progress.putIfAbsent(id, Progress.new);
    next
      ..positionMs = played ? 0 : pr.positionMs
      ..played = played
      ..isNew = false
      ..updatedAt = now;
    _touch('progress', id, now);
    _changed();
  }

  bool isFavorite(String id) => favorites[id]?.on ?? false;

  void setFavorite(String id, bool on) {
    final now = _now();
    favorites[id] = Flag(on, now);
    _touch('fav', id, now);
    _changed();
  }

  List<Episode> get favoriteEpisodes => [
        for (final e in favorites.entries)
          if (e.value.on && episodes[e.key] != null) episodes[e.key]!,
      ]..sort((a, b) => b.published.compareTo(a.published));

  /// Episodes you have listened to, most recent first.
  List<Episode> get historyEpisodes {
    final ids = progress.entries.where((e) => e.value.lastPlayedAt > 0 && episodes[e.key] != null).toList()
      ..sort((a, b) => b.value.lastPlayedAt.compareTo(a.value.lastPlayedAt));
    return [for (final e in ids) episodes[e.key]!];
  }

  // ---- queue -------------------------------------------------------------

  List<Episode> get queueEpisodes => [
        for (final id in queue)
          if (episodes[id] != null) episodes[id]!,
      ];

  void _queueChanged() {
    queueUpdatedAt = _now();
    _touch('queue', 'main', queueUpdatedAt);
    _changed();
  }

  void enqueue(String id, {bool next = false}) {
    queue.remove(id);
    next ? queue.insert(0, id) : queue.add(id);
    _queueChanged();
  }

  void removeFromQueue(String id) {
    if (queue.remove(id)) _queueChanged();
  }

  void reorderQueue(int from, int to) {
    if (to > from) to -= 1;
    queue.insert(to, queue.removeAt(from));
    _queueChanged();
  }

  void clearQueue() {
    queue = [];
    _queueChanged();
  }

  // ---- batch actions (right-click menus act on several episodes at once) -----

  /// Adds episodes to the queue, keeping their order. [next] puts them at the front instead.
  void enqueueAll(List<String> ids, {bool next = false}) {
    queue.removeWhere(ids.contains);
    next ? queue.insertAll(0, ids) : queue.addAll(ids);
    _queueChanged();
  }

  void removeAllFromQueue(List<String> ids) {
    final before = queue.length;
    queue.removeWhere(ids.contains);
    if (queue.length != before) _queueChanged();
  }

  /// Moves queued episodes to the top or bottom, keeping their relative order.
  void moveInQueue(List<String> ids, {required bool toTop}) {
    final moving = queue.where(ids.contains).toList();
    queue.removeWhere(ids.contains);
    toTop ? queue.insertAll(0, moving) : queue.addAll(moving);
    _queueChanged();
  }

  void markAllPlayed(Iterable<String> ids, bool played) {
    final now = _now();
    for (final id in ids) {
      final pr = progress.putIfAbsent(id, Progress.new);
      pr
        ..positionMs = played ? 0 : pr.positionMs
        ..played = played
        ..isNew = false
        ..updatedAt = now;
      _touch('progress', id, now);
    }
    _changed();
  }

  void setFavorites(Iterable<String> ids, bool on) {
    final now = _now();
    for (final id in ids) {
      favorites[id] = Flag(on, now);
      _touch('fav', id, now);
    }
    _changed();
  }

  /// Takes episodes out of the listening history without changing whether they count as played.
  void removeFromHistory(Iterable<String> ids) {
    final now = _now();
    for (final id in ids) {
      final pr = progress[id];
      if (pr == null) continue;
      pr
        ..lastPlayedAt = 0
        ..updatedAt = now;
      _touch('progress', id, now);
    }
    _changed();
  }

  // ---- preferences -------------------------------------------------------

  void setPrefs({double? speed, int? skipBackSec, int? skipForwardSec}) {
    this.speed = speed ?? this.speed;
    this.skipBackSec = skipBackSec ?? this.skipBackSec;
    this.skipForwardSec = skipForwardSec ?? this.skipForwardSec;
    prefsUpdatedAt = _now();
    _touch('setting', 'prefs', prefsUpdatedAt);
    _changed();
  }

  /// Playback speed for a podcast: its own setting, else the global one.
  double speedFor(String feedUrl) => podcasts[feedUrl]?.speed ?? speed;

  /// Sets the speed where it applies: a podcast that has its own speed keeps it separate.
  void setSpeedFor(String feedUrl, double s) {
    if (podcasts[feedUrl]?.speed != null) {
      updatePodcastSettings(feedUrl, speed: s);
    } else {
      setPrefs(speed: s);
    }
  }

  /// Changes one setting. Synced settings also go to the server.
  void setSetting(String key, Object value) {
    settings.set(key, value);
    _afterSettingChange(key);
  }

  void resetSettings() {
    for (final k in AppSettings.defaults.keys) {
      settings.reset(k);
    }
    _afterSettingChange('themeMode');
    prefsUpdatedAt = _now();
    _touch('setting', 'prefs', prefsUpdatedAt);
  }

  void _afterSettingChange(String key) {
    if (AppSettings.synced.contains(key)) {
      prefsUpdatedAt = _now();
      _touch('setting', 'prefs', prefsUpdatedAt);
    }
    if (key == 'dateStyle' || key == 'themeMode') currentDateStyle = settings.dateStyle;
    if (key == 'refreshIntervalMin' || key == 'syncIntervalMin' || key == 'themeMode') _rescheduleTimers();
    _changed();
  }

  /// Startup work and the periodic timers; call once after [load].
  void startBackground() {
    currentDateStyle = settings.dateStyle;
    if (settings.refreshOnLaunch) {
      refreshAll().then((_) => settings.syncOnStart ? sync() : null);
    } else if (settings.syncOnStart) {
      sync();
    }
    _rescheduleTimers();
  }

  void _rescheduleTimers() {
    _refreshTimer?.cancel();
    _syncTimer?.cancel();
    _refreshTimer = settings.refreshIntervalMin > 0
        ? Timer.periodic(Duration(minutes: settings.refreshIntervalMin), (_) => refreshAll())
        : null;
    _syncTimer = settings.syncIntervalMin > 0
        ? Timer.periodic(Duration(minutes: settings.syncIntervalMin), (_) => sync())
        : null;
  }

  void setEink(bool v) {
    einkMode = v;
    _changed();
  }

  // ---- importing (used by the AntennaPod / OPML importers) -----------------

  /// Adds a podcast from a backup without overwriting anything the user already has.
  void importPodcast(Podcast incoming, List<Episode> eps) {
    final now = _now();
    final existing = podcasts[incoming.feedUrl];
    if (existing == null) {
      podcasts[incoming.feedUrl] = incoming..updatedAt = now;
      _touch('sub', incoming.feedUrl, now);
    } else {
      var changed = false;
      if (incoming.subscribed && !existing.subscribed) {
        existing.subscribed = true;
        changed = true;
      }
      if (existing.customTitle.isEmpty && incoming.customTitle.isNotEmpty) {
        existing.customTitle = incoming.customTitle;
        changed = true;
      }
      if (existing.speed == null && incoming.speed != null) {
        existing.speed = incoming.speed;
        changed = true;
      }
      if (existing.skipIntroSec == 0 && incoming.skipIntroSec > 0) {
        existing.skipIntroSec = incoming.skipIntroSec;
        changed = true;
      }
      if (existing.skipEndingSec == 0 && incoming.skipEndingSec > 0) {
        existing.skipEndingSec = incoming.skipEndingSec;
        changed = true;
      }
      for (final t in incoming.tags) {
        if (!existing.tags.contains(t)) {
          existing.tags.add(t);
          changed = true;
        }
      }
      if (existing.imageUrl.isEmpty) existing.imageUrl = incoming.imageUrl;
      if (existing.username.isEmpty) {
        existing.username = incoming.username;
        existing.password = incoming.password;
      }
      existing.extra = {...incoming.extra, ...existing.extra};
      if (changed) {
        existing.updatedAt = now;
        _touch('sub', existing.feedUrl, now);
      }
    }
    _mergeEpisodes(eps);
  }

  /// Takes backup progress only where it is newer than what is already here.
  bool importProgress(String id, Progress incoming) {
    final existing = progress[id];
    if (existing != null && existing.updatedAt >= incoming.updatedAt) {
      existing.lastPlayedAt = max(existing.lastPlayedAt, incoming.lastPlayedAt);
      return false;
    }
    progress[id] = incoming;
    _touch('progress', id, incoming.updatedAt);
    return true;
  }

  /// Backup queue goes in front of an empty queue, or after the current one.
  int importQueue(List<String> ids) {
    var added = 0;
    for (final id in ids) {
      if (!queue.contains(id)) {
        queue.add(id);
        added++;
      }
    }
    if (added > 0) {
      queueUpdatedAt = _now();
      _touch('queue', 'main', queueUpdatedAt);
    }
    return added;
  }

  bool importFavorite(String id) {
    if (isFavorite(id)) return false;
    final now = _now();
    favorites[id] = Flag(true, now);
    _touch('fav', id, now);
    return true;
  }

  /// Call once after a batch of imports.
  void finishImport() {
    _changed();
    sync();
  }

  // ---- sync: orchestration -------------------------------------------------

  bool get signedIn => token.isNotEmpty && serverUrl.isNotEmpty;
  bool get gpodderEnabled => gServer.isNotEmpty && gUser.isNotEmpty;
  bool get syncEnabled => signedIn || gpodderEnabled;

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> sync() async {
    if (!syncEnabled || syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    final errors = <String>[];
    try {
      if (signedIn) {
        try {
          await _syncPodsync();
        } catch (e) {
          errors.add(_msg(e));
        }
      }
      if (gpodderEnabled) {
        try {
          await _syncGpodder();
        } catch (e) {
          errors.add('gPodder: ${_msg(e)}');
        }
      }
      if (errors.isNotEmpty) syncError = errors.join('\n');
    } finally {
      syncing = false;
      _changed();
    }
  }

  // ---- sync: PodSync server -------------------------------------------------

  Uri _api(String path) => Uri.parse('${serverUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<void> signIn(String server, String user, String password, {bool register = false}) async {
    serverUrl = server.trim();
    final res = await _http.post(
      _api(register ? '/api/register' : '/api/login'),
      body: jsonEncode({'username': user, 'password': password, 'device': Platform.operatingSystem}),
    );
    if (res.statusCode != 200) {
      throw Exception(res.body.trim().isEmpty ? 'HTTP ${res.statusCode}' : res.body.trim());
    }
    token = jsonDecode(res.body)['token'];
    username = user;
    _syncSeq = 0;
    // First sign-in on a device pushes everything it already has.
    for (final s in podcasts.values) {
      _touch('sub', s.feedUrl, s.updatedAt, gpodder: false);
    }
    for (final e in progress.entries) {
      _touch('progress', e.key, e.value.updatedAt, gpodder: false);
    }
    for (final e in favorites.entries) {
      _touch('fav', e.key, e.value.at);
    }
    if (queueUpdatedAt > 0) _touch('queue', 'main', queueUpdatedAt);
    if (prefsUpdatedAt > 0) _touch('setting', 'prefs', prefsUpdatedAt);
    _changed();
    await sync();
  }

  void signOut() {
    token = '';
    username = '';
    _syncSeq = 0;
    _dirty.clear();
    _changed();
  }

  Map<String, dynamic>? _recordFor(String type, String key) {
    switch (type) {
      case 'sub':
        final pc = podcasts[key];
        if (pc == null) return null;
        return {
          'type': type,
          'key': key,
          'updated_at': pc.updatedAt,
          'deleted': !pc.subscribed,
          'data': {
            'title': pc.title,
            'customTitle': pc.customTitle,
            'author': pc.author,
            'imageUrl': pc.imageUrl,
            'speed': pc.speed,
            'skipIntro': pc.skipIntroSec,
            'skipEnding': pc.skipEndingSec,
            'tags': pc.tags,
          },
        };
      case 'progress':
        final pr = progress[key];
        if (pr == null) return null;
        return {
          'type': type,
          'key': key,
          'updated_at': pr.updatedAt,
          'deleted': false,
          'data': {'pos': pr.positionMs, 'dur': pr.durationMs, 'played': pr.played, 'new': pr.isNew, 'lastPlayed': pr.lastPlayedAt},
        };
      case 'fav':
        final f = favorites[key];
        if (f == null) return null;
        return {'type': type, 'key': key, 'updated_at': f.at, 'deleted': !f.on, 'data': {}};
      case 'queue':
        return {'type': type, 'key': key, 'updated_at': queueUpdatedAt, 'deleted': false, 'data': {'items': queue}};
      case 'setting':
        return {
          'type': type,
          'key': key,
          'updated_at': prefsUpdatedAt,
          'deleted': false,
          'data': {'speed': speed, 'skipBack': skipBackSec, 'skipForward': skipForwardSec, 'more': settings.syncedJson()},
        };
    }
    return null;
  }

  Future<void> _syncPodsync() async {
    final pushed = Map<String, int>.from(_dirty);
    final changes = <Map<String, dynamic>>[];
    pushed.forEach((k, at) {
      final i = k.indexOf('|');
      final r = _recordFor(k.substring(0, i), k.substring(i + 1));
      if (r != null) changes.add(r);
    });
    final res = await _http
        .post(_api('/api/sync'), headers: {'Authorization': 'Bearer $token'}, body: jsonEncode({'since': _syncSeq, 'changes': changes}))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      token = '';
      throw Exception('Signed out by the server, please sign in again');
    }
    if (res.statusCode != 200) throw Exception('Sync failed (HTTP ${res.statusCode})');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final newSubs = applyRemote(List<Map<String, dynamic>>.from(body['changes']));
    _syncSeq = body['seq'];
    // Only clear entries that were not modified again while the request was in flight.
    pushed.forEach((k, at) {
      if (_dirty[k] == at) _dirty.remove(k);
    });
    lastSync = DateTime.now();
    // Fetch episodes for subscriptions that arrived from another device.
    for (final f in newSubs) {
      refreshFeed(f).catchError((Object e) => debugPrint('refresh $f: $e'));
    }
  }

  /// Merges server records into local state (newest updated_at wins).
  /// Returns feed URLs of subscriptions that are new to this device.
  @visibleForTesting
  List<String> applyRemote(List<Map<String, dynamic>> changes) {
    final newSubs = <String>[];
    for (final c in changes) {
      final at = (c['updated_at'] as num).toInt();
      final key = c['key'] as String;
      final data = (c['data'] as Map?)?.cast<String, dynamic>() ?? {};
      switch (c['type']) {
        case 'sub':
          final existing = podcasts[key];
          if (existing != null && existing.updatedAt >= at) break;
          final subscribed = !(c['deleted'] as bool);
          if ((existing == null || !existing.subscribed) && subscribed) newSubs.add(key);
          final pc = existing ?? Podcast(feedUrl: key);
          pc
            ..title = data['title'] ?? pc.title
            ..customTitle = data['customTitle'] ?? pc.customTitle
            ..author = data['author'] ?? pc.author
            ..imageUrl = data['imageUrl'] ?? pc.imageUrl
            ..speed = (data['speed'] as num?)?.toDouble()
            ..skipIntroSec = data['skipIntro'] ?? pc.skipIntroSec
            ..skipEndingSec = data['skipEnding'] ?? pc.skipEndingSec
            ..tags = data.containsKey('tags') ? List<String>.from(data['tags'] ?? []) : pc.tags
            ..subscribed = subscribed
            ..updatedAt = at;
          podcasts[key] = pc;
          // A subscription change that came from the PodSync server still has to reach gPodder.
          _touch('sub', key, at, server: false);
          break;
        case 'progress':
          final existing = progress[key];
          if (existing != null && existing.updatedAt >= at) break;
          progress[key] = Progress(
            positionMs: data['pos'] ?? 0,
            durationMs: data['dur'] ?? 0,
            played: data['played'] ?? false,
            isNew: data['new'] ?? false,
            lastPlayedAt: max(data['lastPlayed'] ?? 0, existing?.lastPlayedAt ?? 0),
            updatedAt: at,
          );
          _touch('progress', key, at, server: false);
          break;
        case 'fav':
          final existing = favorites[key];
          if (existing != null && existing.at >= at) break;
          favorites[key] = Flag(!(c['deleted'] as bool), at);
          break;
        case 'queue':
          if (queueUpdatedAt >= at) break;
          queue = List<String>.from(data['items'] ?? []);
          queueUpdatedAt = at;
          break;
        case 'setting':
          if (prefsUpdatedAt >= at) break;
          speed = (data['speed'] ?? speed).toDouble();
          skipBackSec = data['skipBack'] ?? skipBackSec;
          skipForwardSec = data['skipForward'] ?? skipForwardSec;
          settings.applySynced(Map<String, dynamic>.from(data['more'] ?? {}));
          prefsUpdatedAt = at;
          break;
      }
    }
    return newSubs;
  }

  // ---- sync: gPodder -------------------------------------------------------

  GpodderClient _gClient() => GpodderClient(baseUrl: gServer, username: gUser, password: gPass, deviceId: gDevice, client: _http, userAgent: settings.effectiveUserAgent, timeout: Duration(seconds: settings.requestTimeoutSec));

  /// Signs in to a gPodder server and uploads what this device already has.
  Future<void> connectGpodder(String server, String user, String password) async {
    final device = gDevice.isNotEmpty ? gDevice : 'podsync-${Platform.operatingSystem}-${Random().nextInt(1 << 32).toRadixString(36)}';
    final client = GpodderClient(baseUrl: server, username: user, password: password, deviceId: device, client: _http);
    await client.login();
    await client.registerDevice('PodSync (${Platform.operatingSystem})', Platform.isAndroid ? 'mobile' : 'desktop');
    gServer = server.trim().replaceAll(RegExp(r'/+$'), '');
    gUser = user;
    gPass = password;
    gDevice = device;
    _gRegistered = true;
    _gSubsSince = 0;
    _gActionsSince = 0;
    _gPending = [];
    for (final s in podcasts.values) {
      _gDirty['sub|${s.feedUrl}'] = s.updatedAt;
    }
    for (final e in progress.entries) {
      if (e.value.positionMs > 0 || e.value.played) _gDirty['progress|${e.key}'] = e.value.updatedAt;
    }
    _changed();
    await sync();
  }

  void disconnectGpodder() {
    gServer = gUser = gPass = '';
    _gRegistered = false;
    _gSubsSince = 0;
    _gActionsSince = 0;
    _gDirty.clear();
    _gPending = [];
    _changed();
  }

  Future<void> _syncGpodder() async {
    final c = _gClient();
    if (!_gRegistered) {
      await c.login();
      await c.registerDevice('PodSync (${Platform.operatingSystem})', Platform.isAndroid ? 'mobile' : 'desktop');
      _gRegistered = true;
    }

    // 1. Pull subscription changes. Anything we changed locally and haven't uploaded yet wins.
    final subs = await c.subscriptionChanges(_gSubsSince);
    final fresh = <String>[];
    final now = _now();
    for (final url in subs.add) {
      if (_gDirty.containsKey('sub|$url')) continue;
      final pc = podcasts[url];
      if (pc != null && pc.subscribed) continue;
      if (pc == null) {
        podcasts[url] = Podcast(feedUrl: url, subscribed: true, updatedAt: now);
      } else {
        pc
          ..subscribed = true
          ..updatedAt = now;
      }
      _touch('sub', url, now, gpodder: false);
      fresh.add(url);
    }
    for (final url in subs.remove) {
      if (_gDirty.containsKey('sub|$url')) continue;
      final pc = podcasts[url];
      if (pc == null || !pc.subscribed) continue;
      pc
        ..subscribed = false
        ..updatedAt = now;
      _touch('sub', url, now, gpodder: false);
    }
    _gSubsSince = subs.timestamp;

    // 2. Push subscription changes.
    final subDirty = {for (final e in _gDirty.entries) if (e.key.startsWith('sub|')) e.key: e.value};
    final add = <String>[], remove = <String>[];
    subDirty.forEach((k, _) {
      final pc = podcasts[k.substring(4)];
      if (pc == null) return;
      (pc.subscribed ? add : remove).add(pc.feedUrl);
    });
    if (add.isNotEmpty || remove.isNotEmpty) await c.pushSubscriptions(add, remove);
    subDirty.forEach((k, at) {
      if (_gDirty[k] == at) _gDirty.remove(k);
    });

    // 3. Pull episode actions (latest per episode) and apply them.
    final acts = await c.episodeActions(_gActionsSince);
    _gPending.addAll(acts.actions);
    _applyGpodderActions();
    _gActionsSince = acts.timestamp;

    // 4. Push our progress.
    final progDirty = {for (final e in _gDirty.entries) if (e.key.startsWith('progress|')) e.key: e.value};
    final outgoing = <Map<String, dynamic>>[];
    progDirty.forEach((k, _) {
      final id = k.substring(9);
      final e = episodes[id];
      final pr = progress[id];
      if (e == null || pr == null) return;
      final totalSec = (pr.durationMs > 0 ? pr.durationMs : e.durationMs) ~/ 1000;
      final action = <String, dynamic>{
        'podcast': e.feedUrl,
        'episode': e.audioUrl,
        'guid': e.guid,
        'device': gDevice,
        'timestamp': GpodderClient.formatTime(pr.updatedAt),
      };
      if (pr.played) {
        // A play action that reaches the end is how gPodder clients mark an episode finished.
        action..['action'] = 'play'..['started'] = totalSec..['position'] = totalSec..['total'] = totalSec;
      } else if (pr.positionMs > 0) {
        action..['action'] = 'play'..['started'] = 0..['position'] = pr.positionMs ~/ 1000..['total'] = totalSec;
      } else {
        action['action'] = 'new';
      }
      outgoing.add(action);
    });
    for (var i = 0; i < outgoing.length; i += 500) {
      await c.pushActions(outgoing.sublist(i, min(i + 500, outgoing.length)));
    }
    progDirty.forEach((k, at) {
      if (_gDirty[k] == at) _gDirty.remove(k);
    });

    lastSync = DateTime.now();
    for (final f in fresh) {
      refreshFeed(f).catchError((Object e) => debugPrint('refresh $f: $e'));
    }
  }

  /// Applies queued gPodder actions to the episodes we know about; the rest wait
  /// until a feed refresh brings the episode in.
  void _applyGpodderActions() {
    if (_gPending.isEmpty) return;
    final byUrl = <String, String>{}, byGuid = <String, String>{};
    for (final e in episodes.values) {
      byUrl['${e.feedUrl}|${e.audioUrl}'] = e.id;
      byGuid['${e.feedUrl}|${e.guid}'] = e.id;
    }
    final keep = <Map<String, dynamic>>[];
    for (final a in _gPending) {
      final feed = a['podcast'] as String? ?? '';
      final id = byUrl['$feed|${a['episode']}'] ?? byGuid['$feed|${a['guid']}'];
      if (id == null) {
        if (isSubscribed(feed)) keep.add(a);
        continue;
      }
      final ts = GpodderClient.parseTime(a['timestamp']);
      final at = ts > 0 ? ts : _now();
      final existing = progress[id];
      if (existing != null && existing.updatedAt >= at) continue;
      switch (a['action']) {
        case 'play':
          final pos = (a['position'] as num?)?.toInt() ?? -1;
          final total = (a['total'] as num?)?.toInt() ?? -1;
          if (pos < 0) continue;
          final finished = total > 0 && pos >= total;
          progress[id] = Progress(
            positionMs: finished ? 0 : pos * 1000,
            durationMs: total > 0 ? total * 1000 : (existing?.durationMs ?? 0),
            played: finished,
            lastPlayedAt: max(at, existing?.lastPlayedAt ?? 0),
            updatedAt: at,
          );
          _touch('progress', id, at, gpodder: false);
        case 'new':
          progress[id] = Progress(
            durationMs: existing?.durationMs ?? 0,
            isNew: true,
            lastPlayedAt: existing?.lastPlayedAt ?? 0,
            updatedAt: at,
          );
          _touch('progress', id, at, gpodder: false);
      }
    }
    // Don't let actions for episodes that never show up pile up forever.
    _gPending = keep.length > 2000 ? keep.sublist(keep.length - 2000) : keep;
  }

  /// Exposed for tests: feed gPodder actions in as if they had been pulled.
  @visibleForTesting
  void applyGpodderActionsForTest(List<Map<String, dynamic>> actions) {
    _gPending.addAll(actions);
    _applyGpodderActions();
  }
}
