import 'package:sqlite3/sqlite3.dart';

import 'library.dart';
import 'models.dart';

/// What an import brought in, for showing to the user.
class ImportReport {
  int podcasts = 0;
  int subscribed = 0;
  int episodes = 0;
  int played = 0;
  int inProgress = 0;
  int history = 0;
  int queued = 0;
  int favorites = 0;
  int chapters = 0;
  int skippedFeeds = 0;
  int skippedEpisodes = 0;
  final List<String> warnings = [];

  String summary() {
    final lines = [
      '$podcasts podcasts ($subscribed subscribed)',
      '$episodes episodes ($played played, $inProgress partly listened)',
      if (history > 0) '$history in listening history',
      if (queued > 0) '$queued in the queue',
      if (favorites > 0) '$favorites favorites',
      if (chapters > 0) '$chapters chapters',
      if (skippedFeeds > 0) '$skippedFeeds local-folder podcasts skipped (their audio files are on the old phone)',
      if (skippedEpisodes > 0) '$skippedEpisodes episodes without audio skipped',
      ...warnings,
    ];
    return lines.join('\n');
  }
}

/// Newest database version this importer was written against (AntennaPod 3.11).
const antennaPodKnownVersion = 3110000;

const _localFolderPrefix = 'antennapod_local:';
const _generativeCoverPrefix = 'antennapod_generative_cover:';
const _tagSeparator = '\u001e';

dynamic _col(Row r, String name) => r.containsKey(name) ? r[name] : null;
int _int(Row r, String name, [int dflt = 0]) {
  final v = _col(r, name);
  return v is num ? v.toInt() : dflt;
}

String _str(Row r, String name) {
  final v = _col(r, name);
  return v is String ? v : '';
}

