import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/episode_view.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'desktop_menubar.dart';
import 'desktop_table.dart';
import 'desktop_toolbar.dart';
import 'detail_pane.dart';
import 'episode_filter.dart';
import 'interface_menu.dart';
import 'downloads_ui.dart';
import 'pal.dart';
import 'resize.dart';
import 'podcasts_library.dart';
import 'zoom.dart';
import 'mini_player.dart';
import 'podcast_settings.dart';
import 'settings.dart';
import 'store_view.dart';

/// A place in the sidebar or a podcast page. Equal places compare equal, so the
/// back/forward history can tell when you are already there.
sealed class _Source {
  const _Source();
  String get key;
  @override
  bool operator ==(Object other) => other is _Source && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

class _Library extends _Source {
  const _Library(this.kind);
  final String kind; // podcasts | episodes | queue | favorites | history
  @override
  String get key => 'lib:$kind';
}

class _Store extends _Source {
  const _Store();
  @override
  String get key => 'store';
}

class _Settings extends _Source {
  const _Settings();
  @override
  String get key => 'settings';
}

class _Show extends _Source {
  const _Show(this.feedUrl);
  final String feedUrl;
  @override
  String get key => 'show:$feedUrl';
}

/// Desktop UI modelled on iTunes 12: a menu bar, a transport + "LCD" toolbar, a
/// source-list sidebar, a striped table of episodes and an optional details pane.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // Places visited, like a browser: back and forward move along it, going somewhere new cuts off the forward part.
  late final List<_Source> _history = [_startSource(context.read<Library>())];
  int _pos = 0;
  String filter = '';
  final FocusNode _searchFocus = FocusNode();
  Episode?
  _detailEpisode; // the one episode selected in the table, for the details pane
  EpisodeFilter _episodeFilter = EpisodeFilter.all;

  /// The place PodSync opens on: the person's choice (Settings > Interface > Open on), or the
  /// one they left from, or Episodes.
  static _Source _startSource(Library lib) {
    final want = lib.settings.startScreen == 'last'
        ? lib.settings.lastScreen
        : lib.settings.startScreen;
    if (want == 'store' || want == 'store:') return const _Store();
    const kinds = {
      'episodes',
      'podcasts',
      'queue',
      'favorites',
      'history',
      'downloads',
      'stats',
    };
    return kinds.contains(want) ? _Library(want) : const _Library('episodes');
  }

  _Source get source => _history[_pos];
  bool get canGoBack => _pos > 0;
  bool get canGoForward => _pos < _history.length - 1;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _go(_Source s) {
    if (s == source) return;
    setState(() {
      _history.removeRange(_pos + 1, _history.length);
      _history.add(s);
      _pos++;
      filter = '';
      _detailEpisode = null;
      _episodeFilter = EpisodeFilter.all;
    });
    final lib = context.read<Library>();
    if (lib.settings.startScreen == 'last') {
      if (s is _Library) lib.setSetting('lastScreen', s.kind);
      if (s is _Store) lib.setSetting('lastScreen', 'store');
    }
  }

  void _back() {
    if (canGoBack) {
      setState(() {
        _pos--;
        _detailEpisode = null;
      });
    }
  }

  void _forward() {
    if (canGoForward) {
      setState(() {
        _pos++;
        _detailEpisode = null;
      });
    }
  }

  void _goTo(String where) => _go(switch (where) {
    'store' => const _Store(),
    'settings' => const _Settings(),
    _ => _Library(where),
  });

  late final DesktopCommands _commands = DesktopCommands(
    go: _goTo,
    focusSearch: () => _searchFocus.requestFocus(),
    goPodcast: (f) => _go(_Show(f)),
    openUpNext: () =>
        showUpNextPopover(context, onGoToPodcast: (f) => _go(_Show(f))),
  );

