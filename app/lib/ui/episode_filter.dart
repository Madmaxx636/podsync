import 'package:flutter/material.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';

/// Which episodes an episode list shows, like AntennaPod's and Kasts' filters.
enum EpisodeFilter { all, unplayed, downloaded, queued, favorites }

const episodeFilterLabels = {
  EpisodeFilter.all: 'All',
  EpisodeFilter.unplayed: 'Unplayed',
  EpisodeFilter.downloaded: 'Downloaded',
  EpisodeFilter.queued: 'In Up Next',
  EpisodeFilter.favorites: 'Favorites',
};

bool episodeMatches(
  EpisodeFilter f,
  Episode e,
  Library lib,
  DownloadManager dm,
) => switch (f) {
  EpisodeFilter.all => true,
  EpisodeFilter.unplayed => !lib.progressOf(e.id).played,
  EpisodeFilter.downloaded => dm.isDownloaded(e.id),
  EpisodeFilter.queued => lib.queue.contains(e.id),
  EpisodeFilter.favorites => lib.isFavorite(e.id),
};

List<Episode> filterEpisodes(
  EpisodeFilter f,
  List<Episode> eps,
  Library lib,
  DownloadManager dm,
) => f == EpisodeFilter.all
    ? eps
    : eps.where((e) => episodeMatches(f, e, lib, dm)).toList();

/// A row of chips with a count on each, to pick the filter.
class EpisodeFilterBar extends StatelessWidget {
  const EpisodeFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.episodes,
    required this.lib,
    required this.dm,
    this.dense = true,
  });
  final EpisodeFilter value;
  final ValueChanged<EpisodeFilter> onChanged;
  final List<Episode> episodes; // the unfiltered list, for the counts
  final Library lib;
  final DownloadManager dm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            for (final f in EpisodeFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  visualDensity: dense ? VisualDensity.compact : null,
                  showCheckmark: false,
                  selected: value == f,
                  label: Text(
                    f == EpisodeFilter.all
                        ? '${episodeFilterLabels[f]} (${episodes.length})'
                        : '${episodeFilterLabels[f]} (${episodes.where((e) => episodeMatches(f, e, lib, dm)).length})',
                  ),
                  onSelected: (_) => onChanged(f),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
