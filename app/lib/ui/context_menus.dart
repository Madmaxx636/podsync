import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'podcast_settings.dart';

/// Opens a popup menu at the pointer and returns the chosen value.
Future<String?> _menuAt(
  BuildContext context,
  Offset at,
  List<PopupMenuEntry<String>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(at, at),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// iTunes-style right-click menu for one or more selected episodes.
Future<void> showEpisodeMenu(
  BuildContext context,
  Offset at,
  List<Episode> eps, {
  bool queueView = false,
  bool historyView = false,
  ValueChanged<String>? onGoToPodcast,
}) async {
  if (eps.isEmpty) return;
  final lib = context.read<Library>();
  final player = context.read<PlayerController>();
  final dm = context.read<DownloadManager>();
  final ids = [for (final e in eps) e.id];
  final one = eps.length == 1;
  final allQueued = ids.every(lib.queue.contains);
  final allPlayed = ids.every((id) => lib.progressOf(id).played);
  final allFav = ids.every(lib.isFavorite);
  final allDownloaded = ids.every(dm.isDownloaded);
  final allBusy = ids.every(dm.isBusy);

  final choice = await _menuAt(context, at, [
    PopupMenuItem(
      value: 'play',
      child: Text(one ? 'Play' : 'Play ${eps.length} Episodes'),
    ),
    const PopupMenuItem(value: 'next', child: Text('Play Next')),
    PopupMenuItem(
      value: 'queue',
      child: Text(allQueued ? 'Remove from Up Next' : 'Add to Up Next'),
    ),
    if (queueView) ...[
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'top', child: Text('Move to Top of Up Next')),
      const PopupMenuItem(value: 'up', child: Text('Move Up')),
      const PopupMenuItem(value: 'down', child: Text('Move Down')),
      const PopupMenuItem(
        value: 'bottom',
        child: Text('Move to Bottom of Up Next'),
      ),
    ],
    const PopupMenuDivider(),
    PopupMenuItem(
      value: allDownloaded ? 'undownload' : (allBusy ? 'canceldl' : 'download'),
      child: Text(
        allDownloaded
            ? 'Remove Download'
            : (allBusy
                  ? 'Cancel Download'
                  : (one ? 'Download' : 'Download ${eps.length} Episodes')),
      ),
    ),
    _ratingItem(ids, lib),
    PopupMenuItem(
      value: 'played',
      child: Text(allPlayed ? 'Mark as Unplayed' : 'Mark as Played'),
    ),
    PopupMenuItem(
      value: 'fav',
      child: Text(allFav ? 'Remove from Favorites' : 'Add to Favorites'),
    ),
    if (historyView)
      const PopupMenuItem(
        value: 'history',
        child: Text('Remove from Recently Played'),
      ),
    const PopupMenuDivider(),
    if (one) const PopupMenuItem(value: 'info', child: Text('Get Info')),
    if (one && onGoToPodcast != null)
      const PopupMenuItem(value: 'podcast', child: Text('Go to Podcast')),
    PopupMenuItem(
      value: 'copy',
      child: Text(one ? 'Copy Episode Link' : 'Copy Episode Links'),
    ),
    if (queueView) ...[
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'clear', child: Text('Clear Up Next')),
    ],
  ]);
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'play':
      // The first starts now; any others line up right behind it.
      if (!one) lib.enqueueAll(ids.skip(1).toList(), next: true);
      player.play(eps.first);
    case 'next':
      lib.enqueueAll(ids, next: true);
    case 'queue':
      if (allQueued) {
        lib.removeAllFromQueue(ids);
        showQueueUndo(context, lib, 'Removed from Up Next');
      } else {
        lib.enqueueAll(ids.where((id) => !lib.queue.contains(id)).toList());
      }
    case 'top':
      lib.moveInQueue(ids, toTop: true);
    case 'bottom':
      lib.moveInQueue(ids, toTop: false);
    case 'up':
      lib.nudgeInQueue(ids, -1);
    case 'down':
      lib.nudgeInQueue(ids, 1);
    case 'download':
      dm.downloadAll(eps);
    case 'canceldl':
      for (final id in ids) {
        dm.cancel(id);
      }
    case 'undownload':
      for (final id in ids) {
        await dm.delete(id);
      }
    case 'played':
      lib.markAllPlayed(ids, !allPlayed);
    case 'fav':
      lib.setFavorites(ids, !allFav);
    case 'history':
      lib.removeFromHistory(ids);
    case 'info':
      showEpisodeInfo(context, eps.first);
    case 'podcast':
      onGoToPodcast!(eps.first.feedUrl);
    case 'copy':
      await Clipboard.setData(
        ClipboardData(
          text: eps
              .map((e) => e.link.isNotEmpty ? e.link : e.audioUrl)
              .join('\n'),
        ),
      );
      if (context.mounted) {
        showSnack(context, one ? 'Link copied' : 'Links copied');
      }
    case 'clear':
      lib.clearQueue();
      showQueueUndo(context, lib, 'Up Next cleared');
  }
}