  /// Space plays and pauses, unless you are typing in a text box.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final player = context.read<PlayerController>();
    if (player.current == null) return KeyEventResult.ignored;
    player.toggle();
    return KeyEventResult.handled;
  }

  String _settingsCategory = 'Appearance';

  /// Opens Settings on the Interface page (right-click the toolbar or sidebar, then Customize).
  void _customize() {
    setState(() => _settingsCategory = 'Interface');
    _go(const _Settings());
  }

  bool get _isTable =>
      source is _Show ||
      (source is _Library &&
          !const {
            'podcasts',
            'downloads',
            'stats',
          }.contains((source as _Library).kind));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: MiniPlayer.active,
    builder: (context, mini, _) =>
        mini ? const MiniPlayerView() : _buildFull(context),
  );

  Widget _buildFull(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final s = lib.settings;
    return CallbackShortcuts(
      bindings: {
        ...desktopShortcuts(context, _commands),
        ...Zoom.shortcuts(lib),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _forward,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
            _back,
        const SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
            _forward,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            lib.setSetting('showDetails', !s.showDetails),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        // The back and forward buttons on a mouse.
        child: Listener(
          onPointerDown: (e) {
            if (e.buttons == kBackMouseButton) _back();
            if (e.buttons == kForwardMouseButton) _forward();
          },
          child: Scaffold(
            backgroundColor: pal.bg,
            body: Column(
              children: [
                if (s.uiMenuBar) AppMenuBar(commands: _commands),
                DesktopToolbar(
                  onSearch: (v) => setState(() => filter = v),
                  searchFocus: _searchFocus,
                  onGoToPodcast: (f) => _go(_Show(f)),
                  onCustomize: _customize,
                  onOpenDownloads: () => _goTo('downloads'),
                ),
                DesktopNavRow(
                  onBack: canGoBack ? _back : null,
                  onForward: canGoForward ? _forward : null,
                  title: _placeName(lib),
                  places: [
                    for (final (label, kind) in const [
                      ('Episodes', 'episodes'),
                      ('Podcasts', 'podcasts'),
                      ('Up Next', 'queue'),
                      ('Favorites', 'favorites'),
                      ('Recently Played', 'history'),
                      ('Downloads', 'downloads'),
                      ('Statistics', 'stats'),
                    ])
                      (label, () => _goTo(kind)),
                  ],
                  storeActive: source is _Store,
                  onLibrary: () {
                    if (source is _Store || source is _Settings) {
                      _go(const _Library('episodes'));
                    }
                  },
                  onStore: () => _go(const _Store()),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (s.showSidebar) ...[
                        _Sidebar(
                          source: source,
                          onSelect: _go,
                          onCustomize: _customize,
                        ),
                        // Drag the edge to resize the sidebar; double-click puts it back.
                        VerticalSplitter(
                          onDrag: (dx) => lib.setSetting(
                            'sidebarWidth',
                            (s.sidebarWidth + dx).clamp(140.0, 480.0),
                          ),
                          onReset: () => lib.setSetting('sidebarWidth', 200.0),
                        ),
                      ],
                      Expanded(child: _content(lib)),
                      if (s.showDetails && _isTable) ...[
                        VerticalSplitter(
                          onDrag: (dx) => lib.setSetting(
                            'detailsWidth',
                            (s.detailsWidth - dx).clamp(200.0, 700.0),
                          ),
                          onReset: () => lib.setSetting('detailsWidth', 300.0),
                        ),
                        EpisodeDetailPane(
                          episode: _detailEpisode,
                          onGoToPodcast: (f) => _go(_Show(f)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (s.showStatusBar) _StatusBar(text: _status(lib)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The name of where you are, for the menu in the second toolbar row.
  String _placeName(Library lib) {
    final s = source;
    if (s is _Store) return 'Podcast Store';
    if (s is _Settings) return 'Settings';
    if (s is _Show) return lib.podcastTitle(s.feedUrl);
    return switch ((s as _Library).kind) {
      'podcasts' => 'Podcasts',
      'queue' => 'Up Next',
      'favorites' => 'Favorites',
      'history' => 'Recently Played',
      'downloads' => 'Downloads',
      'stats' => 'Statistics',
      _ => 'Episodes',
    };
  }

  String _status(Library lib) {
    final s = source;
    List<Episode> eps;
    if (s is _Library && s.kind == 'queue') {
      eps = lib.queueEpisodes;
    } else if (s is _Library && s.kind == 'episodes') {
      eps = lib.allEpisodes;
    } else if (s is _Library && s.kind == 'favorites') {
      eps = lib.favoriteEpisodes;
    } else if (s is _Library && s.kind == 'history') {
      eps = lib.historyEpisodes;
    } else if (s is _Show) {
      eps = lib.episodesOf(s.feedUrl);
    } else if (s is _Library && s.kind == 'downloads') {
      final dm = context.read<DownloadManager>();
      return '${dm.doneCount} downloaded, ${fmtBytes(dm.totalBytes)}';
    } else if (s is _Library && s.kind == 'podcasts') {
      return podcastsStatus(lib);
    } else if (s is _Library && s.kind == 'stats') {
      final st = lib.stats();
      return '${fmtLong(st.listened, zero: '0 m')} listened across ${st.played} episodes';
    } else {
      return lib.syncing
          ? 'Syncing…'
          : (lib.syncError ?? (lib.syncEnabled ? 'Sync is on' : ''));
    }
    final total = Duration(
      milliseconds: eps.fold(0, (a, e) => a + e.durationMs),
    );
    if (s is _Library && s.kind == 'queue') {
      return '${eps.length} episodes, ${fmtLong(lib.queueTotalLength, zero: '0 m')} total, ${fmtLong(lib.queueRemaining, zero: 'nothing')} left';
    }
    final hours = total.inMinutes / 60;
    return '${eps.length} episodes, ${hours.toStringAsFixed(1)} hours';
  }

  Widget _content(Library lib) {
    final s = source;
    final dm = context.watch<DownloadManager>();
    bool match(Episode e) =>
        filter.isEmpty ||
        e.title.toLowerCase().contains(filter.toLowerCase()) ||
        lib
            .podcastTitle(e.feedUrl)
            .toLowerCase()
            .contains(filter.toLowerCase());
    void goPodcast(String f) => _go(_Show(f));
    void focus(Episode? e) => setState(() => _detailEpisode = e);
    switch (s) {
      case _Library(kind: 'podcasts'):
        return PodcastsLibrary(
          filter: filter,
          onOpen: goPodcast,
          onStore: () => _go(const _Store()),
          onFocusEpisode: focus,
        );
      case _Library(kind: 'queue'):
        return Column(
          children: [
            const QueueHeader(),
            Expanded(
              child: EpisodeTable(
                key: const ValueKey('queue'),
                episodes: lib.queueEpisodes.where(match).toList(),
                queueMode: true,
                canReorder: filter.isEmpty,
                onGoToPodcast: goPodcast,
                onFocusEpisode: focus,
              ),
            ),
          ],
        );
      case _Library(kind: 'favorites'):
        return EpisodeTable(
          key: const ValueKey('favorites'),
          episodes: lib.favoriteEpisodes.where(match).toList(),
          emptyText: 'No favorites yet. Right-click an episode to add one.',
          onGoToPodcast: goPodcast,
          onFocusEpisode: focus,
        );
      case _Library(kind: 'history'):
        return EpisodeTable(
          key: const ValueKey('history'),
          episodes: lib.historyEpisodes.where(match).toList(),
          keepOrder: true,
          historyView: true,
          emptyText: 'Nothing played yet',
          onGoToPodcast: goPodcast,
          onFocusEpisode: focus,
        );
      case _Library(kind: 'downloads'):
        return const DownloadsView();
      case _Library(kind: 'stats'):
        return const StatsView();
      case _Library():
        final all = lib.allEpisodes.where(match).toList();
        return Column(
          children: [
            if (lib.settings.uiFilterBar)
              EpisodeFilterBar(
                value: _episodeFilter,
                onChanged: (f) => setState(() => _episodeFilter = f),
                episodes: all,
                lib: lib,
                dm: dm,
              ),
            Expanded(
              child: EpisodeTable(
                key: const ValueKey('episodes'),
                episodes: filterEpisodes(_episodeFilter, all, lib, dm),
                emptyText: _episodeFilter == EpisodeFilter.all
                    ? null
                    : 'No ${episodeFilterLabels[_episodeFilter]!.toLowerCase()} episodes',
                onGoToPodcast: goPodcast,
                onFocusEpisode: focus,
              ),
            ),
          ],
        );
      case _Show(:final feedUrl):
        final eps = EpisodeView.of(lib, feedUrl, downloaded: dm.isDownloaded)
            .where(match)
            .where(
              (e) => !lib.settings.hidePlayed || !lib.progressOf(e.id).played,
            )
            .toList();
        return Column(
          children: [
            _ShowHeader(feedUrl),
            if (lib.settings.uiFilterBar)
              EpisodeFilterBar(
                value: _episodeFilter,
                onChanged: (f) => setState(() => _episodeFilter = f),
                episodes: eps,
                lib: lib,
                dm: dm,
              ),
            Expanded(
              child: EpisodeTable(
                key: ValueKey('show:$feedUrl'),
                episodes: filterEpisodes(_episodeFilter, eps, lib, dm),
                // This podcast's own sort order wins over the column sort.
                keepOrder:
                    lib.podcasts[feedUrl] != null &&
                    EpisodeView.sortOf(lib.podcasts[feedUrl]!).isNotEmpty,
                showPodcastColumn: false,
                onGoToPodcast: goPodcast,
                onFocusEpisode: focus,
              ),
            ),
          ],
        );
      case _Store():
        return StoreView(onOpen: goPodcast);
      case _Settings():
        return SettingsPane(
          key: ValueKey(_settingsCategory),
          initial: _settingsCategory,
        );
    }
  }
}

/// The strip above Up Next: totals, when the queue would finish, and the sort, shuffle, clean-up and undo buttons.
class QueueHeader extends StatelessWidget {
  const QueueHeader({super.key});

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static const _labels = {
    QueueSort.oldestFirst: 'Release date, oldest first',
    QueueSort.newestFirst: 'Release date, newest first',
    QueueSort.title: 'Title',
    QueueSort.podcast: 'Podcast',
    QueueSort.shortest: 'Time left, shortest first',
    QueueSort.longest: 'Time left, longest first',
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pin = context.read<PlayerController>().current?.id;
    final pal = Pal.of(context);
    final n = lib.queue.length;
    final left = lib.queueRemaining;
    final ends = DateTime.now().add(left);

    Future<void> clear() async {
      if (lib.settings.confirmClearQueue) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Clear Up Next?'),
            content: Text('This removes all $n episodes from Up Next.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      lib.clearQueue();
      if (context.mounted) showQueueUndo(context, lib, 'Up Next cleared');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: pal.header,
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pal.text,
                  ),
                ),
                Text(
                  n == 0
                      ? 'Nothing queued'
                      : '$n episodes  ·  ${fmtLong(lib.queueTotalLength, zero: '0 m')} total  ·  ${fmtLong(left, zero: 'nothing')} left  ·  ends about ${_clock(ends)}',
                  style: TextStyle(fontSize: 12, color: pal.muted),
                ),
              ],
            ),
          ),
          PopupMenuButton<QueueSort>(
            tooltip: 'Sort Up Next',
            enabled: n > 1,
            onSelected: (m) {
              lib.sortQueue(m, pinId: pin);
              showQueueUndo(context, lib, 'Up Next sorted');
            },
            itemBuilder: (c) => [
              for (final e in _labels.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort,
                    size: 18,
                    color: n > 1 ? null : Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sort',
                    style: TextStyle(
                      color: n > 1 ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: n > 1
                ? () {
                    lib.shuffleQueue(pinId: pin);
                    showQueueUndo(context, lib, 'Up Next shuffled');
                  }
                : null,
            icon: const Icon(Icons.shuffle, size: 18),
            label: const Text('Shuffle'),
          ),
          TextButton(
            onPressed: lib.queue.any((id) => lib.progressOf(id).played)
                ? () {
                    final removed = lib.removePlayedFromQueue();
                    showQueueUndo(context, lib, 'Removed $removed played');
                  }
                : null,
            child: const Text('Remove Played'),
          ),
          TextButton(
            onPressed: n > 0 ? clear : null,
            child: const Text('Clear'),
          ),
          TextButton.icon(
            onPressed: lib.canUndoQueue ? () => lib.undoQueue() : null,
            icon: const Icon(Icons.undo, size: 18),
            label: Text(
              lib.canUndoQueue ? 'Undo ${lib.queueUndoLabel}' : 'Undo',
            ),
          ),
        ],
      ),
    );
  }
}

// ---- sidebar ---------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.source,
    required this.onSelect,
    required this.onCustomize,
  });
  final _Source source;
  final ValueChanged<_Source> onSelect;
  final VoidCallback onCustomize;

  bool _is(_Source s) => switch ((source, s)) {
    (_Library a, _Library b) => a.kind == b.kind,
    (_Store(), _Store()) => true,
    (_Settings(), _Settings()) => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final dm = context.watch<DownloadManager>();
    final ui = lib.settings;
    final counts = ui.uiSidebarCounts;
    final anyLibrary =
        ui.uiNavPodcasts ||
        ui.uiNavEpisodes ||
        ui.uiNavUpNext ||
        ui.uiNavFavorites ||
        ui.uiNavHistory ||
        ui.uiNavDownloads ||
        ui.uiNavStats;
    final pal = Pal.of(context);
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 4),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: pal.muted,
        ),
      ),
    );
    Widget item(
      IconData icon,
      String label,
      _Source s, {
      bool? selected,
      int? count,
    }) {
      final sel = selected ?? _is(s);
      final row = InkWell(
        onTap: () => onSelect(s),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: sel ? pal.selected : null,
          child: Row(
            children: [
              Icon(icon, size: 16, color: sel ? Colors.white : pal.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: sel ? Colors.white : pal.text,
                  ),
                ),
              ),
              if (count != null && count > 0)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: sel ? Colors.white70 : pal.muted,
                  ),
                ),
            ],
          ),
        ),
      );
      if (s is! _Show) return row;
      return GestureDetector(
        onSecondaryTapDown: (d) => showPodcastMenu(
          context,
          Zoom.at(context, d.globalPosition),
          s.feedUrl,
          onOpen: (f) => onSelect(_Show(f)),
        ),
        child: row,
      );
    }

    return Container(
      width: lib.settings.sidebarWidth,
      color: pal.sidebar,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (d) => showSidebarMenu(
                context,
                Zoom.at(context, d.globalPosition),
                lib,
                onCustomize,
              ),
              child: ListView(
                children: [
                  if (anyLibrary) header('Library'),
                  if (ui.uiNavPodcasts)
                    item(
                      Icons.podcasts,
                      'Podcasts',
                      const _Library('podcasts'),
                      count: counts ? lib.subscriptions.length : null,
                    ),
                  if (ui.uiNavEpisodes)
                    item(
                      Icons.library_music,
                      'Episodes',
                      const _Library('episodes'),
                      count: counts ? lib.unplayedCount : null,
                    ),
                  if (ui.uiNavUpNext)
                    item(
                      Icons.queue_music,
                      'Up Next',
                      const _Library('queue'),
                      count: counts ? lib.queue.length : null,
                    ),
                  if (ui.uiNavFavorites)
                    item(
                      Icons.star,
                      'Favorites',
                      const _Library('favorites'),
                      count: counts ? lib.favoriteCount : null,
                    ),
                  if (ui.uiNavHistory)
                    item(
                      Icons.history,
                      'Recently Played',
                      const _Library('history'),
                    ),
                  if (ui.uiNavDownloads)
                    item(
                      dm.activeIds.isEmpty
                          ? Icons.download_done
                          : Icons.downloading,
                      'Downloads',
                      const _Library('downloads'),
                      count: counts
                          ? dm.doneCount +
                                dm.activeIds.length +
                                dm.queuedIds.length
                          : null,
                    ),
                  if (ui.uiNavStats)
                    item(
                      Icons.bar_chart,
                      'Statistics',
                      const _Library('stats'),
                    ),
                  if (ui.uiNavStore) ...[
                    header('Podcast Store'),
                    item(Icons.search, 'Find Podcasts', const _Store()),
                  ],
                  // Settings is always listed, so there is always a way back to these switches.
                  header('Settings'),
                  item(
                    lib.syncEnabled ? Icons.cloud_done : Icons.settings,
                    'Settings and Sync',
                    const _Settings(),
                  ),
                  if (ui.uiNavSubscriptions && lib.subscriptions.isNotEmpty)
                    header('Subscriptions'),
                  if (ui.uiNavSubscriptions)
                    for (final p in lib.subscriptions)
                      item(
                        Icons.rss_feed,
                        p.displayTitle,
                        _Show(p.feedUrl),
                        selected:
                            source is _Show &&
                            (source as _Show).feedUrl == p.feedUrl,
                      ),
                ],
              ),
            ),
          ),
          if (lib.settings.showArtworkPane &&
              context.select<PlayerController, bool>((p) => p.current != null))
            // Drag up to make the artwork bigger (as far as the sidebar is wide), down to shrink.
            HorizontalSplitter(
              onDrag: (dy) {
                final cur = lib.settings.artworkSize > 0
                    ? lib.settings.artworkSize
                    : lib.settings.sidebarWidth;
                lib.setSetting('artworkSize', (cur - dy).clamp(100.0, 480.0));
              },
              onReset: () => lib.setSetting('artworkSize', 0.0),
            ),
          if (lib.settings.showArtworkPane)
            _ArtworkPane(onGoToPodcast: (f) => onSelect(_Show(f))),
        ],
      ),
    );
  }
}

