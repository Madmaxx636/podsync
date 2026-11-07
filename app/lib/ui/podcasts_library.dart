import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/episode_view.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'downloads_ui.dart';
import 'pal.dart';
import 'podcast_settings.dart';
import 'resize.dart';
import 'zoom.dart';

/// Your subscriptions in the order you dragged them into, then any new ones A to Z.
List<Podcast> orderedSubscriptions(Library lib) {
  final subs = lib.subscriptions;
  final order = (lib.settings['podcastOrder'] as String)
      .split('\n')
      .where((x) => x.isNotEmpty)
      .toList();
  final byUrl = {for (final p in subs) p.feedUrl: p};
  return [
    for (final u in order)
      if (byUrl.containsKey(u)) byUrl.remove(u)!,
    ...byUrl.values,
  ];
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// iTunes' wording for when an episode came out: Today, Yesterday, the weekday for the past
/// week, then "Saturday, Sep 28, 2013".
String _when(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 0 && days < 7) return _weekdays[d.weekday - 1];
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// "1 hour 10 minutes", "47 minutes", "2 hours 25 minutes".
String _length(int ms) {
  if (ms <= 0) return '';
  final m = (ms / 60000).round();
  final h = m ~/ 60, r = m % 60;
  String u(int n, String w) => '$n $w${n == 1 ? '' : 's'}';
  if (h == 0) return u(r, 'minute');
  return r == 0 ? u(h, 'hour') : '${u(h, 'hour')} ${u(r, 'minute')}';
}

/// 10/4/13, the short date of the List view.
String _shortDate(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}/${d.day}/${d.year % 100}';
}

bool _matches(Library lib, Episode e, String filter) =>
    filter.isEmpty ||
    e.title.toLowerCase().contains(filter.toLowerCase()) ||
    lib.podcastTitle(e.feedUrl).toLowerCase().contains(filter.toLowerCase());

const _blue = Color(0xFF3D7BD9);

const _sortChoices = {
  'dateDesc': 'Date, newest first',
  'dateAsc': 'Date, oldest first',
  'titleAsc': 'Title, A to Z',
  'titleDesc': 'Title, Z to A',
  'durationAsc': 'Length, shortest first',
  'durationDesc': 'Length, longest first',
};

/// Sorts [eps] by one of the keys above (and, for Unplayed, 'podcastAsc': by show, then newest
/// first). Equal rows always fall back to newest first so they never jump about.
List<Episode> _sorted(Library lib, String key, List<Episode> eps) {
  final asc = key.endsWith('Asc');
  final field = key.replaceAll(RegExp(r'(Asc|Desc)$'), '');
  final titles = field == 'podcast'
      ? {
          for (final e in eps)
            e.feedUrl: lib.podcastTitle(e.feedUrl).toLowerCase(),
        }
      : const <String, String>{};
  int primary(Episode a, Episode b) => switch (field) {
    'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    'duration' => a.durationMs.compareTo(b.durationMs),
    'podcast' => titles[a.feedUrl]!.compareTo(titles[b.feedUrl]!),
    _ => a.published.compareTo(b.published),
  };
  return [...eps]..sort((a, b) {
    final c = primary(a, b);
    if (c != 0) return asc ? c : -c;
    return b.published.compareTo(a.published);
  });
}

