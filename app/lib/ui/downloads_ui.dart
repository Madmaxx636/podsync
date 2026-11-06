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

/// How much you have listened to, overall and per podcast: three pages (Subscriptions, Years,
/// Downloads) with a gauge or bar chart on top and a ranked list under it.
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  int _tab = 0;

  static const _slices = [
    Color(0xFF3B7DDD),
    Color(0xFFE5222D),
    Color(0xFFFF9800),
    Color(0xFF8E8E93),
  ];

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final st = lib.stats();
    final theme = Theme.of(context);

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

    final body = switch (_tab) {
      1 => _years(context, st),
      2 => _downloads(context, lib, dm),
      _ => _subscriptions(context, lib, st),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statistics', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Subscriptions')),
                    ButtonSegment(value: 1, label: Text('Years')),
                    ButtonSegment(value: 2, label: Text('Downloads')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// A row of a ranked list: cover-less title, a figure and a bar relative to the biggest.
  Widget _rank(
    BuildContext context,
    String title,
    String figure,
    double share,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(figure, style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 5,
              color: color,
              backgroundColor: theme.dividerColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Container(
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
  }

  Widget _subscriptions(BuildContext context, Library lib, LibraryStats st) {
    final theme = Theme.of(context);
    final list = st.perPodcast;
    final total = st.listened.inMilliseconds;
    // Three biggest podcasts get their own colour, everyone else shares the grey one.
    final parts = <double>[
      for (var i = 0; i < 3; i++)
        i < list.length ? list[i].listened.inMilliseconds.toDouble() : 0,
    ];
    parts.add(
      (total - parts.fold(0.0, (a, b) => a + b))
          .clamp(0.0, double.infinity)
          .toDouble(),
    );
    final top = list.isEmpty ? 1 : list.first.listened.inMilliseconds;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _Gauge(
              parts: parts,
              colors: _slices,
              big: fmtLong(st.listened, zero: '0 m'),
              small: 'Listened in total',
            ),
          ),
        ),
        const Divider(height: 28),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _tile(context, '${st.played}', 'episodes played'),
            _tile(context, '${st.inProgress}', 'in progress'),
            _tile(context, '${lib.unplayedCount}', 'unplayed'),
            _tile(
              context,
              fmtLong(st.length, zero: '0 m'),
              'total length of library',
            ),
            _tile(
              context,
              '${lib.queue.length}',
              'in Up Next (${fmtLong(lib.queueTotalLength, zero: '0 m')})',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Listening time is estimated from your progress: finished episodes count in full, started ones count up to where you stopped.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Text(
            'Subscribe to a podcast to see numbers here.',
            style: theme.textTheme.bodySmall,
          ),
        for (var i = 0; i < list.length; i++)
          _rank(
            context,
            list[i].title,
            '${fmtLong(list[i].listened, zero: '0 m')} · ${list[i].played} of ${list[i].episodes} played',
            top > 0 ? list[i].listened.inMilliseconds / top : 0,
            _slices[i < 3 ? i : 3],
          ),
      ],
    );
  }

  Widget _years(BuildContext context, LibraryStats st) {
    final theme = Theme.of(context);
    if (st.byMonth.isEmpty) {
      return Center(
        child: Text(
          'Nothing played yet. Listening time per month shows up here.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final keys = st.byMonth.keys.toList()..sort();
    final first = keys.first, last = keys.last;
    final months = [for (var k = first; k <= last; k++) k];
    final byYear = <int, Duration>{};
    for (final e in st.byMonth.entries) {
      byYear.update(e.key ~/ 12, (v) => v + e.value, ifAbsent: () => e.value);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    const palette = [
      Color(0xFF0A78C8),
      Color(0xFF9C27B0),
      Color(0xFFE5222D),
      Color(0xFFFF9800),
      Color(0xFF2E9E6B),
    ];
    Color yearColor(int y) => palette[(years.first - y) % palette.length];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 230,
          child: _MonthBars(
            months: months,
            hours: [
              for (final m in months) (st.byMonth[m]?.inMinutes ?? 0) / 60.0,
            ],
            colorOf: (m) => yearColor(m ~/ 12),
            textColor: theme.textTheme.bodySmall?.color ?? Colors.grey,
            ruleColor: theme.dividerColor,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Time played per month',
            style: theme.textTheme.titleSmall,
          ),
        ),
        const Divider(height: 28),
        for (final y in years)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(width: 10, height: 36, color: yearColor(y)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$y', style: theme.textTheme.titleMedium),
                    Text(
                      '${(byYear[y]!.inMinutes / 60).toStringAsFixed(1)} hours',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _downloads(BuildContext context, Library lib, DownloadManager dm) {
    final byFeed = <String, (int, int)>{};
    for (final id in dm.doneIds) {
      final e = lib.episodes[id];
      if (e == null) continue;
      final cur = byFeed[e.feedUrl] ?? (0, 0);
      byFeed[e.feedUrl] = (cur.$1 + (dm.infoOf(id)?.bytes ?? 0), cur.$2 + 1);
    }
    final rows = byFeed.entries.toList()
      ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final total = dm.totalBytes;
    final parts = <double>[
      for (var i = 0; i < 3; i++)
        i < rows.length ? rows[i].value.$1.toDouble() : 0,
    ];
    parts.add(
      (total - parts.fold(0.0, (a, b) => a + b))
          .clamp(0.0, double.infinity)
          .toDouble(),
    );
    final top = rows.isEmpty ? 1 : rows.first.value.$1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _Gauge(
              parts: parts,
              colors: _slices,
              big: fmtBytes(total),
              small: 'Total size of ${dm.doneCount} episodes on the device',
            ),
          ),
        ),
        const Divider(height: 28),
        if (rows.isEmpty)
          Text(
            'Nothing is downloaded.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var i = 0; i < rows.length; i++)
          _rank(
            context,
            lib.podcastTitle(rows[i].key),
            '${fmtBytes(rows[i].value.$1)} · ${rows[i].value.$2} episodes',
            top > 0 ? rows[i].value.$1 / top : 0,
            _slices[i < 3 ? i : 3],
          ),
      ],
    );
  }
}

/// A half-circle split into coloured shares with a figure and caption in the middle.
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.parts,
    required this.colors,
    required this.big,
    required this.small,
  });
  final List<double> parts;
  final List<Color> colors;
  final String big, small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 2.1,
      child: CustomPaint(
        painter: _GaugePainter(parts, colors, theme.dividerColor),
        child: Align(
          alignment: const Alignment(0, 0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                big,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(small, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.parts, this.colors, this.empty);
  final List<double> parts;
  final List<Color> colors;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.height * 0.07;
    final r = (size.width / 2 - stroke).clamp(0.0, size.height - stroke);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, r + stroke),
      radius: r,
    );
    final total = parts.fold(0.0, (a, b) => a + b);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      canvas.drawArc(rect, 3.14159, 3.14159, false, paint..color = empty);
      return;
    }
    const gap = 0.025; // radians between slices
    var a = 3.14159;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] <= 0) continue;
      final sweep = parts[i] / total * 3.14159;
      final draw = (sweep - gap).clamp(0.004, 4.0);
      canvas.drawArc(rect, a + gap / 2, draw, false, paint..color = colors[i]);
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.parts != parts || o.colors != colors || o.empty != empty;
}