/// The square at the bottom of the iTunes sidebar showing what is playing.
class _ArtworkPane extends StatelessWidget {
  const _ArtworkPane({required this.onGoToPodcast});
  final ValueChanged<String> onGoToPodcast;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final e = context.select<PlayerController, Episode?>((p) => p.current);
    final width = context.select<Library, double>(
      (l) => l.settings.sidebarWidth,
    );
    final wanted = context.select<Library, double>(
      (l) => l.settings.artworkSize,
    );
    // As wide as the sidebar unless you dragged it smaller (it can never be wider than the sidebar).
    final size = (wanted > 0 ? wanted : width).clamp(100.0, width);
    final hide = Tooltip(
      message: 'Hide the artwork (View menu brings it back)',
      child: InkWell(
        onTap: () =>
            context.read<Library>().setSetting('showArtworkPane', false),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 12, color: Colors.white),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: pal.rule)),
      ),
      width: double.infinity,
      child: e == null
          ? SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  'Nothing playing',
                  style: TextStyle(fontSize: 11, color: pal.muted),
                ),
              ),
            )
          : Tooltip(
              message: e.title,
              child: Stack(
                children: [
                  InkWell(
                    onTap: () => onGoToPodcast(e.feedUrl),
                    child: Art(e.imageUrl, size: size, radius: 0),
                  ),
                  Positioned(top: 2, right: 2, child: hide),
                ],
              ),
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.toolbarTop, pal.toolbarBottom],
        ),
        border: Border(top: BorderSide(color: pal.rule)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: pal.text,
        ),
      ),
    );
  }
}

