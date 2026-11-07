import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'downloads_ui.dart';
import 'pal.dart';
import 'zoom.dart';

/// The iTunes-style list of episodes. In Up Next ([queueMode]) it also shows the
/// play order, when each episode would start, and rows can be dragged into place.
class EpisodeTable extends StatefulWidget {
  const EpisodeTable({
    super.key,
    required this.episodes,
    this.showPodcastColumn = true,
    this.queueMode = false,
    this.keepOrder = false,
    this.historyView = false,
    this.canReorder = true,
    this.queueMarks = false,
    this.emptyText,
    this.onGoToPodcast,
    this.onFocusEpisode,
  });

  final List<Episode> episodes;
  final bool showPodcastColumn;
  final bool queueMode;
  final bool keepOrder; // show in the given order (history), no column sorting
  final bool historyView;
  final bool canReorder; // false while a search filter hides part of the queue
  final bool queueMarks; // a circle at the right of each row to put it in Up Next (My Podcasts)
  final String? emptyText;
  final ValueChanged<String>?
  onGoToPodcast; // "Go to Podcast" in the right-click menu
  final ValueChanged<Episode?>?
  onFocusEpisode; // the one selected episode, for the details pane

  @override
  State<EpisodeTable> createState() => _EpisodeTableState();
}

class _Col {
  const _Col(this.key, this.label, {this.width, this.flex = 0});
  final String key;
  final String label;
  final double? width;
  final int flex;
}

class _EpisodeTableState extends State<EpisodeTable> {
  String sortBy = 'date';
  bool? _asc; // null until the user clicks a header; then follows the "episode order" setting
  final Set<String> selected = {};
  final FocusNode _focus = FocusNode();
  String? _anchor; // where a shift-click range starts
  List<Episode> _shown = [];
  final Map<String, double> _dragging =
      {}; // widths while a column edge is being dragged
  double _avail = 0; // width of the table, so columns cannot be dragged past it
  static const _minName = 160.0, _minCol = 40.0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final s = lib.settings;
    final player = context.read<PlayerController>();
    final currentId = context.select<PlayerController, String?>(
      (p) => p.current?.id,
    );
    final asc = _asc ?? (sortBy == 'date' ? s.sortOldestFirst : true);
    final queue = widget.queueMode;
    // Up Next counts down as the episode plays: follow the player's position by the second.
    final livePos = context.select<PlayerController, int>(
      (p) => queue ? p.position.inSeconds : 0,
    );
    final fixedOrder = queue || widget.keepOrder;
    final present = {for (final e in widget.episodes) e.id};
    selected.removeWhere((id) => !present.contains(id));

    var eps = [...widget.episodes];
    if (!fixedOrder) {
      // Work the sort keys out once per episode, not on every comparison: with thousands of
      // episodes the comparisons run tens of thousands of times per sort.
      final names = sortBy == 'name'
          ? {for (final e in eps) e.id: e.title.toLowerCase()}
          : const <String, String>{};
      final podcastTitles = sortBy == 'podcast'
          ? <String, String>{}
          : const <String, String>{};
      if (sortBy == 'podcast') {
        for (final e in eps) {
          podcastTitles.putIfAbsent(
            e.feedUrl,
            () => lib.podcastTitle(e.feedUrl),
          );
        }
      }
      final ratings = sortBy == 'rating'
          ? {for (final e in eps) e.id: lib.ratingOf(e.id)}
          : const <String, int>{};
      // The Time column shows what is left for a half-played episode, so that is what it sorts by.
      final times = sortBy == 'time'
          ? {
              for (final e in eps)
                e.id: () {
                  final pr = lib.progressOf(e.id);
                  final left = lib.remainingOf(e);
                  return !pr.played && pr.positionMs > 0 && left > Duration.zero
                      ? left.inMilliseconds
                      : e.durationMs;
                }(),
            }
          : const <String, int>{};
      int primary(Episode a, Episode b) => switch (sortBy) {
        'name' => names[a.id]!.compareTo(names[b.id]!),
        'time' => times[a.id]!.compareTo(times[b.id]!),
        'podcast' => podcastTitles[a.feedUrl]!.compareTo(
          podcastTitles[b.feedUrl]!,
        ),
        'rating' => ratings[a.id]!.compareTo(ratings[b.id]!),
        _ => a.published.compareTo(b.published),
      };
      // Dart's sort is not stable, so equal rows (every episode of one podcast when sorting by
      // Podcast, say) would come out in any order and jump about. They always fall back to
      // newest first, then by title, whichever way the column runs.
      eps.sort((a, b) {
        final c = primary(a, b);
        if (c != 0) return asc ? c : -c;
        final byDate = b.published.compareTo(a.published);
        return byDate != 0 ? byDate : a.title.compareTo(b.title);
      });
    }
    _shown = eps;

