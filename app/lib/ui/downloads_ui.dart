import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'paged.dart';

/// The little status icon for an episode: not downloaded, waiting, downloading with progress,
/// failed (click to retry) or downloaded.
class DownloadIcon extends StatelessWidget {
  const DownloadIcon(this.episode, {super.key, this.size = 16, this.color});
  final Episode episode;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final info = dm.infoOf(episode.id);
    final c = color ?? Theme.of(context).iconTheme.color;

    Widget button(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      Color? tint,
    }) => InstantIconButton(
      icon: icon,
      size: size,
      tooltip: tip,
      color: tint ?? c,
      onTap: onTap,
    );

    switch (info?.state) {
      case DownloadState.done:
        return button(Icons.offline_pin, 'Downloaded', null);
      case DownloadState.downloading:
        return InstantIconButton(
          size: size,
          tooltip: info!.fraction == null
              ? 'Downloading… click to cancel'
              : 'Downloading ${(info.fraction! * 100).round()}%… click to cancel',
          onTap: () => dm.cancel(episode.id),
          child: SizedBox(
            width: size - 2,
            height: size - 2,
            child: CircularProgressIndicator(
              value: info.fraction,
              strokeWidth: 2,
              color: c,
            ),
          ),
        );
      case DownloadState.queued:
        return button(
          Icons.hourglass_empty,
          info!.error ?? 'Waiting to download… click to cancel',
          () => dm.cancel(episode.id),
        );
      case DownloadState.failed:
        return button(
          Icons.error_outline,
          'Failed: ${info!.error}. Click to retry',
          () => dm.retry(episode.id),
          tint: Theme.of(context).colorScheme.error,
        );
      case null:
        return button(
          Icons.cloud_download_outlined,
          'Download',
          () => dm.download(episode),
        );
    }
  }
}

/// Everything downloaded or downloading, with progress, size and clean-up buttons.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final lib = context.watch<Library>();
    final player = context.read<PlayerController>();
    final ids = dm.allIds;
    final theme = Theme.of(context);

    Future<void> confirmAndDeleteAll() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete all downloads?'),
          content: Text(
            'This frees ${fmtBytes(dm.totalBytes)} on this device. Episodes stay in your library and can be streamed or downloaded again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete all'),
            ),
          ],
        ),
      );
      if (ok == true) await dm.deleteAll();
    }

    Widget rowFor(BuildContext c, String id) {
      final e = lib.episodes[id];
      final info = dm.infoOf(id);
      if (e == null || info == null) {
        return const SizedBox.shrink();
      }
      final done = info.state == DownloadState.done;
      final status = switch (info.state) {
        DownloadState.done => fmtBytes(info.bytes),
        DownloadState.downloading =>
          info.total > 0
              ? '${fmtBytes(info.bytes)} of ${fmtBytes(info.total)}'
              : fmtBytes(info.bytes),
        DownloadState.queued => info.error ?? 'Waiting',
        DownloadState.failed => 'Failed: ${info.error}',
      };
      return ListTile(
        dense: true,
        leading: Art(e.imageUrl, size: 40, radius: 3),
        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${lib.podcastTitle(e.feedUrl)} · $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: info.state == DownloadState.failed
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            if (info.state == DownloadState.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(
                  value: info.fraction,
                  minHeight: 3,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done)
              IconButton(
                tooltip: 'Play',
                icon: const Icon(Icons.play_arrow),
                onPressed: () => player.play(e),
              ),
            if (info.state == DownloadState.failed)
              IconButton(
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh),
                onPressed: () => dm.retry(id),
              ),
            if (!done && info.state != DownloadState.failed)
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: () => dm.cancel(id),
              ),
            if (done || info.state == DownloadState.failed)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => dm.delete(id),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Downloads', style: theme.textTheme.titleLarge),
                    Text(
                      '${dm.doneCount} downloaded · ${fmtBytes(dm.totalBytes)}'
                      '${dm.activeIds.isNotEmpty ? ' · ${dm.activeIds.length} downloading' : ''}'
                      '${dm.queuedIds.isNotEmpty ? ' · ${dm.queuedIds.length} waiting' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: dm.activeIds.isEmpty && dm.queuedIds.isEmpty
                    ? null
                    : dm.cancelAll,
                child: const Text('Cancel All'),
              ),
              TextButton(
                onPressed: dm.doneIds.any((id) => lib.progressOf(id).played)
                    ? () async {
                        final n = await dm.deletePlayed();
                        if (context.mounted) {
                          showSnack(context, 'Deleted $n played');
                        }
                      }
                    : null,
                child: const Text('Delete Played'),
              ),
              TextButton(
                onPressed: ids.isEmpty ? null : confirmAndDeleteAll,
                child: const Text('Delete All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ids.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nothing downloaded yet.\nUse the cloud icon on an episode, or turn on automatic downloads in Settings.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : (lib.einkMode
                    ? PagedList<String>(
                        items: ids,
                        itemExtent: 84,
                        itemBuilder: (c, id) => rowFor(c, id),
                      )
                    : ListView.builder(
                        itemCount: ids.length,
                        itemBuilder: (c, i) => rowFor(c, ids[i]),
                      )),
        ),
      ],
    );
  }
}