/// Reads an AntennaPod database backup (`AntennaPodBackup-<date>.db`, from
/// Settings > Import/Export > Database export) and merges it into [lib].
///
/// Columns are read by name and may be missing, so backups from older versions
/// import too. Preferences (AntennaPod's app settings) are not in the database
/// export, and downloaded audio files are not either.
ImportReport importAntennaPodBackup(Library lib, String path) {
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
  } catch (e) {
    throw FormatException('This file is not a database: $e');
  }
  final report = ImportReport();
  final pending = <String, (Podcast, List<Episode>)>{}; // feeds collected during this import
  try {
    final tables = {for (final r in db.select("SELECT name FROM sqlite_master WHERE type='table'")) r['name'] as String};
    if (!tables.contains('Feeds') || !tables.contains('FeedItems')) {
      throw const FormatException('This is not an AntennaPod database backup (no Feeds/FeedItems tables)');
    }
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > antennaPodKnownVersion) {
      report.warnings.add('Backup is from a newer AntennaPod (database version $version); anything new in it was ignored.');
    }

    // Feeds -------------------------------------------------------------
    final feedUrlById = <int, String>{};
    for (final r in db.select('SELECT * FROM Feeds')) {
      final url = _str(r, 'download_url');
      if (url.isEmpty) continue;
      if (url.startsWith(_localFolderPrefix)) {
        report.skippedFeeds++;
        continue;
      }
      feedUrlById[_int(r, 'id')] = url;

      final speed = _col(r, 'feed_playback_speed');
      final tags = _str(r, 'tags').split(_tagSeparator).where((t) => t.isNotEmpty && t != '#root').toList();
      final image = _str(r, 'image_url');
      final state = _int(r, 'state'); // 0 subscribed, 1 not subscribed, 2 archived
      final podcast = Podcast(
        feedUrl: url,
        title: _str(r, 'title'),
        customTitle: _str(r, 'custom_title'),
        author: _str(r, 'author'),
        imageUrl: image.startsWith(_generativeCoverPrefix) ? '' : image,
        description: _str(r, 'description'),
        link: _str(r, 'link'),
        language: _str(r, 'language'),
        subscribed: state == 0,
        speed: speed is num && speed > 0 ? speed.toDouble() : null,
        skipIntroSec: _int(r, 'feed_skip_intro'),
        skipEndingSec: _int(r, 'feed_skip_ending'),
        tags: tags,
        username: _str(r, 'username'),
        password: _str(r, 'password'),
        extra: {
          'autoDownload': _int(r, 'auto_download', 1),
          'keepUpdated': _int(r, 'keep_updated', 1),
          'autoDeleteAction': _int(r, 'auto_delete_action'),
          'volumeAdaption': _int(r, 'feed_volume_adaption'),
          'skipSilence': _int(r, 'feed_skip_silence', 1),
          'includeFilter': _str(r, 'include_filter'),
          'excludeFilter': _str(r, 'exclude_filter'),
          'minimalDurationFilter': _int(r, 'minimal_duration_filter', -1),
          'episodeNotification': _int(r, 'episode_notification'),
          'newEpisodesAction': _int(r, 'new_episodes_action'),
          'sortOrder': _str(r, 'sort_order'),
          'hide': _str(r, 'hide'),
          'paymentLink': _str(r, 'payment_link'),
        },
      );
      pending[url] = (podcast, <Episode>[]);
      report.podcasts++;
      if (podcast.subscribed) report.subscribed++;
    }

    // Media (durations, positions, download URLs), one row per episode -------
    final mediaByItem = <int, Row>{};
    if (tables.contains('FeedMedia')) {
      for (final r in db.select('SELECT * FROM FeedMedia')) {
        mediaByItem[_int(r, 'feeditem')] = r;
      }
    }
    // Very old databases linked item -> media instead of media -> item.
    final mediaById = <int, Row>{};
    if (mediaByItem.isEmpty && tables.contains('FeedMedia')) {
      for (final r in db.select('SELECT * FROM FeedMedia')) {
        mediaById[_int(r, 'id')] = r;
      }
    }

    // Chapters ---------------------------------------------------------------
    final chaptersByItem = <int, List<Chapter>>{};
    if (tables.contains('SimpleChapters')) {
      for (final r in db.select('SELECT * FROM SimpleChapters ORDER BY start')) {
        (chaptersByItem[_int(r, 'feeditem')] ??= []).add(Chapter(
          _int(r, 'start'),
          _str(r, 'title'),
          link: _str(r, 'link'),
          imageUrl: _str(r, 'image_url'),
        ));
      }
    }

    // Episodes + their play state --------------------------------------------
    final idByItem = <int, String>{};
    final progressById = <String, Progress>{};
    for (final r in db.select('SELECT * FROM FeedItems')) {
      final itemId = _int(r, 'id');
      final feedUrl = feedUrlById[_int(r, 'feed')];
      if (feedUrl == null || !pending.containsKey(feedUrl)) continue;
      final media = mediaByItem[itemId] ?? mediaById[_int(r, 'media')];
      final audio = media == null ? '' : _str(media, 'download_url');
      if (audio.isEmpty) {
        report.skippedEpisodes++;
        continue;
      }
      var guid = _str(r, 'item_identifier');
      if (guid.isEmpty) guid = audio; // same fallback the feed parser uses
      final chapters = chaptersByItem[itemId] ?? const <Chapter>[];
      final episode = Episode(
        feedUrl: feedUrl,
        guid: guid,
        title: _str(r, 'title'),
        description: _str(r, 'description'),
        audioUrl: audio,
        published: _int(r, 'pubDate'),
        durationMs: _int(media!, 'duration'),
        imageUrl: _str(r, 'image_url'),
        link: _str(r, 'link'),
        fileSize: _int(media, 'filesize'),
        mimeType: _str(media, 'mime_type'),
        chapters: chapters,
      );
      pending[feedUrl]!.$2.add(episode);
      idByItem[itemId] = episode.id;
      report.episodes++;
      report.chapters += chapters.length;

      final read = _int(r, 'read');
      final position = _int(media, 'position');
      final completed = _int(media, 'playback_completion_date');
      final lastPlayed = _int(media, 'last_played_time');
      final played = read == 1;
      if (played || position > 0 || completed > 0 || lastPlayed > 0) {
        final when = completed > lastPlayed ? completed : lastPlayed;
        progressById[episode.id] = Progress(
          positionMs: played ? 0 : position,
          durationMs: _int(media, 'duration'),
          played: played,
          lastPlayedAt: when,
          // 1, not 0: loses to any real progress already here or on other devices.
          updatedAt: when > 0 ? when : 1,
        );
        if (played) report.played++;
        if (!played && position > 0) report.inProgress++;
        if (when > 0) report.history++;
      }
    }

    // Apply everything in one go ---------------------------------------------
    for (final entry in pending.values) {
      lib.importPodcast(entry.$1, entry.$2);
    }
    progressById.forEach(lib.importProgress);

    if (tables.contains('Queue')) {
      final ids = [
        for (final r in db.select('SELECT feeditem FROM Queue ORDER BY id ASC'))
          if (idByItem[_int(r, 'feeditem')] != null) idByItem[_int(r, 'feeditem')]!,
      ];
      report.queued = lib.importQueue(ids);
    }
    if (tables.contains('Favorites')) {
      for (final r in db.select('SELECT feeditem FROM Favorites')) {
        final id = idByItem[_int(r, 'feeditem')];
        if (id != null && lib.importFavorite(id)) report.favorites++;
      }
    }
    lib.finishImport();
  } finally {
    db.close();
  }
  return report;
}
