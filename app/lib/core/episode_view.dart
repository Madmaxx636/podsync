import 'library.dart';
import 'models.dart';

/// How one podcast's episode list is sorted and filtered. Both live in the podcast's own record,
/// so they sync like its other settings.
class EpisodeView {
  /// Filter keys, each a pair: required `true` means the first label (Played), `false` the
  /// second (Not played). A key that is absent is not filtered on.
  static const filterPairs = <(String, String, String)>[
    ('played', 'Played', 'Not played'),
    ('paused', 'Paused', 'Not paused'),
    ('favorite', 'Is favorite', 'Not favorite'),
    ('hasMedia', 'Has media', 'No media'),
    ('queued', 'Queued', 'Not queued'),
    ('downloaded', 'Downloaded', 'Not downloaded'),
  ];

  /// '' = follow the global order, else key + 'Asc' / 'Desc'.
  static String sortOf(Podcast p) => (p.extra['epSort'] as String?) ?? '';

  static Map<String, bool> filterOf(Podcast p) {
    final raw = p.extra['epFilter'];
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.value is bool) '${e.key}': e.value as bool,
    };
  }

  static bool isFiltered(Podcast p) => filterOf(p).isNotEmpty;

  /// "Not played, Downloaded" for the settings row.
  static String filterSummary(Podcast p) {
    final f = filterOf(p);
    if (f.isEmpty) return 'Show all episodes';
    return [
      for (final (key, yes, no) in filterPairs)
        if (f.containsKey(key)) f[key]! ? yes : no,
    ].join(', ');
  }

  static String sortLabel(String sort) => switch (sort) {
    'dateAsc' => 'Date, oldest first',
    'dateDesc' => 'Date, newest first',
    'titleAsc' => 'Episode title, A to Z',
    'titleDesc' => 'Episode title, Z to A',
    'durationAsc' => 'Duration, shortest first',
    'durationDesc' => 'Duration, longest first',
    _ => 'Global default',
  };

  /// This podcast's episodes with its own filter and sort order applied.
  static List<Episode> of(
    Library lib,
    String feedUrl, {
    required bool Function(String id) downloaded,
  }) {
    final p = lib.podcasts[feedUrl];
    final eps = lib.episodesOf(feedUrl);
    if (p == null) return eps;

    final f = filterOf(p);
    bool keep(Episode e) {
      final pr = lib.progressOf(e.id);
      final facts = <String, bool>{
        'played': pr.played,
        'paused': !pr.played && pr.positionMs > 0,
        'favorite': lib.isFavorite(e.id),
        'hasMedia': e.audioUrl.isNotEmpty,
        'queued': lib.queue.contains(e.id),
        'downloaded': downloaded(e.id),
      };
      for (final entry in f.entries) {
        if (facts[entry.key] != null && facts[entry.key] != entry.value) {
          return false;
        }
      }
      return true;
    }

    final shown = f.isEmpty ? eps : eps.where(keep).toList();
    final sort = sortOf(p);
    if (sort.isEmpty) return shown;
    final asc = sort.endsWith('Asc');
    int cmp(Episode a, Episode b) =>
        switch (sort.replaceAll(RegExp(r'(Asc|Desc)$'), '')) {
          'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          'duration' => a.durationMs.compareTo(b.durationMs),
          _ => a.published.compareTo(b.published),
        };
    final sorted = [...shown]..sort((a, b) => asc ? cmp(a, b) : cmp(b, a));
    return sorted;
  }
}