// ---- podcasts grid, show header, store ---------------------------------------

class _ShowHeader extends StatefulWidget {
  const _ShowHeader(this.feedUrl);
  final String feedUrl;

  @override
  State<_ShowHeader> createState() => _ShowHeaderState();
}

class _ShowHeaderState extends State<_ShowHeader> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final p = lib.podcasts[widget.feedUrl];
    final subscribed = lib.isSubscribed(widget.feedUrl);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.header,
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          Art(p?.imageUrl ?? '', size: 96, radius: 0),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p?.displayTitle ?? '',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pal.text,
                  ),
                ),
                Text(p?.author ?? '', style: TextStyle(color: pal.muted)),
                const SizedBox(height: 4),
                Text(
                  p?.description ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: pal.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (subscribed) ...[
            IconButton(
              tooltip: 'Filter episodes',
              icon: Icon(
                p != null && EpisodeView.isFiltered(p)
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              onPressed: () => showEpisodeFilter(context, widget.feedUrl),
            ),
            IconButton(
              tooltip: 'Sort episodes',
              icon: const Icon(Icons.sort),
              onPressed: () => showEpisodeSort(context, widget.feedUrl),
            ),
            IconButton(
              tooltip: 'Podcast settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showPodcastSettings(context, widget.feedUrl),
            ),
          ],
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      if (subscribed) {
                        lib.unsubscribe(widget.feedUrl);
                      } else {
                        await lib.subscribe(widget.feedUrl);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, 'Could not subscribe: $e');
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(subscribed ? 'Subscribed' : 'Subscribe'),
          ),
        ],
      ),
    );
  }
}