/// The "Sort" menu of the Unplayed and My Podcasts views.
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.current,
    required this.onPick,
    this.extra = const {},
    this.label = false,
  });
  final String current;
  final ValueChanged<String> onPick;
  final Map<String, String> extra;
  final bool
  label; // icon with a caption under it, like the other header buttons

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Sort episodes',
      onSelected: onPick,
      itemBuilder: (c) => [
        for (final e in {..._sortChoices, ...extra}.entries)
          CheckedPopupMenuItem(
            value: e.key,
            checked: e.key == current,
            child: Text(e.value),
          ),
      ],
      child: label
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 20, color: pal.muted),
                  const SizedBox(height: 2),
                  Text(
                    'Sort',
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 16, color: pal.muted),
                  const SizedBox(width: 4),
                  Text(
                    'Sort',
                    style: TextStyle(fontSize: 12.5, color: pal.muted),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The status bar text for the Podcasts section, in iTunes' words.
String podcastsStatus(Library lib) {
  final tab = lib.settings['podcastsTab'];
  List<Episode> eps;
  if (tab == 'list') {
    eps = [for (final p in lib.subscriptions) ...lib.episodesOf(p.feedUrl)];
    final ms = eps.fold<int>(0, (a, e) => a + e.durationMs);
    final days = ms / 86400000;
    final span = days >= 1
        ? '${days.floor()} day${days.floor() == 1 ? '' : 's'}'
        : '${(ms / 3600000).toStringAsFixed(1)} hours';
    return '${lib.subscriptions.length} items, $span, ${fmtBytes(eps.fold<int>(0, (a, e) => a + e.fileSize))}';
  }
  if (tab == 'mine') {
    final chosen = lib.settings['podcastsSelected'] as String;
    final subs = orderedSubscriptions(lib);
    final feed = subs.any((p) => p.feedUrl == chosen)
        ? chosen
        : (subs.isEmpty ? '' : subs.first.feedUrl);
    eps = lib.episodesOf(feed);
    if (eps.isEmpty) return 'Zero items';
  } else {
    eps = [
      for (final p in lib.subscriptions)
        for (final e in lib.episodesOf(p.feedUrl))
          if (!lib.progressOf(e.id).played) e,
    ];
  }
  return '${eps.length} episodes, ${fmtBytes(eps.fold<int>(0, (a, e) => a + e.fileSize))}';
}

/// The Podcasts section as iTunes 11.1 lays it out: Unplayed, My Podcasts and List across the
/// top, each a different way into the same subscriptions.
class PodcastsLibrary extends StatelessWidget {
  const PodcastsLibrary({
    super.key,
    required this.filter,
    required this.onOpen,
    required this.onStore,
    required this.onFocusEpisode,
  });

  final String filter;
  final ValueChanged<String> onOpen;
  final VoidCallback onStore;
  final ValueChanged<Episode?> onFocusEpisode;

  static const tabs = {
    'unplayed': 'Unplayed',
    'mine': 'My Podcasts',
    'list': 'List',
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final tab = tabs.containsKey(lib.settings['podcastsTab'])
        ? lib.settings['podcastsTab'] as String
        : 'unplayed';
    // Unplayed has its own sort, kept on this device; the old "oldest first" setting is the start.
    final unplayedSort = (lib.settings['unplayedSort'] as String).isNotEmpty
        ? lib.settings['unplayedSort'] as String
        : (lib.settings.sortOldestFirst ? 'dateAsc' : 'dateDesc');
    final body = switch (tab) {
      'mine' => _MyPodcasts(
        filter: filter,
        onFocusEpisode: onFocusEpisode,
        onOpen: onOpen,
      ),
      'list' => _PodcastList(filter: filter, onOpen: onOpen, onStore: onStore),
      _ => _BigEpisodes(
        episodes: _sorted(lib, unplayedSort, [
          for (final p in lib.subscriptions)
            for (final e in lib.episodesOf(p.feedUrl))
              if (!lib.progressOf(e.id).played && _matches(lib, e, filter)) e,
        ]),
        mode: _RowMode.unplayed,
        onFocusEpisode: onFocusEpisode,
        onOpen: onOpen,
        empty: 'Nothing unplayed. Everything you subscribe to is caught up.',
      ),
    };
    return Column(
      children: [
        Container(
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [pal.toolbarTop, pal.toolbarBottom],
            ),
            border: Border(bottom: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Check for new episodes',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 26,
                ),
                icon: Icon(Icons.refresh, size: 17, color: pal.muted),
                onPressed: lib.refreshAll,
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in tabs.entries)
                        _Pill(
                          e.value,
                          selected: e.key == tab,
                          onTap: () => lib.setSetting('podcastsTab', e.key),
                        ),
                    ],
                  ),
                ),
              ),
              tab == 'unplayed'
                  ? _SortButton(
                      current: unplayedSort,
                      onPick: (k) => lib.setSetting('unplayedSort', k),
                      extra: const {'podcastAsc': 'Podcast, A to Z'},
                    )
                  : const SizedBox(width: 36),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// A tab label; the chosen one sits in a rounded, pressed-in pill, as in iTunes 11.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? pal.muted.withValues(alpha: 0.22) : null,
            border: selected
                ? Border.all(color: pal.muted.withValues(alpha: 0.45))
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: pal.text,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- the big episode rows (Unplayed, My Podcasts) ----------------------------------------

