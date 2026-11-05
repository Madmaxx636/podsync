import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'downloads_ui.dart';
import 'settings.dart';
import 'sleep_ui.dart';
import 'store_view.dart';
import 'common.dart';
import 'paged.dart';
import 'podcast_settings.dart';

enum _Section { queue, episodes, podcasts, add, downloads, stats, settings }

const _titles = {
  _Section.queue: 'Queue',
  _Section.episodes: 'Episodes',
  _Section.podcasts: 'Subscriptions',
  _Section.add: 'Add podcast',
  _Section.downloads: 'Downloads',
  _Section.stats: 'Statistics',
  _Section.settings: 'Settings',
};

const _icons = {
  _Section.queue: Icons.queue_music,
  _Section.episodes: Icons.library_music,
  _Section.podcasts: Icons.subscriptions,
  _Section.add: Icons.add,
  _Section.downloads: Icons.download_done,
  _Section.stats: Icons.bar_chart,
  _Section.settings: Icons.settings,
};

/// Downloads and Statistics can be hidden in Settings; the other sections cannot.
bool _hidden(Library lib, _Section s) =>
    (s == _Section.downloads && !lib.settings.uiPhoneDownloads) ||
    (s == _Section.stats && !lib.settings.uiPhoneStats);

/// Phone/tablet UI modelled on AntennaPod: a navigation drawer, episode rows
/// with a play button on the right, and a mini player docked at the bottom.
/// With e-ink mode on, the drawer becomes a row of text tabs and every list
/// is paged instead of scrolled.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  _Section section = _Section.queue;
  final List<_Section> _previous =
      []; // sections visited before this one, for the back button

  void _select(_Section s) {
    if (s == section) return;
    setState(() {
      _previous.add(section);
      section = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final eink = lib.einkMode;

    final body = switch (section) {
      _Section.queue => QueueView(
        onFindPodcasts: () => _select(_Section.add),
        onBrowseEpisodes: () => _select(_Section.episodes),
      ),
      _Section.episodes => const EpisodesView(),
      _Section.podcasts => const SubscriptionsView(),
      _Section.add => const AddPodcastView(),
      _Section.downloads => const DownloadsView(),
      _Section.stats => const StatsView(),
      _Section.settings => const SettingsHome(),
    };

    // Back goes to the section you came from; from the first one it leaves the app.
    return PopScope(
      canPop: _previous.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _previous.isNotEmpty) {
          setState(() => section = _previous.removeLast());
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ScreenHeader(
                title: _titles[section]!,
                actions: [
                  if (lib.signedIn)
                    IconButton(
                      tooltip: 'Sync',
                      onPressed: lib.syncing
                          ? null
                          : () async {
                              await lib.sync();
                              await lib.refreshAll();
                            },
                      icon: const Icon(Icons.sync),
                    ),
                ],
              ),
              if (eink) _EinkTabs(section: section, onSelect: _select),
              Expanded(child: body),
            ],
          ),
        ),
        // One look for both kinds of screen: the same headers, rows, mini player and player.
        // Colour phones navigate with AntennaPod's bottom bar, e-ink with the tabs above.
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const MiniPlayer(), if (!eink) _bottomNav(context, lib)],
        ),
      ),
    );
  }

  static const _navMain = [
    _Section.queue,
    _Section.episodes,
    _Section.podcasts,
    _Section.add,
  ];
  static const _navMore = [
    _Section.downloads,
    _Section.stats,
    _Section.settings,
  ];

  Widget _bottomNav(BuildContext context, Library lib) {
    final inMore = _navMore.contains(section);
    final index = inMore ? _navMain.length : _navMain.indexOf(section);
    return NavigationBar(
      height: 68,
      selectedIndex: index,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) {
        if (i < _navMain.length) {
          _select(_navMain[i]);
        } else {
          _showMore(context, lib);
        }
      },
      destinations: [
        for (final s in _navMain)
          NavigationDestination(
            icon: _navIcon(lib, s),
            selectedIcon: _navIcon(lib, s),
            label: s == _Section.podcasts
                ? 'Podcasts'
                : _titles[s]!.split(' ').first,
          ),
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
    );
  }

  Widget _navIcon(Library lib, _Section s) {
    final n = switch (s) {
      _Section.queue => lib.queue.length,
      _Section.episodes => lib.unplayedCount,
      _ => 0,
    };
    final icon = Icon(_icons[s]);
    return n == 0 ? icon : Badge(label: Text('$n'), child: icon);
  }

  void _showMore(BuildContext context, Library lib) {
    final dm = context.read<DownloadManager>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _navMore)
              if (!_hidden(lib, s))
                ListTile(
                  leading: Icon(_icons[s]),
                  title: Text(_titles[s]!),
                  trailing: s == _Section.downloads && dm.doneCount > 0
                      ? Text('${dm.doneCount}')
                      : null,
                  selected: s == section,
                  onTap: () {
                    Navigator.pop(c);
                    _select(s);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

/// The big bold title at the top of each screen, with its actions at the right.
class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 6, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class _EinkTabs extends StatelessWidget {
  const _EinkTabs({required this.section, required this.onSelect});
  final _Section section;
  final ValueChanged<_Section> onSelect;

  static const _main = [
    _Section.queue,
    _Section.episodes,
    _Section.podcasts,
    _Section.add,
  ];
  static const _more = [_Section.downloads, _Section.stats, _Section.settings];

  @override
  Widget build(BuildContext context) {
    // Browser-style tabs: the selected one is outlined with rounded top corners and open at the
    // bottom, so it joins the line that runs under the whole row.
    final lib = context.read<Library>();
    final inMore = _more.contains(section);

    Widget tab(
      String label,
      bool selected, {
      required VoidCallback onTap,
      String? tooltip,
    }) {
      final box = Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : null,
          border: selected
              ? const Border(
                  top: BorderSide(width: 2),
                  left: BorderSide(width: 2),
                  right: BorderSide(width: 2),
                )
              : null,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w900 : FontWeight.bold,
            color: Colors.black,
          ),
        ),
      );
      return Expanded(
        // Reacts on touch-down; waiting for the finger to lift feels slow on e-ink.
        child: Listener(
          onPointerDown: (_) => onTap(),
          behavior: HitTestBehavior.opaque,
          child: tooltip == null ? box : Tooltip(message: tooltip, child: box),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(height: 2, child: ColoredBox(color: Colors.black)),
          ),
          Row(
            children: [
              for (final s in _main)
                tab(
                  s == _Section.podcasts
                      ? 'Podcasts'
                      : (s == _Section.add ? 'Add' : _titles[s]!),
                  s == section,
                  onTap: () => onSelect(s),
                ),
              // Downloads, Statistics and Settings live under one tab so the row stays readable.
              Expanded(
                child: Builder(
                  builder: (ctx) => Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) async {
                      final box = ctx.findRenderObject() as RenderBox;
                      final origin = box.localToGlobal(Offset.zero);
                      final picked = await showMenu<_Section>(
                        context: ctx,
                        position: RelativeRect.fromLTRB(
                          origin.dx,
                          origin.dy + box.size.height,
                          origin.dx + box.size.width,
                          0,
                        ),
                        items: [
                          for (final s in _more)
                            if (!_hidden(lib, s))
                              PopupMenuItem(value: s, child: Text(_titles[s]!)),
                        ],
                      );
                      if (picked != null) onSelect(picked);
                    },
                    child: Tooltip(
                      message: 'More sections',
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: inMore ? Colors.white : null,
                          border: inMore
                              ? const Border(
                                  top: BorderSide(width: 2),
                                  left: BorderSide(width: 2),
                                  right: BorderSide(width: 2),
                                )
                              : null,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          inMore ? _titles[section]! : 'More',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: inMore
                                ? FontWeight.w900
                                : FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ListView normally, a [PagedList] in e-ink mode.
Widget adaptiveList<T>(
  BuildContext context,
  List<T> items,
  double extent,
  Widget Function(BuildContext, T) build, {
  String empty = 'Nothing here',
}) {
  final lib = context.read<Library>();
  if (lib.einkMode) {
    // `extent` is the row height at the default size; the e-ink "row size" setting scales it.
    return PagedList<T>(
      items: items,
      itemExtent: extent * lib.settings.einkRowHeight / 88,
      itemBuilder: build,
      empty: empty,
    );
  }
  if (items.isEmpty) {
    return Center(
      child: Text(empty, style: Theme.of(context).textTheme.titleMedium),
    );
  }
  return ListView.builder(
    itemCount: items.length,
    itemExtent: extent,
    itemBuilder: (c, i) => build(c, items[i]),
  );
}

// ---- lists -----------------------------------------------------------------

class QueueView extends StatelessWidget {
  const QueueView({super.key, this.onFindPodcasts, this.onBrowseEpisodes});

  final VoidCallback? onFindPodcasts;
  final VoidCallback? onBrowseEpisodes;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final items = lib.queueEpisodes;
    final Widget list;
    if (items.isEmpty) {
      list = _EmptyQueue(
        hasPodcasts: lib.subscriptions.isNotEmpty,
        onFindPodcasts: onFindPodcasts,
        onBrowseEpisodes: onBrowseEpisodes,
      );
    } else if (!lib.einkMode) {
      list = ReorderableListView.builder(
        itemCount: items.length,
        onReorderItem: (from, to) =>
            lib.reorderQueue(from, to > from ? to + 1 : to),
        itemBuilder: (c, i) => Dismissible(
          key: ValueKey(items[i].id),
          onDismissed: (_) {
            lib.removeFromQueue(items[i].id);
            showQueueUndo(context, lib, 'Removed from queue');
          },
          background: Container(color: Colors.red.shade400),
          child: SizedBox(height: 104, child: EpisodeTile(items[i])),
        ),
      );
    } else {
      list = adaptiveList(context, items, 104, (c, e) => EpisodeTile(e));
    }
    return Column(
      children: [
        if (items.isNotEmpty || lib.canUndoQueue) const _QueueSummary(),
        Expanded(child: list),
      ],
    );
  }
}

/// First-run and cleared-queue state: says what Up Next is and where to go next.
class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({
    required this.hasPodcasts,
    this.onFindPodcasts,
    this.onBrowseEpisodes,
  });

  final bool hasPodcasts;
  final VoidCallback? onFindPodcasts;
  final VoidCallback? onBrowseEpisodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 56, color: theme.hintColor),
            const SizedBox(height: 16),
            Text('Your queue is empty', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              hasPodcasts ? 'Add episodes to play them one after another.' : 'Subscribe to a podcast, then add episodes here to play them one after another.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (!hasPodcasts && onFindPodcasts != null)
              FilledButton(
                onPressed: onFindPodcasts,
                child: const Text('Find podcasts'),
              ),
            if (hasPodcasts && onBrowseEpisodes != null)
              FilledButton(
                onPressed: onBrowseEpisodes,
                child: const Text('Browse episodes'),
              ),
          ],
        ),
      ),
    );
  }
}