    final showPodcast = widget.showPodcastColumn && s.colPodcast;
    // Every column but Name has a width you can drag; Name takes whatever is left.
    final saved = s.colWidthMap;
    double w(String key, double fallback) =>
        _dragging[key] ?? saved[key] ?? fallback;
    final cols = <_Col>[
      _Col('lead', '', width: queue ? 58 : 28),
      if (s.colDownload) const _Col('dl', '', width: 34),
      const _Col('name', 'Name', flex: 1),
      if (s.colTime) _Col('time', 'Time', width: w('time', 84)),
      if (queue && s.colStarts)
        _Col('starts', 'Starts in', width: w('starts', 96)),
      if (queue && s.colStartsAt)
        _Col('startsAt', 'Starts at', width: w('startsAt', 110)),
      if (queue && s.colEndsAt)
        _Col('endsAt', 'Ends at', width: w('endsAt', 110)),
      if (showPodcast) _Col('podcast', 'Podcast', width: w('podcast', 220)),
      if (s.colRating) _Col('rating', 'Rating', width: w('rating', 92)),
      if (s.colDate) _Col('date', 'Release Date', width: w('date', 128)),
      if (widget.queueMarks) const _Col('mark', '', width: 34),
      const _Col('play', '', width: 36),
    ];
    double othersWidth(String key) => [
      for (final c in cols)
        if (c.width != null && c.key != key) c.width!,
    ].fold(0.0, (a, b) => a + b);
    void commitWidths() {
      final all = {...saved, ..._dragging};
      _dragging.clear();
      lib.setSetting(
        'colWidths',
        all.entries.map((e) => '${e.key}=${e.value.round()}').join(','),
      );
    }

    // Time left per episode (the playing one from the player's live position) and when each
    // queued episode would start and end, for the Starts in / Starts at / Ends at columns.
    Duration leftOf(Episode e) {
      if (queue && e.id == currentId && livePos > 0) {
        final total = player.duration > Duration.zero
            ? player.duration
            : Duration(milliseconds: e.durationMs);
        final left = total - Duration(seconds: livePos);
        return left < Duration.zero ? Duration.zero : left;
      }
      return lib.remainingOf(e);
    }

