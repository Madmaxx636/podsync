import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'desktop_table.dart';
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

/// The Podcasts section as iTunes 11 lays it out: Unplayed, My Podcasts and List across the top, each a different way into the same subscriptions.
class PodcastsLibrary extends StatelessWidget {
  const PodcastsLibrary({
    super.key,
    required this.filter,
    required this.onOpen,
    required this.onFocusEpisode,
  });

  final String filter;
  final ValueChanged<String> onOpen;
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
    final body = switch (tab) {
      'mine' => _MyPodcasts(
        filter: filter,
        onFocusEpisode: onFocusEpisode,
        onOpen: onOpen,
      ),
      'list' => _PodcastList(filter: filter, onOpen: onOpen),
      _ => _Unplayed(
        filter: filter,
        onFocusEpisode: onFocusEpisode,
        onOpen: onOpen,
      ),
    };
    return Column(
      children: [
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: pal.header,
            border: Border(bottom: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Check for new episodes',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: lib.refreshAll,
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in tabs.entries)
                        _TabLabel(
                          e.value,
                          selected: e.key == tab,
                          onTap: () => lib.setSetting('podcastsTab', e.key),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, {required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? pal.selected : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? pal.text : pal.muted,
          ),
        ),
      ),
    );
  }
}

/// 1,234 as 1.2k, so a long count never crowds the row.
String _short(int n) => n < 1000
    ? '$n'
    : (n < 10000
          ? '${(n / 1000).toStringAsFixed(1)}k'
          : '${(n / 1000).round()}k');

bool _matches(Library lib, Episode e, String filter) =>
    filter.isEmpty ||
    e.title.toLowerCase().contains(filter.toLowerCase()) ||
    lib.podcastTitle(e.feedUrl).toLowerCase().contains(filter.toLowerCase());

// ---- Unplayed ----------------------------------------------------------------------------

/// Every unplayed episode from every subscription, newest on top (or oldest, if you prefer).
class _Unplayed extends StatelessWidget {
  const _Unplayed({
    required this.filter,
    required this.onFocusEpisode,
    required this.onOpen,
  });
  final String filter;
  final ValueChanged<Episode?> onFocusEpisode;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final oldestFirst = lib.settings.sortOldestFirst;
    final eps =
        [
          for (final p in lib.subscriptions)
            for (final e in lib.episodesOf(p.feedUrl))
              if (!lib.progressOf(e.id).played && _matches(lib, e, filter)) e,
        ]..sort(
          (a, b) => oldestFirst
              ? a.published.compareTo(b.published)
              : b.published.compareTo(a.published),
        );
    return Column(
      children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                '${eps.length} unplayed',
                style: TextStyle(fontSize: 12.5, color: pal.muted),
              ),
              const Spacer(),
              Text(
                'Oldest first',
                style: TextStyle(fontSize: 12.5, color: pal.muted),
              ),
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: oldestFirst,
                onChanged: (v) => lib.setSetting('sortOldestFirst', v ?? false),
              ),
            ],
          ),
        ),
        Expanded(
          child: EpisodeTable(
            key: ValueKey('unplayed$oldestFirst'),
            episodes: eps,
            keepOrder: true,
            emptyText:
                'Nothing unplayed. Everything you subscribe to is caught up.',
            onGoToPodcast: onOpen,
            onFocusEpisode: onFocusEpisode,
          ),
        ),
      ],
    );
  }
}

// ---- My Podcasts -------------------------------------------------------------------------