const _queueSortLabels = {
  QueueSort.oldestFirst: 'Release date, oldest first',
  QueueSort.newestFirst: 'Release date, newest first',
  QueueSort.title: 'Title',
  QueueSort.podcast: 'Podcast',
  QueueSort.shortest: 'Time left, shortest first',
  QueueSort.longest: 'Time left, longest first',
};

/// Totals for the queue and the sort / shuffle / clean-up / undo menu.
class _QueueSummary extends StatelessWidget {
  const _QueueSummary();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pin = context.read<PlayerController>().current?.id;
    final n = lib.queue.length;
    final left = lib.queueRemaining;
    final ends = DateTime.now().add(left);
    final h = ends.hour % 12 == 0 ? 12 : ends.hour % 12;
    final clock =
        '$h:${ends.minute.toString().padLeft(2, '0')} ${ends.hour < 12 ? 'AM' : 'PM'}';

    void done(String message) => showQueueUndo(context, lib, message);

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                n == 0
                    ? 'Nothing queued'
                    : '$n episodes • ${fmtLong(left, zero: 'nothing')} left • ends about $clock',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Queue options',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'shuffle':
                  lib.shuffleQueue(pinId: pin);
                  done('Queue shuffled');
                case 'played':
                  done('Removed ${lib.removePlayedFromQueue()} played');
                case 'clear':
                  lib.clearQueue();
                  done('Queue cleared');
                case 'undo':
                  lib.undoQueue();
                default:
                  lib.sortQueue(QueueSort.values.byName(v), pinId: pin);
                  done('Queue sorted');
              }
            },
            itemBuilder: (c) => [
              if (lib.canUndoQueue)
                PopupMenuItem(
                  value: 'undo',
                  child: Text('Undo ${lib.queueUndoLabel}'),
                ),
              for (final e in _queueSortLabels.entries)
                PopupMenuItem(
                  value: e.key.name,
                  enabled: n > 1,
                  child: Text('Sort: ${e.value}'),
                ),
              PopupMenuItem(
                value: 'shuffle',
                enabled: n > 1,
                child: const Text('Shuffle'),
              ),
              PopupMenuItem(
                value: 'played',
                enabled: lib.queue.any((id) => lib.progressOf(id).played),
                child: const Text('Remove played episodes'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: n > 0,
                child: const Text('Clear queue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _EpisodeFilter { unplayed, all, downloaded, favorites, history }

class EpisodesView extends StatefulWidget {
  const EpisodesView({super.key});

  @override
  State<EpisodesView> createState() => _EpisodesViewState();
}

class _EpisodesViewState extends State<EpisodesView> {
  _EpisodeFilter filter = _EpisodeFilter.unplayed;

  static const _labels = {
    _EpisodeFilter.unplayed: 'Unplayed',
    _EpisodeFilter.all: 'All',
    _EpisodeFilter.downloaded: 'Offline',
    _EpisodeFilter.favorites: 'Favorites',
    _EpisodeFilter.history: 'History',
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final eink = lib.einkMode;
    final items = switch (filter) {
      _EpisodeFilter.unplayed =>
        lib.allEpisodes.where((e) => !lib.progressOf(e.id).played).toList(),
      _EpisodeFilter.all => lib.allEpisodes,
      _EpisodeFilter.downloaded =>
        lib.allEpisodes.where((e) => dm.isDownloaded(e.id)).toList(),
      _EpisodeFilter.favorites => lib.favoriteEpisodes,
      _EpisodeFilter.history => lib.historyEpisodes,
    };
    final empty = switch (filter) {
      _EpisodeFilter.favorites => 'No favorites yet',
      _EpisodeFilter.downloaded => 'Nothing downloaded yet',
      _EpisodeFilter.history => 'Nothing played yet',
      _ =>
        lib.subscriptions.isEmpty
            ? 'Subscribe to a podcast to see episodes'
            : 'No episodes',
    };
    return Column(
      children: [
        if (lib.settings.uiPhoneFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Row(
              children: [
                for (final f in _EpisodeFilter.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _labels[f]!,
                              style: eink && filter == f
                                  ? const TextStyle(color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selected: filter == f,
                        onSelected: (_) => setState(() => filter = f),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await lib.sync();
              await lib.refreshAll();
            },
            child: adaptiveList(
              context,
              items,
              104,
              (c, e) => EpisodeTile(e),
              empty: empty,
            ),
          ),
        ),
      ],
    );
  }
}

class SubscriptionsView extends StatelessWidget {
  const SubscriptionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final subs = lib.subscriptions;
    final eink = lib.einkMode;
    if (eink || subs.isEmpty) {
      return adaptiveList(
        context,
        subs,
        88,
        (c, p) => _PodcastRow(p),
        empty: 'No subscriptions yet',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: subs.length,
      itemBuilder: (c, i) {
        final p = subs[i];
        final unplayed = lib
            .episodesOf(p.feedUrl)
            .where((e) => !lib.progressOf(e.id).played)
            .length;
        return InkWell(
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(builder: (_) => PodcastScreen(p.feedUrl)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Art(p.imageUrl, size: 140),
              if (unplayed > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(c).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unplayed',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PodcastRow extends StatelessWidget {
  const _PodcastRow(this.p);
  final Podcast p;

  @override
  Widget build(BuildContext context) {
    final eink = context.read<Library>().einkMode;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PodcastScreen(p.feedUrl)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Art(p.imageUrl, size: 64, gray: eink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (p.author.isNotEmpty)
                    Text(
                      p.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- episode row -------------------------------------------------------------

/// The round play / pause button AntennaPod puts on every row and on the player: an outline on
/// e-ink, a filled accent circle in colour.
class PlayCircle extends StatelessWidget {
  const PlayCircle({
    super.key,
    required this.playing,
    required this.onTap,
    this.size = 52,
    this.eink = false,
    this.filled = false,
  });
  final bool playing;
  final VoidCallback onTap;
  final double size;
  final bool eink;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = filled && !eink;
    final line = eink ? Colors.black : (fill ? cs.primary : cs.onSurface);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: playing ? 'Pause' : 'Play',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill ? cs.primary : null,
            border: fill
                ? null
                : Border.all(width: eink ? 2.5 : 2, color: line),
          ),
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            size: size * 0.58,
            color: fill ? cs.onPrimary : line,
          ),
        ),
      ),
    );
  }
}

class EpisodeTile extends StatelessWidget {
  const EpisodeTile(this.e, {super.key});
  final Episode e;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<PlayerController>();
    final dm = context.watch<DownloadManager>();
    final eink = lib.einkMode;
    final pr = lib.progressOf(e.id);
    final dur = e.durationMs > 0 ? e.durationMs : pr.durationMs;
    final fraction = dur > 0 ? (pr.positionMs / dur).clamp(0.0, 1.0) : 0.0;
    final isCurrent = context.select<PlayerController, bool>(
      (p) => p.current?.id == e.id,
    );
    final isPlaying = context.select<PlayerController, bool>(
      (p) => p.current?.id == e.id && p.playing,
    );
    final cs = Theme.of(context).colorScheme;
    final muted = eink ? Colors.black : cs.onSurfaceVariant;
    // "Sep 8 • 304 MB • Downloaded", then the title, then the time or progress: AntennaPod's row.
    final meta = [
      fmtDate(e.published, year: false),
      if (e.fileSize > 0) fmtBytes(e.fileSize),
      if (dm.isDownloaded(e.id)) 'Downloaded',
      if (lib.isFavorite(e.id)) '\u2605',
    ].where((x) => x.isNotEmpty).join(' • ');
    final smallStyle = TextStyle(
      fontSize: 13,
      color: muted,
      fontWeight: FontWeight.w600,
    );
    final Widget status = pr.played
        ? Text('Played', style: smallStyle)
        : (fraction > 0
              ? Row(
                  children: [
                    Text(fmtDurationMs(pr.positionMs), style: smallStyle),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '-${fmtDurationMs(dur - pr.positionMs)}',
                      style: smallStyle,
                    ),
                  ],
                )
              : Text(dur > 0 ? fmtDurationMs(dur) : '', style: smallStyle));

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EpisodeScreen(e.id)),
      ),
      onLongPress: () => _menu(context, lib),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            Art(e.imageUrl, size: 64, gray: eink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: smallStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.15,
                      fontWeight: pr.played
                          ? FontWeight.normal
                          : FontWeight.w700,
                      color: pr.played ? Theme.of(context).disabledColor : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  status,
                ],
              ),
            ),
            const SizedBox(width: 6),
            // The download icon can be switched off in Settings > Interface; e-ink spells it out
            // in the "Downloaded" note instead.
            if (!eink && lib.settings.uiRowDownloadIcon)
              DownloadIcon(e, size: 22),
            const SizedBox(width: 4),
            PlayCircle(
              playing: isPlaying,
              size: 52,
              eink: eink,
              onTap: () => isCurrent ? player.toggle() : player.play(e),
            ),
            // E-ink has no comfortable long-press, so its menu button is always visible.
            if (eink)
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _menu(context, lib),
              ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context, Library lib) {
    final inQueue = lib.queue.contains(e.id);
    final played = lib.progressOf(e.id).played;
    final queueIndex = lib.queue.indexOf(e.id);
    final dm = context.read<DownloadManager>();
    final eink = lib.einkMode;

    final entries = <(IconData, String, VoidCallback)>[
      (Icons.playlist_play, 'Play next', () => lib.enqueue(e.id, next: true)),
      (
        inQueue ? Icons.remove_from_queue : Icons.add_to_queue,
        inQueue ? 'Remove from queue' : 'Add to queue',
        () {
          if (inQueue) {
            lib.removeFromQueue(e.id);
            showQueueUndo(context, lib, 'Removed from queue');
          } else {
            lib.enqueue(e.id);
          }
        },
      ),
      (
        dm.isDownloaded(e.id)
            ? Icons.delete_outline
            : (dm.isBusy(e.id) ? Icons.cancel_outlined : Icons.download),
        dm.isDownloaded(e.id)
            ? 'Remove download'
            : (dm.isBusy(e.id) ? 'Cancel download' : 'Download'),
        () => dm.isDownloaded(e.id)
            ? dm.delete(e.id)
            : (dm.isBusy(e.id) ? dm.cancel(e.id) : dm.download(e)),
      ),
      if (inQueue) ...[
        (
          Icons.vertical_align_top,
          'Move to top',
          () => lib.moveInQueue([e.id], toTop: true),
        ),
        if (queueIndex > 0)
          (Icons.arrow_upward, 'Move up', () => lib.nudgeInQueue([e.id], -1)),
        if (queueIndex < lib.queue.length - 1)
          (
            Icons.arrow_downward,
            'Move down',
            () => lib.nudgeInQueue([e.id], 1),
          ),
        (
          Icons.vertical_align_bottom,
          'Move to bottom',
          () => lib.moveInQueue([e.id], toTop: false),
        ),
      ],
      (
        lib.isFavorite(e.id) ? Icons.star : Icons.star_border,
        lib.isFavorite(e.id) ? 'Remove from favorites' : 'Add to favorites',
        () => lib.setFavorite(e.id, !lib.isFavorite(e.id)),
      ),
      (
        played ? Icons.visibility_off : Icons.check,
        played ? 'Mark as unplayed' : 'Mark as played',
        () => lib.markPlayed(e.id, !played),
      ),
      (
        Icons.link,
        'Copy episode link',
        () async {
          await Clipboard.setData(
            ClipboardData(text: e.link.isNotEmpty ? e.link : e.audioUrl),
          );
          if (context.mounted) showSnack(context, 'Link copied');
        },
      ),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        Widget rating() => Row(
          children: [
            const SizedBox(width: 16),
            const Text('Rating'),
            const Spacer(),
            StarRating(
              value: lib.ratingOf(e.id),
              size: 28,
              onChanged: (v) {
                Navigator.pop(c);
                lib.setRatings([e.id], v);
              },
            ),
            const SizedBox(width: 16),
          ],
        );
        return SafeArea(
          child: eink
              // No scrolling on e-ink: the actions become a wrapped grid of buttons that fits the screen.
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (icon, label, run) in entries)
                            OutlinedButton.icon(
                              icon: Icon(icon, size: 18),
                              label: Text(label),
                              onPressed: () {
                                Navigator.pop(c);
                                run();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      rating(),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (icon, label, run) in entries)
                        ListTile(
                          dense: true,
                          leading: Icon(icon),
                          title: Text(label),
                          onTap: () {
                            Navigator.pop(c);
                            run();
                          },
                        ),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.grade_outlined),
                        title: rating(),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ---- detail screens ----------------------------------------------------------

/// A plain icon-and-label action in the row under the episode header, spread evenly.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class EpisodeScreen extends StatefulWidget {
  const EpisodeScreen(this.id, {super.key});
  final String id;

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  bool showChapters = false;

  Future<void> _playFrom(PlayerController player, Episode e, Chapter c) async {
    if (player.current?.id != e.id) await player.play(e);
    await player.seek(Duration(milliseconds: c.startMs));
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final lib = context.watch<Library>();
    final player = context.read<PlayerController>();
    final e = lib.episodes[id];
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Episode not found')),
      );
    }
    final eink = lib.einkMode;
    final inQueue = lib.queue.contains(id);
    final played = lib.progressOf(id).played;
    final fav = lib.isFavorite(id);
    final dm = context.watch<DownloadManager>();

    // AntennaPod's episode page: a compact header, one plain row with the main actions, and the
    // rest (played, queue, favourite, open podcast, link) in the menu at the top right.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Art(e.imageUrl, size: 76, gray: eink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lib.podcastTitle(e.feedUrl),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  e.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDurationMs(e.durationMs)} · ${fmtDate(e.published, year: false)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final downloaded = dm.isDownloaded(id);
    final actions = Row(
      children: [
        _TextAction(
          icon: Icons.play_arrow,
          label: 'Play',
          onTap: () {
            player.play(e);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          },
        ),
        _TextAction(
          icon: downloaded
              ? Icons.delete_outline
              : (dm.isBusy(id) ? Icons.close : Icons.download),
          label: downloaded
              ? 'Delete'
              : (dm.isBusy(id) ? 'Cancel' : 'Download'),
          onTap: downloaded
              ? () => dm.delete(id)
              : (dm.isBusy(id) ? () => dm.cancel(id) : () => dm.download(e)),
        ),
        if (e.chapters.isNotEmpty)
          _TextAction(
            icon: showChapters ? Icons.notes : Icons.list,
            label: showChapters ? 'Notes' : 'Chapters',
            onTap: () => setState(() => showChapters = !showChapters),
          ),
      ],
    );

    final Widget content = showChapters
        ? adaptiveList(context, e.chapters, 56, (c, ch) {
            return InkWell(
              onTap: () => _playFrom(player, e, ch),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        fmtDuration(Duration(milliseconds: ch.startMs)),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ch.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
        : (eink
              ? PagedText(e.description)
              : SingleChildScrollView(
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${e.title}\n\n',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        TextSpan(
                          text: e.description,
                          style: const TextStyle(fontSize: 17, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ));

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (e.link.isNotEmpty)
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.public),
              onPressed: () => launchUrl(
                Uri.parse(e.link),
                mode: LaunchMode.externalApplication,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              switch (v) {
                case 'played':
                  lib.markPlayed(id, !played);
                case 'queue':
                  inQueue ? lib.removeFromQueue(id) : lib.enqueue(id);
                case 'podcast':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PodcastScreen(e.feedUrl)),
                  );
                case 'fav':
                  lib.setFavorite(id, !fav);
                case 'link':
                  await Clipboard.setData(
                    ClipboardData(
                      text: e.link.isNotEmpty ? e.link : e.audioUrl,
                    ),
                  );
                  if (context.mounted) showSnack(context, 'Link copied');
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: 'played',
                child: Text(played ? 'Mark as unplayed' : 'Mark as played'),
              ),
              PopupMenuItem(
                value: 'queue',
                child: Text(inQueue ? 'Remove from queue' : 'Add to queue'),
              ),
              const PopupMenuItem(
                value: 'podcast',
                child: Text('Open podcast'),
              ),
              PopupMenuItem(
                value: 'fav',
                child: Text(fav ? 'Remove from favorites' : 'Add to favorites'),
              ),
              const PopupMenuItem(
                value: 'link',
                child: Text('Share (copy link)'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            actions,
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PodcastScreen extends StatefulWidget {
  const PodcastScreen(this.feedUrl, {super.key});
  final String feedUrl;

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  bool busy = false;

  Future<void> _toggle(Library lib) async {
    setState(() => busy = true);
    try {
      if (lib.isSubscribed(widget.feedUrl)) {
        lib.unsubscribe(widget.feedUrl);
      } else {
        await lib.subscribe(widget.feedUrl);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not subscribe: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final p = lib.podcasts[widget.feedUrl];
    final eps = lib
        .episodesOf(widget.feedUrl)
        .where((e) => !lib.settings.hidePlayed || !lib.progressOf(e.id).played)
        .toList();
    final subscribed = lib.isSubscribed(widget.feedUrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.displayTitle ?? 'Podcast'),
        actions: [
          if (subscribed)
            PopupMenuButton<String>(
              tooltip: 'Downloads',
              icon: const Icon(Icons.download_for_offline_outlined),
              onSelected: (v) {
                final dm = context.read<DownloadManager>();
                final todo = eps
                    .where(
                      (e) =>
                          !lib.progressOf(e.id).played &&
                          !dm.isDownloaded(e.id) &&
                          !dm.isBusy(e.id),
                    )
                    .toList();
                if (v == 'all') {
                  dm.downloadAll(todo);
                  showSnack(context, 'Downloading ${todo.length} episodes');
                } else {
                  for (final e in eps.where((e) => dm.isDownloaded(e.id))) {
                    dm.delete(e.id);
                  }
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(
                  value: 'all',
                  child: Text('Download all unplayed'),
                ),
                PopupMenuItem(value: 'remove', child: Text('Remove downloads')),
              ],
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: widget.feedUrl));
                if (context.mounted) showSnack(context, 'Feed address copied');
              } else {
                final all = lib.episodesOf(widget.feedUrl).map((e) => e.id);
                lib.markAllPlayed(all, v == 'played');
                if (context.mounted) {
                  showSnack(
                    context,
                    v == 'played'
                        ? 'All episodes marked as played'
                        : 'All episodes marked as unplayed',
                  );
                }
              }
            },
            itemBuilder: (c) => [
              if (subscribed) ...const [
                PopupMenuItem(
                  value: 'played',
                  child: Text('Mark all as played'),
                ),
                PopupMenuItem(
                  value: 'unplayed',
                  child: Text('Mark all as unplayed'),
                ),
              ],
              const PopupMenuItem(
                value: 'copy',
                child: Text('Copy feed address'),
              ),
            ],
          ),
          if (subscribed)
            IconButton(
              tooltip: 'Podcast settings',
              icon: const Icon(Icons.tune),
              onPressed: () => showPodcastSettings(context, widget.feedUrl),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Art(p?.imageUrl ?? '', size: 72, gray: lib.einkMode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p?.author ?? '',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => _toggle(lib),
                    child: Text(subscribed ? 'Unsubscribe' : 'Subscribe'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: adaptiveList(
                context,
                eps,
                104,
                (c, e) => EpisodeTile(e),
                empty: 'No episodes',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ---- add podcast -------------------------------------------------------------

class AddPodcastView extends StatelessWidget {
  const AddPodcastView({super.key});

  @override
  Widget build(BuildContext context) => PhoneStore(
    onOpen: (feed) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PodcastScreen(feed)),
    ),
  );
}

// ---- player ------------------------------------------------------------------

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.read<Library>();
    // Listen for the setting too, so switching the mini player off in Settings takes effect at once.
    final visible = context.select<Library, bool>(
      (l) => l.settings.uiMiniPlayer,
    );
    final e = player.current;
    if (e == null || !visible) return const SizedBox.shrink();
    final eink = lib.einkMode;
    final total = player.duration.inMilliseconds;
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: eink ? 0 : 6,
      color: eink ? Colors.white : cs.surfaceContainerHigh,
      child: Container(
        decoration: eink
            ? const BoxDecoration(border: Border(top: BorderSide(width: 2)))
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AntennaPod's thin progress line runs along the top edge.
            LinearProgressIndicator(
              value: total > 0
                  ? (player.position.inMilliseconds / total).clamp(0.0, 1.0)
                  : 0,
              minHeight: 3,
            ),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: SizedBox(
                height: 62,
                child: Row(
                  children: [
                    Art(e.imageUrl, size: 62, radius: 0, gray: eink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            lib.podcastTitle(e.feedUrl),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: eink ? Colors.black : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 36,
                      tooltip: player.playing ? 'Pause' : 'Play',
                      icon: Icon(
                        player.playing ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: player.toggle,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.watch<Library>();
    final e = player.current;
    final eink = lib.einkMode;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }
    final total = player.duration.inMilliseconds.toDouble();
    final pos = player.position.inMilliseconds
        .toDouble()
        .clamp(0, total > 0 ? total : 1)
        .toDouble();
    final cs = Theme.of(context).colorScheme;
    final muted = eink ? Colors.black : cs.onSurfaceVariant;
    final speed = lib.speedFor(e.feedUrl);
    Chapter? chapterNow;
    for (final c in e.chapters) {
      if (c.startMs <= player.position.inMilliseconds) chapterNow = c;
    }

    void openNotes() => eink
        ? Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EpisodeScreen(e.id)),
          )
        : _showPlayerSheet(context, e);

    // An icon with a small label under it, like AntennaPod's speed and skip controls.
    Widget control(
      IconData icon,
      String label,
      String tooltip,
      VoidCallback onTap,
    ) => Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: SizedBox(
          width: 58,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 34),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (lib.settings.uiPlayerSpeed)
            control(
              Icons.speed,
              speed.toStringAsFixed(2),
              'Playback speed',
              () {
                const speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
                final i = speeds.indexWhere((x) => (x - speed).abs() < 0.01);
                player.setSpeed(speeds[(i + 1) % speeds.length]);
              },
            )
          else
            const SizedBox(width: 58),
          control(
            Icons.fast_rewind,
            '${lib.skipBackSec}',
            'Back ${lib.skipBackSec}s',
            player.skipBack,
          ),
          PlayCircle(
            playing: player.playing,
            size: 76,
            eink: eink,
            filled: true,
            onTap: player.toggle,
          ),
          control(
            Icons.fast_forward,
            '${lib.skipForwardSec}',
            'Forward ${lib.skipForwardSec}s',
            player.skipForward,
          ),
          control(Icons.skip_next, '', 'Next in queue', player.next),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Collapse arrow at the left; favourite, sleep timer and the menu at the right.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close player',
                    icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: lib.isFavorite(e.id)
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    icon: Icon(
                      lib.isFavorite(e.id) ? Icons.star : Icons.star_border,
                    ),
                    onPressed: () =>
                        lib.setFavorite(e.id, !lib.isFavorite(e.id)),
                  ),
                  if (lib.settings.uiPlayerSleep) const SleepTimerButton(),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) async {
                      switch (v) {
                        case 'notes':
                          openNotes();
                        case 'played':
                          lib.markPlayed(e.id, true);
                        case 'link':
                          await Clipboard.setData(
                            ClipboardData(
                              text: e.link.isNotEmpty ? e.link : e.audioUrl,
                            ),
                          );
                          if (context.mounted) {
                            showSnack(context, 'Link copied');
                          }
                      }
                    },
                    itemBuilder: (c) => const [
                      PopupMenuItem(value: 'notes', child: Text('Show notes')),
                      PopupMenuItem(
                        value: 'played',
                        child: Text('Mark as played'),
                      ),
                      PopupMenuItem(
                        value: 'link',
                        child: Text('Copy episode link'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = max(0.0, min(c.maxWidth - 64, c.maxHeight - 8));
                  return Center(
                    child: Art(e.imageUrl, size: side, radius: 10, gray: eink),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                children: [
                  Text(
                    '${lib.podcastTitle(e.feedUrl)}  •  ${fmtDate(e.published, year: false)}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (chapterNow != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        chapterNow.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (player.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(player.error!, textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: openNotes,
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: Text(
                      e.chapters.isEmpty
                          ? 'Shownotes'
                          : 'Shownotes and chapters',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Slider(
                value: pos,
                max: total > 0 ? total : 1,
                onChanged: total > 0
                    ? (v) => player.seek(Duration(milliseconds: v.round()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtDuration(player.position)),
                  Text(
                    total > 0
                        ? '-${fmtDuration(player.duration - player.position)}'
                        : '',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            controls,
            if (lib.settings.uiPlayerVolume)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: lib.settings.muted ? 'Unmute' : 'Mute',
                      icon: Icon(
                        lib.settings.muted || lib.settings.volume == 0
                            ? Icons.volume_off
                            : (lib.settings.volume < 0.5
                                  ? Icons.volume_down
                                  : Icons.volume_up),
                      ),
                      onPressed: player.toggleMute,
                    ),
                    Expanded(
                      child: Slider(
                        value: lib.settings.muted ? 0.0 : lib.settings.volume,
                        onChanged: player.setVolume,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${((lib.settings.muted ? 0.0 : lib.settings.volume) * 100).round()}%',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// AntennaPod's slide-up panel: the show notes, and the chapters to jump between.
void _showPlayerSheet(BuildContext context, Episode e) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (c, scroll) => _PlayerSheet(e, scroll),
    ),
  );
}

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet(this.e, this.scroll);
  final Episode e;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final notes = ListView(
      controller: scroll,
      padding: const EdgeInsets.all(16),
      children: [
        Text(e.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SelectableText(
          e.description.isEmpty ? 'No show notes.' : e.description,
        ),
      ],
    );
    if (e.chapters.isEmpty) return notes;
    final now = player.position.inMilliseconds;
    var current = 0;
    for (var i = 0; i < e.chapters.length; i++) {
      if (e.chapters[i].startMs <= now) current = i;
    }
    final chapters = ListView.builder(
      controller: scroll,
      itemCount: e.chapters.length,
      itemBuilder: (c, i) {
        final ch = e.chapters[i];
        return ListTile(
          selected: i == current,
          leading: Text(fmtDuration(Duration(milliseconds: ch.startMs))),
          title: Text(ch.title),
          onTap: () => player.seek(Duration(milliseconds: ch.startMs)),
        );
      },
    );
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Notes'),
              Tab(text: 'Chapters'),
            ],
          ),
          Expanded(child: TabBarView(children: [notes, chapters])),
        ],
      ),
    );
  }
}
