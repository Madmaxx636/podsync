import 'package:flutter/material.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import 'pal.dart';

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

/// The filter as one joined segmented control with a count on each segment, like iTunes' own.
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
    final pal = Pal.of(context);
    final filters = EpisodeFilter.values;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: pal.rule),
              borderRadius: BorderRadius.circular(5),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < filters.length; i++) ...[
                    if (i > 0) VerticalDivider(width: 1, color: pal.rule),
                    InkWell(
                      onTap: () => onChanged(filters[i]),
                      child: Container(
                        color: value == filters[i] ? pal.selected : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Text(
                          filters[i] == EpisodeFilter.all
                              ? '${episodeFilterLabels[filters[i]]} (${episodes.length})'
                              : '${episodeFilterLabels[filters[i]]} (${episodes.where((e) => episodeMatches(filters[i], e, lib, dm)).length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: value == filters[i]
                                ? Colors.white
                                : pal.text,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
