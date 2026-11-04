import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'downloads_ui.dart';
import 'pal.dart';

/// The info pane on the right: artwork, details, notes and chapters of the selected
/// episode, or of whatever is playing when nothing is selected.
class EpisodeDetailPane extends StatelessWidget {
  const EpisodeDetailPane({
    super.key,
    required this.episode,
    required this.onGoToPodcast,
  });
  final Episode? episode;
  final ValueChanged<String> onGoToPodcast;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.watch<PlayerController>();
    final pal = Pal.of(context);
    final e = episode ?? player.current;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: pal.sidebar,
        border: Border(left: BorderSide(color: pal.rule)),
      ),
      child: e == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Select an episode to see its details',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted),
                ),
              ),
            )
          : _content(context, lib, player, pal, e),
    );
  }

  Widget _content(
    BuildContext context,
    Library lib,
    PlayerController player,
    Pal pal,
    Episode e,
  ) {
    final pr = lib.progressOf(e.id);
    final left = lib.remainingOf(e);
    final inQueue = lib.queue.contains(e.id);
    final meta = TextStyle(fontSize: 12, color: pal.muted);
    final isCurrent = player.current?.id == e.id;
    final dm = context.watch<DownloadManager>();
    final status = pr.played
        ? 'Played'
        : (pr.positionMs > 0 ? '${fmtLong(left)} left' : 'Unplayed');
    final saved = dm.isDownloaded(e.id)
        ? 'Downloaded, ${fmtBytes(dm.infoOf(e.id)!.bytes)}'
        : '';

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Center(
          child: Container(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Art(e.imageUrl, size: 200, radius: 0),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          e.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: pal.text,
          ),
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: () => onGoToPodcast(e.feedUrl),
          child: Text(
            lib.podcastTitle(e.feedUrl),
            style: TextStyle(fontSize: 13, color: pal.selected),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            fmtDate(e.published),
            if (e.durationMs > 0) fmtDurationMs(e.durationMs),
            status,
            saved,
          ].where((x) => x.isNotEmpty).join('  ·  '),
          style: meta,
        ),
        const SizedBox(height: 8),
        StarRating(
          value: lib.ratingOf(e.id),
          size: 20,
          color: const Color(0xFFE5A91B),
          emptyColor: pal.muted,
          onChanged: (v) => lib.setRatings([e.id], v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => isCurrent ? player.toggle() : player.play(e),
              icon: Icon(
                isCurrent && player.playing ? Icons.pause : Icons.play_arrow,
                size: 18,
              ),
              label: Text(isCurrent && player.playing ? 'Pause' : 'Play'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () =>
                  inQueue ? lib.removeFromQueue(e.id) : lib.enqueue(e.id),
              child: Text(inQueue ? 'Remove from Up Next' : 'Add to Up Next'),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: lib.isFavorite(e.id)
                  ? 'Remove from Favorites'
                  : 'Add to Favorites',
              icon: Icon(lib.isFavorite(e.id) ? Icons.star : Icons.star_border),
              onPressed: () => lib.setFavorite(e.id, !lib.isFavorite(e.id)),
            ),
            // Download / downloading / downloaded, with the same click behaviour as the table.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: DownloadIcon(e, size: 22),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Get Info',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showEpisodeInfo(context, e),
            ),
          ],
        ),
        if (e.chapters.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'CHAPTERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: pal.muted,
            ),
          ),
          for (final ch in e.chapters)
            InkWell(
              onTap: () async {
                if (!isCurrent) await player.play(e);
                await player.seek(Duration(milliseconds: ch.startMs));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        fmtDuration(Duration(milliseconds: ch.startMs)),
                        style: meta,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ch.title,
                        style: TextStyle(fontSize: 12, color: pal.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (e.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: pal.muted,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            e.description,
            style: TextStyle(fontSize: 12, color: pal.text),
          ),
        ],
      ],
    );
  }
}