enum _RowMode { unplayed, show, oldShow }

/// Episodes the way iTunes 11 draws them: when and how long on the left, the title and its
/// description in the middle, a cloud (not downloaded) or a queue circle on the right.
class _BigEpisodes extends StatefulWidget {
  const _BigEpisodes({
    super.key,
    required this.episodes,
    required this.mode,
    required this.onFocusEpisode,
    required this.onOpen,
    required this.empty,
  });
  final List<Episode> episodes;
  final _RowMode mode;
  final ValueChanged<Episode?> onFocusEpisode;
  final ValueChanged<String> onOpen;
  final String empty;

  @override
  State<_BigEpisodes> createState() => _BigEpisodesState();
}

class _BigEpisodesState extends State<_BigEpisodes> {
  final Set<String> _more = {};
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final pal = Pal.of(context);
    final player = context.read<PlayerController>();
    final currentId = context.select<PlayerController, String?>(
      (p) => p.current?.id,
    );
    if (widget.episodes.isEmpty) {
      return Center(
        child: Text(widget.empty, style: TextStyle(color: pal.muted)),
      );
    }
    final unplayedMode = widget.mode == _RowMode.unplayed;
    final old = widget.mode == _RowMode.oldShow;

    Widget row(Episode e) {
      final sel = _selected == e.id;
      final playing = currentId == e.id;
      final played = lib.progressOf(e.id).played;
      final grey = old && played;
      final titleColor = grey ? pal.muted : pal.text;
      final desc = e.description.trim();
      final expanded = _more.contains(e.id);
      final long = desc.length > 190;

      final left = unplayedMode
          ? Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Center(
                    child: playing
                        ? Icon(Icons.volume_up, size: 14, color: _blue)
                        : (played
                              ? null
                              : Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: _blue,
                                    shape: BoxShape.circle,
                                  ),
                                )),
                  ),
                ),
                Art(
                  lib.podcasts[e.feedUrl]?.imageUrl.isNotEmpty == true
                      ? lib.podcasts[e.feedUrl]!.imageUrl
                      : e.imageUrl,
                  size: 58,
                  radius: 2,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        lib.podcastTitle(e.feedUrl),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _when(e.published),
                        style: TextStyle(fontSize: 13, color: pal.muted),
                      ),
                      Text(
                        _length(e.durationMs),
                        style: TextStyle(fontSize: 13, color: pal.muted),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _when(e.published),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _length(e.durationMs),
                      style: TextStyle(fontSize: 12.5, color: pal.muted),
                    ),
                  ],
                ),
              ),
            );

      final middle = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (!unplayedMode && playing)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.volume_up, size: 13, color: _blue),
                  ),
                Expanded(
                  child: Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            if (desc.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      desc,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: grey
                            ? pal.muted.withValues(alpha: 0.8)
                            : pal.muted,
                      ),
                    ),
                  ),
                  if (long && !expanded)
                    GestureDetector(
                      onTap: () => setState(() => _more.add(e.id)),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'More',
                              style: TextStyle(fontSize: 12, color: _blue),
                            ),
                            Icon(Icons.arrow_drop_down, size: 15, color: _blue),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );

      final Widget right = old
          ? InstantIconButton(
              icon: lib.queue.contains(e.id)
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              size: 22,
              color: lib.queue.contains(e.id)
                  ? _blue
                  : pal.muted.withValues(alpha: 0.5),
              tooltip: lib.queue.contains(e.id)
                  ? 'In Up Next. Click to remove'
                  : 'Add to Up Next',
              onTap: () => lib.queue.contains(e.id)
                  ? lib.removeFromQueue(e.id)
                  : lib.enqueue(e.id),
              width: 36,
            )
          : SizedBox(
              width: 36,
              child: dm.isDownloaded(e.id)
                  ? null
                  : Center(child: DownloadIcon(e, size: 17, color: pal.muted)),
            );

      return GestureDetector(
        onSecondaryTapDown: (d) {
          setState(() => _selected = e.id);
          showEpisodeMenu(context, Zoom.at(context, d.globalPosition), [
            e,
          ], onGoToPodcast: widget.onOpen);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) {
            if (ev.buttons != kPrimaryButton) return;
            setState(() => _selected = e.id);
            widget.onFocusEpisode(e);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => player.play(e),
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? pal.selected.withValues(alpha: 0.14) : null,
                border: Border(
                  bottom: BorderSide(color: pal.rule.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  left,
                  middle,
                  const SizedBox(width: 8),
                  right,
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.episodes.length,
      itemBuilder: (c, i) => row(widget.episodes[i]),
    );
  }
}

// ---- My Podcasts -------------------------------------------------------------------------

/// Your shows in a column you can drag into order, and the selected show beside it.
class _MyPodcasts extends StatefulWidget {
  const _MyPodcasts({
    required this.filter,
    required this.onFocusEpisode,
    required this.onOpen,
  });
  final String filter;
  final ValueChanged<Episode?> onFocusEpisode;
  final ValueChanged<String> onOpen;

  @override
  State<_MyPodcasts> createState() => _MyPodcastsState();
}

class _MyPodcastsState extends State<_MyPodcasts> {
  bool _old =
      false; // "Old Episodes": every episode, with a circle to queue each

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final subs = orderedSubscriptions(lib);
    if (subs.isEmpty) {
      return Center(
        child: Text(
          'No subscriptions yet. Use File > Subscribe to Podcast, or the Podcast Store.',
          style: TextStyle(color: pal.muted),
        ),
      );
    }
    final chosen = lib.settings['podcastsSelected'] as String;
    final current = subs.firstWhere(
      (p) => p.feedUrl == chosen,
      orElse: () => subs.first,
    );
    // The show's own sort order (its Sort button here, or Episode sort order in its Settings);
    // otherwise the global one.
    final ownSort = EpisodeView.sortOf(current);
    final sortKey = ownSort.isNotEmpty
        ? ownSort
        : (lib.settings.sortOldestFirst ? 'dateAsc' : 'dateDesc');
    final all = _sorted(lib, sortKey, lib.episodesOf(current.feedUrl));
    final unplayed = [
      for (final e in all)
        if (!lib.progressOf(e.id).played) e,
    ];
    final shown = [
      for (final e in (_old ? all : unplayed))
        if (_matches(lib, e, widget.filter)) e,
    ];
    final player = context.read<PlayerController>();

    Widget iconLabel(IconData icon, String label, VoidCallback onTap) =>
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: pal.muted),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, color: pal.muted)),
              ],
            ),
          ),
        );
    Widget button(String text, VoidCallback onTap, {bool primary = false}) =>
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SizedBox(
            height: 24,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: primary ? _blue : null,
                foregroundColor: primary ? Colors.white : pal.text,
                side: BorderSide(color: primary ? _blue : pal.rule),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              child: Text(text),
            ),
          ),
        );

    return Row(
      children: [
        Container(
          width: lib.settings.podsColumnWidth,
          color: pal.sidebar,
          // Drag a show anywhere on its row to reorder; there is no handle to clutter the list.
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: subs.length,
            // The new index already allows for the row being lifted out.
            onReorderItem: (from, to) {
              final urls = [for (final p in subs) p.feedUrl];
              urls.insert(to, urls.removeAt(from));
              lib.setSetting('podcastOrder', urls.join('\n'));
            },
            itemBuilder: (c, i) {
              final p = subs[i];
              final sel = p.feedUrl == current.feedUrl;
              final n = lib
                  .episodesOf(p.feedUrl)
                  .where((e) => !lib.progressOf(e.id).played)
                  .length;
              return ReorderableDragStartListener(
                key: ValueKey(p.feedUrl),
                index: i,
                child: GestureDetector(
                  onSecondaryTapDown: (d) => showPodcastMenu(
                    context,
                    Zoom.at(context, d.globalPosition),
                    p.feedUrl,
                    onOpen: widget.onOpen,
                  ),
                  onDoubleTap: () => widget.onOpen(p.feedUrl),
                  // Select the moment the button goes down, not after the double-click wait.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (e.buttons != kPrimaryButton) return;
                      lib.setSetting('podcastsSelected', p.feedUrl);
                      setState(() => _old = false);
                    },
                    child: Container(
                      height: 43,
                      color: sel
                          ? pal.muted.withValues(alpha: 0.28)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          Art(p.imageUrl, size: 36, radius: 2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: pal.text),
                            ),
                          ),
                          if (n > 0)
                            Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 18,
                              margin: const EdgeInsets.only(left: 6, right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: pal.muted.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                n > 999 ? '999+' : '$n',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        VerticalSplitter(
          onDrag: (dx) => lib.setSetting(
            'podsColumnWidth',
            (lib.settings.podsColumnWidth + dx).clamp(150.0, 520.0),
          ),
          onReset: () => lib.setSetting('podsColumnWidth', 230.0),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                height: 84,
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                decoration: BoxDecoration(
                  color: pal.header,
                  border: Border(bottom: BorderSide(color: pal.rule)),
                ),
                child: Row(
                  children: [
                    Art(current.imageUrl, size: 66, radius: 2),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  current.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: pal.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InstantIconButton(
                                icon: Icons.play_arrow,
                                size: 18,
                                color: pal.muted,
                                tooltip: 'Play the newest unplayed episode',
                                onTap: () {
                                  if (unplayed.isNotEmpty) {
                                    player.play(unplayed.first);
                                  }
                                },
                                width: 24,
                              ),
                              InstantIconButton(
                                icon: Icons.refresh,
                                size: 17,
                                color: pal.muted,
                                tooltip: 'Check this podcast for new episodes',
                                onTap: () => lib.refreshFeed(current.feedUrl),
                                width: 24,
                              ),
                              InstantIconButton(
                                icon: Icons.arrow_circle_right,
                                size: 17,
                                color: pal.muted,
                                tooltip: 'Go to the podcast page',
                                onTap: () => widget.onOpen(current.feedUrl),
                                width: 24,
                              ),
                            ],
                          ),
                          Text(
                            '${all.length} episode${all.length == 1 ? '' : 's'} • Subscribed',
                            style: TextStyle(fontSize: 13, color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                    if (_old) ...[
                      button('Add All', () {
                        lib.enqueueAll([
                          for (final e in all)
                            if (!lib.queue.contains(e.id)) e.id,
                        ]);
                      }),
                      button(
                        'Done',
                        () => setState(() => _old = false),
                        primary: true,
                      ),
                    ] else ...[
                      _SortButton(
                        current: sortKey,
                        label: true,
                        onPick: (k) => lib.updatePodcastSettings(
                          current.feedUrl,
                          extra: {'epSort': k},
                        ),
                      ),
                      iconLabel(
                        Icons.history,
                        'Old Episodes',
                        () => setState(() => _old = true),
                      ),
                      iconLabel(
                        Icons.settings,
                        'Settings',
                        () => showPodcastSettings(context, current.feedUrl),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _BigEpisodes(
                  key: ValueKey('${current.feedUrl}:$_old'),
                  episodes: shown,
                  mode: _old ? _RowMode.oldShow : _RowMode.show,
                  onFocusEpisode: widget.onFocusEpisode,
                  onOpen: widget.onOpen,
                  empty: _old
                      ? 'No episodes'
                      : 'No unplayed episodes. Old Episodes shows the rest.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- List --------------------------------------------------------------------------------

/// The spreadsheet view: each podcast is a row with an arrow that opens its episodes beneath it.
class _PodcastList extends StatefulWidget {
  const _PodcastList({
    required this.filter,
    required this.onOpen,
    required this.onStore,
  });
  final String filter;
  final ValueChanged<String> onOpen;
  final VoidCallback onStore;

  @override
  State<_PodcastList> createState() => _PodcastListState();
}

class _PodcastListState extends State<_PodcastList> {
  final Set<String> _open = {};
  String _sortBy = 'name';
  bool _asc = true;
  String? _selected;

  void _sort(String key) => setState(() {
    if (_sortBy == key) {
      _asc = !_asc;
    } else {
      _sortBy = key;
      _asc = key == 'name';
    }
  });

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final pal = Pal.of(context);
    final player = context.read<PlayerController>();
    final currentId = context.select<PlayerController, String?>(
      (p) => p.current?.id,
    );
    int dir(int c) => _asc ? c : -c;

    int cmpEp(Episode a, Episode b) => dir(switch (_sortBy) {
      'time' => a.durationMs.compareTo(b.durationMs),
      'date' => a.published.compareTo(b.published),
      'desc' => a.description.compareTo(b.description),
      _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    });

    final rows = <(Podcast, List<Episode>)>[];
    for (final p in lib.subscriptions) {
      final eps = [...lib.episodesOf(p.feedUrl)]
        ..sort((a, b) => b.published.compareTo(a.published));
      final hit =
          widget.filter.isEmpty ||
          p.displayTitle.toLowerCase().contains(widget.filter.toLowerCase());
      final shown = hit
          ? eps
          : [
              for (final e in eps)
                if (_matches(lib, e, widget.filter)) e,
            ];
      if (shown.isEmpty && !hit) continue;
      rows.add((p, shown));
    }
    rows.sort((a, b) {
      final la = a.$2.isEmpty ? null : a.$2.first;
      final lb = b.$2.isEmpty ? null : b.$2.first;
      return dir(switch (_sortBy) {
        'time' => (la?.durationMs ?? 0).compareTo(lb?.durationMs ?? 0),
        'date' => (la?.published ?? 0).compareTo(lb?.published ?? 0),
        'desc' => (a.$1.description).compareTo(b.$1.description),
        _ => a.$1.displayTitle.toLowerCase().compareTo(
          b.$1.displayTitle.toLowerCase(),
        ),
      });
    });

    final flat = <Object>[];
    for (final (p, eps) in rows) {
      flat.add(p);
      if (_open.contains(p.feedUrl) || widget.filter.isNotEmpty) {
        flat.addAll(<Episode>[...eps]..sort(cmpEp));
      }
    }

    const dotW = 26.0, checkW = 24.0, timeW = 78.0, dateW = 84.0;
    Widget head(String key, String label, {double? width, bool right = false}) {
      final c = InkWell(
        onTap: () => _sort(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: pal.text,
                    fontWeight: _sortBy == key
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (_sortBy == key)
                Icon(
                  _asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 15,
                  color: pal.text,
                ),
            ],
          ),
        ),
      );
      return width == null
          ? Expanded(child: c)
          : SizedBox(width: width, child: c);
    }

    Widget cell(String text, double w, TextStyle st, {bool right = false}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              text,
              maxLines: 1,
              textAlign: right ? TextAlign.end : TextAlign.start,
              style: st,
            ),
          ),
        );

    final rowH = lib.settings.tableRowHeight.toDouble();
    return Column(
      children: [
        Container(
          height: 22,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [pal.toolbarTop, pal.toolbarBottom],
            ),
            border: Border(bottom: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              const SizedBox(width: dotW),
              SizedBox(
                width: checkW,
                child: Icon(Icons.check, size: 12, color: pal.muted),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(children: [head('name', 'Podcast', width: 160)]),
                ),
              ),
              head('time', 'Time', width: timeW, right: true),
              head('date', 'Release Date', width: dateW + 12),
              Expanded(
                flex: 4,
                child: Row(children: [head('desc', 'Description', width: 220)]),
              ),
            ],
          ),
        ),
        Expanded(
          child: flat.isEmpty
              ? Center(
                  child: Text(
                    'No subscriptions yet',
                    style: TextStyle(color: pal.muted),
                  ),
                )
              : ListView.builder(
                  itemExtent: rowH,
                  itemCount: flat.length,
                  itemBuilder: (c, i) {
                    final item = flat[i];
                    final stripe = i.isOdd ? pal.stripe : pal.bg;
                    if (item is Podcast) {
                      final open =
                          _open.contains(item.feedUrl) ||
                          widget.filter.isNotEmpty;
                      final eps = rows.firstWhere((r) => r.$1 == item).$2;
                      final latest = eps.isEmpty ? null : eps.first;
                      final anyUnplayed = eps.any(
                        (e) => !lib.progressOf(e.id).played,
                      );
                      final st = TextStyle(fontSize: 12.5, color: pal.text);
                      return GestureDetector(
                        onSecondaryTapDown: (d) => showPodcastMenu(
                          context,
                          Zoom.at(context, d.globalPosition),
                          item.feedUrl,
                          onOpen: widget.onOpen,
                        ),
                        child: InkWell(
                          onTap: () => setState(() {
                            _open.contains(item.feedUrl)
                                ? _open.remove(item.feedUrl)
                                : _open.add(item.feedUrl);
                          }),
                          child: Container(
                            color: stripe,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: dotW,
                                  child: anyUnplayed
                                      ? const Center(child: _Dot())
                                      : null,
                                ),
                                const SizedBox(width: checkW),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Icon(
                                        open
                                            ? Icons.arrow_drop_down
                                            : Icons.arrow_right,
                                        size: 18,
                                        color: pal.muted,
                                      ),
                                      Flexible(
                                        child: Text(
                                          item.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: st,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                cell(
                                  latest == null
                                      ? ''
                                      : fmtDurationMs(latest.durationMs),
                                  timeW,
                                  st,
                                  right: true,
                                ),
                                cell(
                                  latest == null
                                      ? ''
                                      : _shortDate(latest.published),
                                  dateW + 12,
                                  st,
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      item.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: st,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    final e = item as Episode;
                    final played = lib.progressOf(e.id).played;
                    final sel = _selected == e.id;
                    final fg = sel ? Colors.white : pal.text;
                    final st = TextStyle(fontSize: 12.5, color: fg);
                    final queued = lib.queue.contains(e.id);
                    return GestureDetector(
                      onSecondaryTapDown: (d) {
                        setState(() => _selected = e.id);
                        showEpisodeMenu(
                          context,
                          Zoom.at(context, d.globalPosition),
                          [e],
                          onGoToPodcast: widget.onOpen,
                        );
                      },
                      child: InkWell(
                        onTap: () => setState(() => _selected = e.id),
                        onDoubleTap: () => player.play(e),
                        child: Container(
                          color: sel ? pal.selected : stripe,
                          child: Row(
                            children: [
                              SizedBox(
                                width: dotW,
                                child: currentId == e.id
                                    ? Icon(
                                        Icons.volume_up,
                                        size: 13,
                                        color: sel ? Colors.white : _blue,
                                      )
                                    : (played
                                          ? null
                                          : const Center(child: _Dot())),
                              ),
                              SizedBox(
                                width: checkW,
                                child: InkWell(
                                  onTap: () => queued
                                      ? lib.removeFromQueue(e.id)
                                      : lib.enqueue(e.id),
                                  child: Tooltip(
                                    message: queued
                                        ? 'In Up Next. Click to remove'
                                        : 'Add to Up Next',
                                    child: queued
                                        ? Icon(Icons.check, size: 14, color: fg)
                                        : null,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 22),
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          e.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: st,
                                        ),
                                      ),
                                      if (!dm.isDownloaded(e.id)) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.cloud_download_outlined,
                                          size: 13,
                                          color: sel
                                              ? Colors.white70
                                              : pal.muted,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              cell(
                                fmtDurationMs(e.durationMs),
                                timeW,
                                st,
                                right: true,
                              ),
                              cell(_shortDate(e.published), dateW + 12, st),
                              Expanded(
                                flex: 4,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    e.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: st,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: pal.header,
            border: Border(top: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              // Subscribe is for a podcast that is not yet subscribed; every row here is.
              const _BarButton('Subscribe'),
              const SizedBox(width: 10),
              _BarButton(
                'Settings...',
                onTap: () => showPodcastDefaults(context),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onStore,
                child: Text(
                  'Podcast Catalog >',
                  style: TextStyle(fontSize: 12.5, color: pal.text),
                ),
              ),
              const SizedBox(width: 18),
              _BarButton('Refresh', onTap: lib.refreshAll),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
  );
}

/// A grey rounded button of the List view's bottom bar (greyed out without an action).
class _BarButton extends StatelessWidget {
  const _BarButton(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      height: 24,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: pal.text,
          backgroundColor: pal.bg,
          side: BorderSide(color: pal.rule),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
        child: Text(text),
      ),
    );
  }
}

/// The defaults every podcast starts from, in iTunes' Podcast Defaults sheet: how often to look
/// for new episodes, whether to download them, and how many to keep. Nothing changes until OK.
Future<void> showPodcastDefaults(BuildContext context) {
  final lib = context.read<Library>();
  final s = lib.settings;
  var check = s.refreshIntervalMin;
  var auto = s.autoDownloadNew;
  var keep = s.maxEpisodesPerFeed;
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final pal = Pal.of(c);
        Widget row(String label, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  label,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 200, child: control),
            ],
          ),
        );
        Widget drop<T>(T value, Map<String, T> options, ValueChanged<T> on) =>
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: pal.field,
                border: Border.all(color: pal.rule),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  isExpanded: true,
                  isDense: true,
                  value: options.containsValue(value)
                      ? value
                      : options.values.first,
                  style: TextStyle(fontSize: 13.5, color: pal.text),
                  items: [
                    for (final e in options.entries)
                      DropdownMenuItem(value: e.value, child: Text(e.key)),
                  ],
                  onChanged: (v) => setState(() => on(v as T)),
                ),
              ),
            );
        return Dialog(
          backgroundColor: pal.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [pal.toolbarTop, pal.toolbarBottom],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Podcast Defaults',
                    style: TextStyle(fontSize: 12.5, color: pal.muted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 20, 10),
                  child: Column(
                    children: [
                      row(
                        'Check for new episodes:',
                        drop<int>(check, const {
                          'Manually': 0,
                          'Every hour': 60,
                          'Every 2 hours': 120,
                          'Every 6 hours': 360,
                          'Every day': 1440,
                        }, (v) => check = v),
                      ),
                      row(
                        'Automatically Download:',
                        drop<bool>(auto, const {
                          'Off': false,
                          'New episodes': true,
                        }, (v) => auto = v),
                      ),
                      row(
                        'Episodes to Keep:',
                        drop<int>(keep, const {
                          'All episodes': 0,
                          'Last 1': 1,
                          'Last 2': 2,
                          'Last 3': 3,
                          'Last 5': 5,
                          'Last 10': 10,
                          'Last 25': 25,
                        }, (v) => keep = v),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: pal.rule),
                        ),
                        child: Tooltip(
                          message: 'Each podcast can override these under its own Settings.',
                          child: Icon(
                            Icons.help_outline,
                            size: 14,
                            color: pal.muted,
                          ),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _blue),
                        onPressed: () {
                          lib.setSetting('refreshIntervalMin', check);
                          lib.setSetting('autoDownloadNew', auto);
                          lib.setSetting('maxEpisodesPerFeed', keep);
                          Navigator.pop(c);
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