/// How much you have listened to, overall and per podcast.
class StatsView extends StatelessWidget {
  const StatsView({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final st = lib.stats();
    final theme = Theme.of(context);
    final top = st.perPodcast.isEmpty
        ? Duration.zero
        : st.perPodcast.first.listened;

    Widget tile(String value, String label) => Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    // E-ink never scrolls: the same numbers as plain rows, paged.
    if (lib.einkMode) {
      final summary = <(String, String)>[
        ('Listened', fmtLong(st.listened, zero: '0 m')),
        ('Episodes played', '${st.played}'),
        ('In progress', '${st.inProgress}'),
        ('Unplayed', '${lib.unplayedCount}'),
        ('Library length', fmtLong(st.length, zero: '0 m')),
        (
          'In Up Next',
          '${lib.queue.length} · ${fmtLong(lib.queueTotalLength, zero: '0 m')}',
        ),
        ('Downloaded', '${dm.doneCount} · ${fmtBytes(dm.totalBytes)}'),
      ];
      final rows = <Widget>[
        for (final r in summary)
          ListTile(
            dense: true,
            title: Text(r.$1),
            trailing: Text(
              r.$2,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        for (final p in st.perPodcast)
          ListTile(
            dense: true,
            title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${fmtLong(p.listened, zero: '0 m')} listened · ${p.played} of ${p.episodes} played',
            ),
          ),
      ];
      return PagedList<Widget>(
        items: rows,
        itemExtent: 64,
        itemBuilder: (c, w) => w,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Statistics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Listening time is estimated from your progress: finished episodes count in full, started ones count up to where you stopped.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            tile(fmtLong(st.listened, zero: '0 m'), 'listened'),
            tile('${st.played}', 'episodes played'),
            tile('${st.inProgress}', 'in progress'),
            tile('${lib.unplayedCount}', 'unplayed'),
            tile(fmtLong(st.length, zero: '0 m'), 'total length of library'),
            tile(
              '${lib.queue.length}',
              'in Up Next (${fmtLong(lib.queueTotalLength, zero: '0 m')})',
            ),
            tile(fmtBytes(dm.totalBytes), 'downloaded (${dm.doneCount})'),
          ],
        ),
        const SizedBox(height: 20),
        Text('By podcast', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        if (st.perPodcast.isEmpty)
          Text(
            'Subscribe to a podcast to see numbers here.',
            style: theme.textTheme.bodySmall,
          ),
        for (final p in st.perPodcast)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${fmtLong(p.listened, zero: '0 m')} listened · ${p.played} of ${p.episodes} played',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: top > Duration.zero
                      ? p.listened.inMilliseconds / top.inMilliseconds
                      : 0,
                  minHeight: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