    final starts = <String, Duration>{};
    final ends = <String, Duration>{};
    if (queue) {
      var ms = 0.0;
      for (final e in lib.queueEpisodes) {
        starts[e.id] = Duration(milliseconds: ms.round());
        ms += leftOf(e).inMilliseconds / lib.speedFor(e.feedUrl);
        ends[e.id] = Duration(milliseconds: ms.round());
      }
    }
    final now = DateTime.now();
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    String clock(Duration from) {
      final t = now.add(from);
      final label = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(t),
        alwaysUse24HourFormat: use24,
      );
      final today = DateTime(now.year, now.month, now.day);
      final days = DateTime(t.year, t.month, t.day).difference(today).inDays;
      if (days == 0) return label;
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days == 1 ? 'Tomorrow $label' : '${names[t.weekday - 1]} $label';
    }

    final queuePos = {for (var i = 0; i < eps.length; i++) eps[i].id: i + 1};

    Widget header(_Col c) {
      if (c.label.isEmpty) return SizedBox(width: c.width, child: null);
      final active = sortBy == c.key && !fixedOrder;
      final child = InkWell(
        onTap: c.key == 'play' || fixedOrder
            ? null
            : () => _headerTap(c.key, asc),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  c.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: pal.text,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (active)
                Icon(
                  asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 16,
                  color: pal.text,
                ),
            ],
          ),
        ),
      );
      if (c.width == null) return Expanded(flex: c.flex, child: child);
      // The edge between this column and the one before it: drag to resize, double-click to reset.
      final handle = Positioned(
        left: -3,
        top: 0,
        bottom: 0,
        width: 7,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () {
              _dragging.clear();
              final rest = {...saved}..remove(c.key);
              lib.setSetting(
                'colWidths',
                rest.entries
                    .map((e) => '${e.key}=${e.value.round()}')
                    .join(','),
              );
            },
            onHorizontalDragUpdate: (d) {
              final room = _avail - othersWidth(c.key) - _minName;
              setState(
                () => _dragging[c.key] = (c.width! - d.delta.dx).clamp(
                  _minCol,
                  room < _minCol ? _minCol : room,
                ),
              );
            },
            onHorizontalDragEnd: (_) => commitWidths(),
            child: Center(child: Container(width: 1, color: pal.rule)),
          ),
        ),
      );
      return SizedBox(
        width: c.width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: child),
            handle,
          ],
        ),
      );
    }

    Widget cell(_Col c, Widget child) => c.width != null
        ? SizedBox(width: c.width, child: child)
        : Expanded(flex: c.flex, child: child);

    Widget row(BuildContext context, Episode e, int i) {
      final pr = lib.progressOf(e.id);
      final sel = selected.contains(e.id);
      final playing = currentId == e.id;
      final fg = sel ? Colors.white : (pr.played ? pal.muted : pal.text);
      final st = TextStyle(
        fontSize: 13,
        color: fg,
        fontWeight: playing ? FontWeight.bold : null,
      );
      const pad = EdgeInsets.symmetric(horizontal: 6);
      final reorderable = queue && widget.canReorder;

      Widget content(_Col c) {
        switch (c.key) {
          case 'lead':
            if (queue) {
              final number = playing
                  ? Icon(Icons.volume_up, size: 14, color: fg)
                  : Text(
                      '${queuePos[e.id]}',
                      style: st.copyWith(
                        fontSize: 11,
                        color: sel ? Colors.white : pal.muted,
                      ),
                    );
              final handle = Icon(
                Icons.drag_indicator,
                size: 16,
                color: sel ? Colors.white70 : pal.muted,
              );
              return Row(
                children: [
                  const SizedBox(width: 4),
                  reorderable
                      ? ReorderableDragStartListener(
                          index: i,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: handle,
                          ),
                        )
                      : const SizedBox(width: 16),
                  Expanded(child: Center(child: number)),
                ],
              );
            }
            return Center(
              child: playing
                  ? Icon(Icons.volume_up, size: 14, color: fg)
                  : (!pr.played && pr.positionMs == 0
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: sel ? Colors.white : pal.selected,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null),
            );
          case 'dl':
            return Center(child: DownloadIcon(e, size: 15, color: fg));
          case 'mark':
            final queued = lib.queue.contains(e.id);
            return InstantIconButton(
              icon: queued ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17,
              color: fg,
              tooltip: queued
                  ? 'In Up Next. Click to remove'
                  : 'Add to Up Next',
              onTap: () =>
                  queued ? lib.removeFromQueue(e.id) : lib.enqueue(e.id),
              width: 34,
            );
          case 'name':
            return Padding(
              padding: pad,
              child: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st,
              ),
            );
          case 'time':
            final left = leftOf(e);
            final partly =
                !pr.played &&
                (pr.positionMs > 0 || (queue && playing && livePos > 0)) &&
                left > Duration.zero;
            return Padding(
              padding: pad,
              child: Text(
                partly
                    ? '${fmtDuration(left)} left'
                    : fmtDurationMs(e.durationMs),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st,
              ),
            );
          case 'starts':
            final at = starts[e.id];
            return Padding(
              padding: pad,
              child: Text(
                at == null
                    ? ''
                    : (i == 0 && playing
                          ? 'Playing'
                          : fmtLong(at, zero: 'Next')),
                style: st,
              ),
            );
          case 'startsAt':
          case 'endsAt':
            final at = (c.key == 'startsAt' ? starts : ends)[e.id];
            return Padding(
              padding: pad,
              child: Text(
                at == null || (c.key == 'startsAt' && i == 0 && playing)
                    ? ''
                    : clock(at),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st,
              ),
            );
          case 'podcast':
            return Padding(
              padding: pad,
              child: Text(
                lib.podcastTitle(e.feedUrl),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st,
              ),
            );
          case 'rating':
            return Padding(
              padding: pad,
              child: StarRating(
                value: lib.ratingOf(e.id),
                onChanged: (v) => lib.setRatings(
                  selected.contains(e.id) ? selected : [e.id],
                  v,
                ),
                color: sel ? Colors.white : const Color(0xFFE5A91B),
                emptyColor: sel
                    ? Colors.white54
                    : pal.muted.withValues(alpha: 0.5),
              ),
            );
          case 'date':
            return Padding(
              padding: pad,
              child: Text(fmtDate(e.published), style: st),
            );
          default:
            return InstantIconButton(
              icon: Icons.play_circle_outline,
              size: 16,
              color: fg,
              tooltip: 'Play',
              onTap: () => player.play(e),
              width: 36,
            );
        }
      }

      return GestureDetector(
        key: ValueKey(e.id),
        onSecondaryTapDown: (d) {
          // Right-clicking something outside the selection selects just that row first.
          if (!selected.contains(e.id)) {
            setState(() => _select(e, i));
            _notifyFocus();
          }
          showEpisodeMenu(
            context,
            Zoom.at(context, d.globalPosition),
            [
              for (final x in _shown)
                if (selected.contains(x.id)) x,
            ],
            queueView: queue,
            historyView: widget.historyView,
            onGoToPodcast: widget.onGoToPodcast,
          );
        },
        // Select the instant the button goes down. A tap handler would wait out the
        // double-click window first, which makes every click feel laggy.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) {
            if (ev.buttons != kPrimaryButton) return;
            _focus.requestFocus();
            setState(() => _select(e, i));
            _notifyFocus();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => player.play(e),
            child: Container(
              color: sel ? pal.selected : (i.isOdd ? pal.stripe : pal.bg),
              child: Row(children: [for (final c in cols) cell(c, content(c))]),
            ),
          ),
        ),
      );
    }

    final rowHeight = s.tableRowHeight.toDouble();
    void playSelected() {
      final chosen = [
        for (final x in _shown)
          if (selected.contains(x.id)) x,
      ];
      if (chosen.isEmpty) return;
      if (chosen.length > 1) {
        lib.enqueueAll([for (final x in chosen.skip(1)) x.id], next: true);
      }
      player.play(chosen.first);
    }

    void selectAll() =>
        setState(() => selected.addAll(_shown.map((x) => x.id)));

    final Widget body;
    if (eps.isEmpty) {
      body = Center(
        child: Text(
          widget.emptyText ??
              (queue
                  ? 'Up Next is empty. Right-click an episode to add it.'
                  : 'No episodes'),
          style: TextStyle(color: pal.muted),
        ),
      );
    } else if (queue && widget.canReorder) {
      body = ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemExtent: rowHeight,
        itemCount: eps.length,
        onReorderItem: _reorder,
        itemBuilder: (c, i) => row(c, eps[i], i),
      );
    } else {
      body = ListView.builder(
        itemExtent: rowHeight,
        itemCount: eps.length,
        itemBuilder: (c, i) => row(c, eps[i], i),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): selectAll,
        const SingleActivator(LogicalKeyboardKey.enter): playSelected,
        if (queue) ...{
          // In Up Next, Delete takes the selected episodes off the queue and Alt+arrows move them.
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              lib.removeAllFromQueue(selected.toList()),
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
              lib.nudgeInQueue(selected.toList(), -1),
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
              lib.nudgeInQueue(selected.toList(), 1),
        },
      },
      child: Focus(
        focusNode: _focus,
        child: LayoutBuilder(
          builder: (context, box) {
            _avail = box.maxWidth;
            return Column(
              children: [
                GestureDetector(
                  onSecondaryTapDown: (d) => _columnMenu(
                    context,
                    Zoom.at(context, d.globalPosition),
                    lib,
                  ),
                  child: Container(
                    height: 25,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [pal.toolbarTop, pal.toolbarBottom],
                      ),
                      border: Border(bottom: BorderSide(color: pal.rule)),
                    ),
                    child: Row(children: [for (final c in cols) header(c)]),
                  ),
                ),
                Expanded(child: body),
                if (selected.length > 1) _selectionBar(pal, lib, queue),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Clicking a column heading sorts the list. Up Next and history keep their own order.
  void _headerTap(String key, bool asc) {
    if (widget.queueMode || widget.keepOrder) return;
    setState(() {
      if (sortBy == key) {
        _asc = !asc;
      } else {
        sortBy = key;
        _asc = key != 'date' && key != 'rating';
      }
    });
  }

  /// Shown while two or more rows are selected (Ctrl-click or Shift-click): the same actions as
  /// the right-click menu, one click away.
  Widget _selectionBar(Pal pal, Library lib, bool queue) {
    final dm = context.read<DownloadManager>();
    final eps = [
      for (final x in _shown)
        if (selected.contains(x.id)) x,
    ];
    final ids = [for (final x in eps) x.id];
    final allQueued = ids.every(lib.queue.contains);
    final allPlayed = ids.every((id) => lib.progressOf(id).played);
    final allFav = ids.every(lib.isFavorite);
    Widget act(IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: pal.text,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: pal.header,
        border: Border(top: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Text(
            '${ids.length} selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: pal.text,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  act(
                    allQueued ? Icons.playlist_remove : Icons.playlist_add,
                    allQueued ? 'Remove from Up Next' : 'Add to Up Next',
                    () {
                      if (allQueued) {
                        lib.removeAllFromQueue(ids);
                        showQueueUndo(context, lib, 'Removed from Up Next');
                      } else {
                        lib.enqueueAll(
                          ids.where((id) => !lib.queue.contains(id)).toList(),
                        );
                      }
                    },
                  ),
                  if (queue) ...[
                    act(
                      Icons.vertical_align_top,
                      'Move to top',
                      () => lib.moveInQueue(ids, toTop: true),
                    ),
                    act(
                      Icons.vertical_align_bottom,
                      'Move to bottom',
                      () => lib.moveInQueue(ids, toTop: false),
                    ),
                  ],
                  act(Icons.download, 'Download', () => dm.downloadAll(eps)),
                  act(Icons.delete_outline, 'Delete downloads', () async {
                    for (final id in ids.where(dm.isDownloaded)) {
                      await dm.delete(id);
                    }
                  }),
                  act(
                    allPlayed
                        ? Icons.radio_button_unchecked
                        : Icons.check_circle_outline,
                    allPlayed ? 'Mark unplayed' : 'Mark played',
                    () => lib.markAllPlayed(ids, !allPlayed),
                  ),
                  act(
                    allFav ? Icons.star : Icons.star_border,
                    allFav ? 'Unfavorite' : 'Favorite',
                    () => lib.setFavorites(ids, !allFav),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear selection',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              setState(selected.clear);
              _notifyFocus();
            },
          ),
        ],
      ),
    );
  }

  /// Right-click on the column headings, like iTunes' "choose columns".
  Future<void> _columnMenu(BuildContext context, Offset at, Library lib) async {
    final s = lib.settings;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    CheckedPopupMenuItem<String> item(String key, String label, bool on) =>
        CheckedPopupMenuItem(value: key, checked: on, child: Text(label));
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(at, at),
        Offset.zero & overlay.size,
      ),
      items: [
        item('colDownload', 'Download status', s.colDownload),
        item('colTime', 'Time', s.colTime),
        if (widget.queueMode) ...[
          item('colStarts', 'Starts in', s.colStarts),
          item('colStartsAt', 'Starts at', s.colStartsAt),
          item('colEndsAt', 'Ends at', s.colEndsAt),
        ],
        if (widget.showPodcastColumn)
          item('colPodcast', 'Podcast', s.colPodcast),
        item('colRating', 'Rating', s.colRating),
        item('colDate', 'Release Date', s.colDate),
      ],
    );
    if (choice != null) lib.setSetting(choice, !(lib.settings[choice] as bool));
  }

  void _reorder(int oldIndex, int newIndex) {
    final lib = context.read<Library>();
    final dragged = _shown[oldIndex];
    // Dragging a selected row takes the whole selection with it; anything else moves alone.
    if (!selected.contains(dragged.id)) {
      setState(
        () => selected
          ..clear()
          ..add(dragged.id),
      );
    }
    final ids = [
      for (final x in _shown)
        if (selected.contains(x.id)) x.id,
    ];
    // Flutter gives the index after the dragged row is lifted out; the library wants the original slot.
    lib.moveQueueItems(ids, newIndex > oldIndex ? newIndex + 1 : newIndex);
  }

  void _notifyFocus() {
    final cb = widget.onFocusEpisode;
    if (cb == null) return;
    cb(
      selected.length == 1
          ? _shown.where((x) => x.id == selected.first).firstOrNull
          : null,
    );
  }

  /// Click selects one row, Ctrl/Cmd-click toggles it, Shift-click selects a range.
  void _select(Episode e, int index) {
    final kb = HardwareKeyboard.instance;
    if (kb.isShiftPressed && _anchor != null) {
      final from = _shown.indexWhere((x) => x.id == _anchor);
      if (from >= 0) {
        selected
          ..clear()
          ..addAll(
            _shown
                .sublist(
                  from < index ? from : index,
                  (from < index ? index : from) + 1,
                )
                .map((x) => x.id),
          );
        return;
      }
    }
    if (kb.isControlPressed || kb.isMetaPressed) {
      selected.contains(e.id) ? selected.remove(e.id) : selected.add(e.id);
    } else {
      selected
        ..clear()
        ..add(e.id);
    }
    _anchor = e.id;
  }
}