/// Bars of hours per month, coloured by year, with 50 h style guide lines and year labels.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.months,
    required this.hours,
    required this.colorOf,
    required this.textColor,
    required this.ruleColor,
  });
  final List<int> months;
  final List<double> hours;
  final Color Function(int month) colorOf;
  final Color textColor, ruleColor;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _MonthBarsPainter(this), size: Size.infinite);
}

class _MonthBarsPainter extends CustomPainter {
  _MonthBarsPainter(this.w);
  final _MonthBars w;

  void _text(Canvas c, String t, Offset at, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontSize: 11, color: w.textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, right ? at - Offset(tp.width, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 22.0, top = 8.0;
    final plot = Rect.fromLTRB(left, top, size.width, size.height - bottom);
    final maxH = w.hours.fold(0.0, (a, b) => a > b ? a : b);
    // Guide lines every 50 hours (every 10 for a small total), up to a little over the tallest bar.
    final stepH = maxH <= 40 ? 10.0 : (maxH <= 120 ? 50.0 : 100.0);
    final ceiling =
        (maxH / stepH).ceil() * stepH + (maxH % stepH == 0 ? stepH : 0);
    final line = Paint()
      ..color = w.ruleColor
      ..strokeWidth = 1;
    for (var h = stepH; h <= ceiling; h += stepH) {
      final y = plot.bottom - h / ceiling * plot.height;
      for (var x = plot.left; x < plot.right; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), line);
      }
      _text(canvas, h.round().toString(), Offset(left - 6, y - 7), right: true);
    }
    final n = w.months.length;
    final slot = plot.width / n;
    for (var i = 0; i < n; i++) {
      final bh = w.hours[i] / ceiling * plot.height;
      canvas.drawRect(
        Rect.fromLTWH(
          plot.left + i * slot + 0.5,
          plot.bottom - bh,
          slot - 1,
          bh,
        ),
        Paint()..color = w.colorOf(w.months[i]),
      );
    }
    // Year labels under the first month of each year, with a small tick.
    for (var i = 0; i < n; i++) {
      final m = w.months[i];
      if (m % 12 == 0 || i == 0) {
        final x = plot.left + i * slot;
        canvas.drawLine(
          Offset(x, plot.bottom),
          Offset(x, plot.bottom + 6),
          line..strokeWidth = 1,
        );
        _text(canvas, '${m ~/ 12}', Offset(x + 6, plot.bottom + 5));
      }
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      line,
    );
  }

  @override
  bool shouldRepaint(_MonthBarsPainter o) => true;
}