/// A menu row with five stars. Not selectable itself; clicking a star rates and closes the menu.
PopupMenuEntry<String> _ratingItem(List<String> ids, Library lib) {
  final current = ids.map(lib.ratingOf).toSet().length == 1
      ? lib.ratingOf(ids.first)
      : 0;
  return PopupMenuItem<String>(
    enabled: false,
    child: Builder(
      builder: (context) => Row(
        children: [
          Text(
            'Rating',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const Spacer(),
          StarRating(
            value: current,
            size: 18,
            color: const Color(0xFFE5A91B),
            emptyColor: Theme.of(context).disabledColor,
            onChanged: (v) {
              lib.setRatings(ids, v);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}

/// iTunes-style right-click menu for a podcast (sidebar, grid or search result).
Future<void> showPodcastMenu(
  BuildContext context,
  Offset at,
  String feedUrl, {
  required ValueChanged<String> onOpen,
}) async {
  final lib = context.read<Library>();
  final dm = context.read<DownloadManager>();
  final subscribed = lib.isSubscribed(feedUrl);
  final eps = lib.episodesOf(feedUrl);
  final unplayed = eps.where((e) => !lib.progressOf(e.id).played).toList();
  final notDownloaded = unplayed
      .where((e) => !dm.isDownloaded(e.id) && !dm.isBusy(e.id))
      .toList();
  final downloaded = eps.where((e) => dm.isDownloaded(e.id)).toList();

  final choice = await _menuAt(context, at, [
    const PopupMenuItem(value: 'open', child: Text('Go to Podcast')),
    if (subscribed) ...[
      const PopupMenuItem(value: 'refresh', child: Text('Refresh Podcast')),
      PopupMenuItem(
        value: 'enqueue',
        enabled: unplayed.isNotEmpty,
        child: const Text('Add Unplayed to Up Next'),
      ),
      PopupMenuItem(
        value: 'played',
        enabled: unplayed.isNotEmpty,
        child: const Text('Mark All as Played'),
      ),
      PopupMenuItem(
        value: 'unplayed',
        enabled: eps.any((e) => lib.progressOf(e.id).played),
        child: const Text('Mark All as Unplayed'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'download',
        enabled: notDownloaded.isNotEmpty,
        child: Text(
          notDownloaded.isEmpty
              ? 'Download Unplayed Episodes'
              : 'Download ${notDownloaded.length} Unplayed Episodes',
        ),
      ),
      PopupMenuItem(
        value: 'undownload',
        enabled: downloaded.isNotEmpty,
        child: Text(
          downloaded.isEmpty
              ? 'Remove Downloads'
              : 'Remove ${downloaded.length} Downloads',
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'info', child: Text('Get Info')),
    ],
    const PopupMenuItem(value: 'copy', child: Text('Copy Feed URL')),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'subscribe',
      child: Text(subscribed ? 'Unsubscribe' : 'Subscribe'),
    ),
  ]);
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'open':
      onOpen(feedUrl);
    case 'refresh':
      try {
        await lib.refreshFeed(feedUrl);
      } catch (e) {
        if (context.mounted) showSnack(context, 'Could not refresh: $e');
      }
    case 'enqueue':
      // Oldest first, so the queue plays them in the order they were released.
      lib.enqueueAll(
        ([...unplayed]..sort((a, b) => a.published.compareTo(b.published)))
            .where((e) => !lib.queue.contains(e.id))
            .map((e) => e.id)
            .toList(),
      );
    case 'played':
      lib.markAllPlayed(eps.map((e) => e.id), true);
    case 'unplayed':
      lib.markAllPlayed(eps.map((e) => e.id), false);
    case 'download':
      // A big batch deserves a heads-up.
      var go = notDownloaded.length <= 20;
      if (!go) {
        go =
            await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Download ${notDownloaded.length} episodes?'),
                content: const Text('This can use a lot of storage and data.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Download'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (go) dm.downloadAll(notDownloaded);
    case 'undownload':
      for (final e in downloaded) {
        await dm.delete(e.id);
      }
    case 'info':
      showPodcastSettings(context, feedUrl);
    case 'copy':
      await Clipboard.setData(ClipboardData(text: feedUrl));
      if (context.mounted) showSnack(context, 'Feed URL copied');
    case 'subscribe':
      if (subscribed) {
        lib.unsubscribe(feedUrl);
      } else {
        try {
          await lib.subscribe(feedUrl);
        } catch (e) {
          if (context.mounted) showSnack(context, 'Could not subscribe: $e');
        }
      }
  }
}

/// "Get Info" for an episode.
void showEpisodeInfo(BuildContext context, Episode e) {
  final lib = context.read<Library>();
  final pr = lib.progressOf(e.id);
  String size(int bytes) =>
      bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  final rows = <(String, String)>[
    ('Podcast', lib.podcastTitle(e.feedUrl)),
    ('Released', fmtDate(e.published)),
    ('Length', fmtDurationMs(e.durationMs)),
    ('Size', size(e.fileSize)),
    ('Format', e.mimeType),
    (
      'Status',
      pr.played
          ? 'Played'
          : (pr.positionMs > 0
                ? 'Played to ${fmtDurationMs(pr.positionMs)}'
                : 'Unplayed'),
    ),
    if (pr.lastPlayedAt > 0) ('Last played', fmtDate(pr.lastPlayedAt)),
    ('Audio', e.audioUrl),
    if (e.link.isNotEmpty) ('Link', e.link),
  ].where((r) => r.$2.isNotEmpty).toList();

  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(e.title, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          r.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(child: SelectableText(r.$2)),
                    ],
                  ),
                ),
              if (e.chapters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${e.chapters.length} chapters',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final ch in e.chapters)
                  Text(
                    '${fmtDuration(Duration(milliseconds: ch.startMs))}  ${ch.title}',
                  ),
              ],
              if (e.description.isNotEmpty) ...[
                const Divider(height: 24),
                SelectableText(e.description),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