/// Your shows in a column you can drag into order, and the selected show's episodes beside it.
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
  String? _feed;
  bool _old = false; // "Old Episodes": include the ones already played

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
    final current = subs.firstWhere(
      (p) => p.feedUrl == _feed,
      orElse: () => subs.first,
    );
    final all = lib.episodesOf(current.feedUrl);
    final unplayed = [
      for (final e in all)
        if (!lib.progressOf(e.id).played) e,
    ];
    final shown =
        (_old ? all : unplayed)
            .where((e) => _matches(lib, e, widget.filter))
            .toList()
          ..sort(
            (a, b) => lib.settings.sortOldestFirst
                ? a.published.compareTo(b.published)
                : b.published.compareTo(a.published),
          );

    Widget button(String text, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: pal.text,
          side: BorderSide(color: pal.rule),
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: Text(text),
      ),
    );

    return Row(
      children: [
        Container(
          width: lib.settings.podsColumnWidth,
          color: pal.sidebar,
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
              return Material(
                key: ValueKey(p.feedUrl),
                color: sel ? pal.selected : Colors.transparent,
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
                      setState(() {
                        _feed = p.feedUrl;
                        _old = false;
                      });
                    },
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Art(p.imageUrl, size: 32, radius: 3),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: sel ? Colors.white : pal.text,
                              ),
                            ),
                          ),
                          // The count has its own right-aligned slot, so the numbers line up
                          // in a column and never run into the drag handle.
                          SizedBox(
                            width: 40,
                            child: Text(
                              n == 0 ? '' : _short(n),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                color: sel ? Colors.white70 : pal.muted,
                              ),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Icon(
                                  Icons.drag_indicator,
                                  size: 18,
                                  color: sel ? Colors.white70 : pal.muted,
                                ),
                              ),
                            ),
                          ),
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
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: pal.rule)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: pal.text,
                            ),
                          ),
                          Text(
                            _old
                                ? '${all.length} episodes'
                                : '${unplayed.length} unplayed',
                            style: TextStyle(fontSize: 12, color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                    if (_old)
                      button('Done', () => setState(() => _old = false))
                    else ...[
                      button('Old Episodes', () => setState(() => _old = true)),
                      button('Add All', () {
                        lib.enqueueAll([
                          for (final e in unplayed)
                            if (!lib.queue.contains(e.id)) e.id,
                        ]);
                      }),
                    ],
                    button(
                      'Settings',
                      () => showPodcastSettings(context, current.feedUrl),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: EpisodeTable(
                  key: ValueKey('mine:${current.feedUrl}:$_old'),
                  episodes: shown,
                  keepOrder: true,
                  showPodcastColumn: false,
                  queueMarks: true,
                  emptyText: _old
                      ? 'No episodes'
                      : 'No unplayed episodes. Old Episodes shows the rest.',
                  onFocusEpisode: widget.onFocusEpisode,
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
  const _PodcastList({required this.filter, required this.onOpen});
  final String filter;
  final ValueChanged<String> onOpen;

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
    final pal = Pal.of(context);
    final player = context.read<PlayerController>();
    int dir(int c) => _asc ? c : -c;

    int cmpEp(Episode a, Episode b) => dir(switch (_sortBy) {
      'time' => a.durationMs.compareTo(b.durationMs),
      'date' => a.published.compareTo(b.published),
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

    Widget head(String key, String label, {double? width}) {
      final c = InkWell(
        onTap: () => _sort(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
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
                  size: 16,
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

    return Column(
      children: [
        Container(
          height: 25,
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
              const SizedBox(width: 28),
              head('name', 'Name'),
              head('time', 'Time', width: 90),
              head('date', 'Release Date', width: 140),
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
                  itemExtent: lib.settings.tableRowHeight.toDouble(),
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
                      final unplayed = eps
                          .where((e) => !lib.progressOf(e.id).played)
                          .length;
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
                                  width: 28,
                                  child: Icon(
                                    open
                                        ? Icons.arrow_drop_down
                                        : Icons.arrow_right,
                                    size: 20,
                                    color: pal.muted,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      unplayed > 0
                                          ? '${item.displayTitle}  ($unplayed unplayed)'
                                          : item.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: pal.text,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      latest == null
                                          ? ''
                                          : fmtDurationMs(latest.durationMs),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: pal.muted,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 140,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      latest == null
                                          ? ''
                                          : fmtDate(latest.published),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: pal.muted,
                                      ),
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
                    final fg = sel
                        ? Colors.white
                        : (played ? pal.muted : pal.text);
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
                              const SizedBox(width: 28),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 22,
                                    right: 6,
                                  ),
                                  child: Text(
                                    e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: fg),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    fmtDurationMs(e.durationMs),
                                    style: TextStyle(fontSize: 13, color: fg),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    fmtDate(e.published),
                                    style: TextStyle(fontSize: 13, color: fg),
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
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: pal.header,
            border: Border(top: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => showPodcastDefaults(context),
                icon: const Icon(Icons.settings, size: 15),
                label: const Text('Settings'),
                style: TextButton.styleFrom(
                  foregroundColor: pal.text,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
              const Spacer(),
              Text(
                '${rows.length} podcasts',
                style: TextStyle(fontSize: 12.5, color: pal.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The defaults every podcast starts from: whether to download, how often to look for new
/// episodes and how many to keep. (Each podcast can override them under its own Settings.)
Future<void> showPodcastDefaults(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (c) => Consumer<Library>(
      builder: (c, lib, _) {
        final s = lib.settings;
        Widget row(String label, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              control,
            ],
          ),
        );
        DropdownButton<int> drop(
          String key,
          int value,
          Map<String, int> options,
        ) => DropdownButton<int>(
          value: options.containsValue(value) ? value : options.values.first,
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.value, child: Text(e.key)),
          ],
          onChanged: (v) => lib.setSetting(key, v ?? value),
        );
        return AlertDialog(
          title: const Text('Podcast Defaults'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(
                  'Automatically download new episodes',
                  Switch(
                    value: s.autoDownloadNew,
                    onChanged: (v) => lib.setSetting('autoDownloadNew', v),
                  ),
                ),
                row(
                  'Check for new episodes',
                  drop('refreshIntervalMin', s.refreshIntervalMin, const {
                    'Manually': 0,
                    'Every 15 minutes': 15,
                    'Every 30 minutes': 30,
                    'Every hour': 60,
                    'Every 6 hours': 360,
                    'Every day': 1440,
                  }),
                ),
                row(
                  'Episodes to keep',
                  drop('maxEpisodesPerFeed', s.maxEpisodesPerFeed, const {
                    'All episodes': 0,
                    'Latest 5': 5,
                    'Latest 10': 10,
                    'Latest 25': 25,
                    'Latest 50': 50,
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
