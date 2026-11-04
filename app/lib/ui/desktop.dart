import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/feed.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'context_menus.dart';
import 'podcast_settings.dart';
import 'settings.dart';

/// iTunes 12 colours, in a light and a dark variant so text always sits on a
/// background it can be read against.
class Pal {
  const Pal({
    required this.bg,
    required this.toolbarTop,
    required this.toolbarBottom,
    required this.sidebar,
    required this.selected,
    required this.stripe,
    required this.rule,
    required this.text,
    required this.muted,
    required this.lcd,
    required this.field,
    required this.header,
  });

  final Color bg,
      toolbarTop,
      toolbarBottom,
      sidebar,
      selected,
      stripe,
      rule,
      text,
      muted,
      lcd,
      field,
      header;

  static const light = Pal(
    bg: Colors.white,
    toolbarTop: Color(0xFFF3F3F3),
    toolbarBottom: Color(0xFFD9D9D9),
    sidebar: Color(0xFFE6EBF1),
    selected: Color(0xFF3D80DF),
    stripe: Color(0xFFF3F6FA),
    rule: Color(0xFFBDBDBD),
    text: Color(0xDD000000),
    muted: Color(0xFF666666),
    lcd: Color(0xFFEFEFEF),
    field: Colors.white,
    header: Color(0xFFF7F7F7),
  );

  static const dark = Pal(
    bg: Color(0xFF1C1C1E),
    toolbarTop: Color(0xFF3A3A3C),
    toolbarBottom: Color(0xFF2C2C2E),
    sidebar: Color(0xFF232426),
    selected: Color(0xFF3D80DF),
    stripe: Color(0xFF242426),
    rule: Color(0xFF48484A),
    text: Color(0xDEFFFFFF),
    muted: Color(0xFFA0A0A5),
    lcd: Color(0xFF1F1F21),
    field: Color(0xFF2C2C2E),
    header: Color(0xFF2A2A2C),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

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

/// Desktop UI modelled on iTunes 12: transport + "LCD" toolbar on top, a
/// source-list sidebar, and a striped table of episodes.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // Places visited, like a browser: back and forward move along it, going somewhere new cuts off the forward part.
  final List<_Source> _history = [const _Library('episodes')];
  int _pos = 0;
  String filter = '';
  String storeQuery = '';
  List<SearchResult> storeResults = [];

  _Source get source => _history[_pos];
  bool get canGoBack => _pos > 0;
  bool get canGoForward => _pos < _history.length - 1;

  void _go(_Source s) {
    if (s == source) return;
    setState(() {
      _history.removeRange(_pos + 1, _history.length);
      _history.add(s);
      _pos++;
      filter = '';
    });
  }

  void _back() {
    if (canGoBack) setState(() => _pos--);
  }

  void _forward() {
    if (canGoForward) setState(() => _pos++);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _forward,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
            _back,
        const SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
            _forward,
      },
      child: Focus(
        autofocus: true,
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
                _Toolbar(
                  onSearch: (s) => setState(() => filter = s),
                  onSettings: () => _go(const _Settings()),
                  onBack: canGoBack ? _back : null,
                  onForward: canGoForward ? _forward : null,
                ),
                Expanded(
                  child: Row(
                    children: [
                      _Sidebar(source: source, onSelect: _go),
                      Container(width: 1, color: pal.rule),
                      Expanded(child: _content(lib)),
                    ],
                  ),
                ),
                _StatusBar(text: _status(lib)),
              ],
            ),
          ),
        ),
      ),
    );
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
    } else {
      return lib.syncing
          ? 'Syncing…'
          : (lib.syncError ?? (lib.syncEnabled ? 'Sync is on' : ''));
    }
    final total = Duration(
      milliseconds: eps.fold(0, (a, e) => a + e.durationMs),
    );
    final hours = total.inMinutes / 60;
    return '${eps.length} episodes, ${hours.toStringAsFixed(1)} hours';
  }

  Widget _content(Library lib) {
    final s = source;
    bool match(Episode e) =>
        filter.isEmpty ||
        e.title.toLowerCase().contains(filter.toLowerCase()) ||
        lib
            .podcastTitle(e.feedUrl)
            .toLowerCase()
            .contains(filter.toLowerCase());
    switch (s) {
      case _Library(kind: 'podcasts'):
        return _PodcastGrid(onOpen: (f) => _go(_Show(f)), filter: filter);
      case _Library(kind: 'queue'):
        return EpisodeTable(
          episodes: lib.queueEpisodes.where(match).toList(),
          queueMode: true,
          onGoToPodcast: (f) => _go(_Show(f)),
        );
      case _Library(kind: 'favorites'):
        return EpisodeTable(
          episodes: lib.favoriteEpisodes.where(match).toList(),
          emptyText: 'No favorites yet. Right-click an episode to add one.',
          onGoToPodcast: (f) => _go(_Show(f)),
        );
      case _Library(kind: 'history'):
        return EpisodeTable(
          episodes: lib.historyEpisodes.where(match).toList(),
          keepOrder: true,
          historyView: true,
          emptyText: 'Nothing played yet',
          onGoToPodcast: (f) => _go(_Show(f)),
        );
      case _Library():
        return EpisodeTable(
          episodes: lib.allEpisodes.where(match).toList(),
          onGoToPodcast: (f) => _go(_Show(f)),
        );
      case _Show(:final feedUrl):
        final eps = lib
            .episodesOf(feedUrl)
            .where(match)
            .where(
              (e) => !lib.settings.hidePlayed || !lib.progressOf(e.id).played,
            )
            .toList();
        return Column(
          children: [
            _ShowHeader(feedUrl),
            Expanded(
              child: EpisodeTable(episodes: eps, showPodcastColumn: false),
            ),
          ],
        );
      case _Store():
        return _StoreView(
          initialQuery: storeQuery,
          initialResults: storeResults,
          onSearched: (q, r) {
            storeQuery = q;
            storeResults = r;
          },
          onOpen: (f) => _go(_Show(f)),
        );
      case _Settings():
        return const SettingsPane();
    }
  }
}

// ---- toolbar ---------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onSearch,
    required this.onSettings,
    required this.onBack,
    required this.onForward,
  });
  final ValueChanged<String> onSearch;
  final VoidCallback onSettings;
  final VoidCallback? onBack; // null when there is nowhere to go back to
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.read<Library>();
    final pal = Pal.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: pal.rule),
    );
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            iconSize: 18,
            tooltip: 'Go back',
            onPressed: onBack,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            iconSize: 18,
            tooltip: 'Go forward',
            onPressed: onForward,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.fast_rewind),
            tooltip: 'Back ${lib.skipBackSec}s',
            onPressed: player.skipBack,
          ),
          IconButton(
            iconSize: 34,
            icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
            onPressed: player.current == null ? null : player.toggle,
          ),
          IconButton(
            icon: const Icon(Icons.fast_forward),
            tooltip: 'Forward ${lib.skipForwardSec}s',
            onPressed: player.skipForward,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Next in Up Next',
            onPressed: player.next,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _Lcd(player: player),
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () {
              const speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
              final feed = player.current?.feedUrl ?? '';
              final i = speeds.indexWhere(
                (s) => (s - lib.speedFor(feed)).abs() < 0.01,
              );
              player.setSpeed(speeds[(i + 1) % speeds.length]);
            },
            child: Text('${lib.speedFor(player.current?.feedUrl ?? '')}×'),
          ),
          SizedBox(
            width: 180,
            height: 30,
            child: TextField(
              onChanged: onSearch,
              style: TextStyle(fontSize: 13, color: pal.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.field,
                hintText: 'Search Library',
                hintStyle: TextStyle(color: pal.muted),
                prefixIcon: Icon(Icons.search, size: 16, color: pal.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: border,
                enabledBorder: border,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _Lcd extends StatelessWidget {
  const _Lcd({required this.player});
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<Library>();
    final pal = Pal.of(context);
    final e = player.current;
    final total = player.duration.inMilliseconds.toDouble();
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: pal.lcd,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: pal.rule),
      ),
      child: e == null
          ? Center(
              child: Text(
                'PodSync',
                style: TextStyle(fontSize: 18, color: pal.muted),
              ),
            )
          : Row(
              children: [
                Art(e.imageUrl, size: 46, radius: 0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: pal.text,
                          ),
                        ),
                        Text(
                          lib.podcastTitle(e.feedUrl),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: pal.muted),
                        ),
                        Row(
                          children: [
                            Text(
                              fmtDuration(player.position),
                              style: TextStyle(fontSize: 10, color: pal.text),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                                child: Slider(
                                  value: player.position.inMilliseconds
                                      .toDouble()
                                      .clamp(0, total > 0 ? total : 1),
                                  max: total > 0 ? total : 1,
                                  onChanged: total > 0
                                      ? (v) => player.seek(
                                          Duration(milliseconds: v.round()),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            Text(
                              total > 0
                                  ? '-${fmtDuration(player.duration - player.position)}'
                                  : '',
                              style: TextStyle(fontSize: 10, color: pal.text),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---- sidebar ---------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.source, required this.onSelect});
  final _Source source;
  final ValueChanged<_Source> onSelect;

  bool _is(_Source s) => switch ((source, s)) {
    (_Library a, _Library b) => a.kind == b.kind,
    (_Store(), _Store()) => true,
    (_Settings(), _Settings()) => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 4),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: pal.muted,
        ),
      ),
    );
    Widget item(IconData icon, String label, _Source s, {bool? selected}) {
      final sel = selected ?? _is(s);
      final row = InkWell(
        onTap: () => onSelect(s),
        child: Container(
          height: 26,
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
                    fontSize: 13,
                    color: sel ? Colors.white : pal.text,
                  ),
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
          d.globalPosition,
          s.feedUrl,
          onOpen: (f) => onSelect(_Show(f)),
        ),
        child: row,
      );
    }

    return Container(
      width: lib.settings.sidebarWidth,
      color: pal.sidebar,
      child: ListView(
        children: [
          header('LIBRARY'),
          item(Icons.podcasts, 'Podcasts', const _Library('podcasts')),
          item(Icons.library_music, 'Episodes', const _Library('episodes')),
          item(Icons.queue_music, 'Up Next', const _Library('queue')),
          item(Icons.star, 'Favorites', const _Library('favorites')),
          item(Icons.history, 'Recently Played', const _Library('history')),
          header('PODCAST STORE'),
          item(Icons.search, 'Find Podcasts', const _Store()),
          header('SETTINGS'),
          item(
            lib.syncEnabled ? Icons.cloud_done : Icons.settings,
            'Settings and Sync',
            const _Settings(),
          ),
          if (lib.subscriptions.isNotEmpty) header('SUBSCRIPTIONS'),
          for (final p in lib.subscriptions)
            item(
              Icons.rss_feed,
              p.displayTitle,
              _Show(p.feedUrl),
              selected:
                  source is _Show && (source as _Show).feedUrl == p.feedUrl,
            ),
        ],
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
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.toolbarTop, pal.toolbarBottom],
        ),
        border: Border(top: BorderSide(color: pal.rule)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: pal.muted)),
    );
  }
}

// ---- table -----------------------------------------------------------------

class EpisodeTable extends StatefulWidget {
  const EpisodeTable({
    super.key,
    required this.episodes,
    this.showPodcastColumn = true,
    this.queueMode = false,
    this.keepOrder = false,
    this.historyView = false,
    this.emptyText,
    this.onGoToPodcast,
  });
  final List<Episode> episodes;
  final bool showPodcastColumn;
  final bool queueMode;
  final bool keepOrder; // show in the given order (history), no column sorting
  final bool historyView;
  final String? emptyText;
  final ValueChanged<String>?
  onGoToPodcast; // "Go to Podcast" in the right-click menu

  @override
  State<EpisodeTable> createState() => _EpisodeTableState();
}

class _EpisodeTableState extends State<EpisodeTable> {
  String sortBy = 'date';
  bool? _asc; // null until the user clicks a header; then follows the "episode order" setting
  final Set<String> selected = {};
  final FocusNode _focus = FocusNode();
  String? _anchor; // where a shift-click range starts
  List<Episode> _shown = [];

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
    final fixedOrder = widget.queueMode || widget.keepOrder;
    // Selection only holds episodes that are still listed.
    selected.removeWhere((id) => !widget.episodes.any((e) => e.id == id));

    var eps = [...widget.episodes];
    if (!fixedOrder) {
      int cmp(Episode a, Episode b) => switch (sortBy) {
        'name' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'time' => a.durationMs.compareTo(b.durationMs),
        'podcast' =>
          lib.podcastTitle(a.feedUrl).compareTo(lib.podcastTitle(b.feedUrl)),
        _ => a.published.compareTo(b.published),
      };
      eps.sort((a, b) => asc ? cmp(a, b) : cmp(b, a));
    }

    Widget head(String label, String key, {double? width, int flex = 0}) {
      final active = sortBy == key && !fixedOrder;
      final child = InkWell(
        onTap: fixedOrder
            ? null
            : () => setState(() {
                if (sortBy == key) {
                  _asc = !asc;
                } else {
                  sortBy = key;
                  _asc = key != 'date';
                }
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
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
      return width != null
          ? SizedBox(width: width, child: child)
          : Expanded(flex: flex, child: child);
    }

    _shown = eps;
    final showPodcast = widget.showPodcastColumn && s.colPodcast;
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            setState(() => selected.addAll(_shown.map((x) => x.id))),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () =>
            setState(() => selected.addAll(_shown.map((x) => x.id))),
        const SingleActivator(LogicalKeyboardKey.enter): playSelected,
        // In Up Next, Delete takes the selected episodes off the queue.
        if (widget.queueMode)
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              lib.removeAllFromQueue(selected.toList()),
      },
      child: Focus(
        focusNode: _focus,
        child: Column(
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
                  const SizedBox(width: 28),
                  head('Name', 'name', flex: 4),
                  if (s.colTime) head('Time', 'time', width: 70),
                  if (showPodcast) head('Podcast', 'podcast', flex: 2),
                  if (s.colDate) head('Release Date', 'date', width: 120),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            Expanded(
              child: eps.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyText ??
                            (widget.queueMode
                                ? 'Up Next is empty. Right-click an episode to add it.'
                                : 'No episodes'),
                        style: TextStyle(color: pal.muted),
                      ),
                    )
                  : ListView.builder(
                      itemExtent: rowHeight,
                      itemCount: eps.length,
                      itemBuilder: (c, i) {
                        final e = eps[i];
                        final pr = lib.progressOf(e.id);
                        final sel = selected.contains(e.id);
                        final fg = sel
                            ? Colors.white
                            : (pr.played ? pal.muted : pal.text);
                        final st = TextStyle(
                          fontSize: 12,
                          color: fg,
                          fontWeight: currentId == e.id
                              ? FontWeight.bold
                              : null,
                        );
                        const pad = EdgeInsets.symmetric(horizontal: 6);
                        return GestureDetector(
                          onSecondaryTapDown: (d) {
                            // Right-clicking something outside the selection selects just that row first.
                            if (!selected.contains(e.id)) {
                              setState(() => _select(e, i));
                            }
                            showEpisodeMenu(
                              c,
                              d.globalPosition,
                              [
                                for (final x in _shown)
                                  if (selected.contains(x.id)) x,
                              ],
                              queueView: widget.queueMode,
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
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onDoubleTap: () => player.play(e),
                              child: Container(
                                color: sel
                                    ? pal.selected
                                    : (i.isOdd ? pal.stripe : pal.bg),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Center(
                                        child: currentId == e.id
                                            ? Icon(
                                                Icons.volume_up,
                                                size: 14,
                                                color: fg,
                                              )
                                            : (!pr.played && pr.positionMs == 0
                                                  ? Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: sel
                                                            ? Colors.white
                                                            : pal.selected,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    )
                                                  : null),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Padding(
                                        padding: pad,
                                        child: Text(
                                          e.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: st,
                                        ),
                                      ),
                                    ),
                                    if (s.colTime)
                                      SizedBox(
                                        width: 70,
                                        child: Padding(
                                          padding: pad,
                                          child: Text(
                                            fmtDurationMs(e.durationMs),
                                            style: st,
                                          ),
                                        ),
                                      ),
                                    if (showPodcast)
                                      Expanded(
                                        flex: 2,
                                        child: Padding(
                                          padding: pad,
                                          child: Text(
                                            lib.podcastTitle(e.feedUrl),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: st,
                                          ),
                                        ),
                                      ),
                                    if (s.colDate)
                                      SizedBox(
                                        width: 120,
                                        child: Padding(
                                          padding: pad,
                                          child: Text(
                                            fmtDate(e.published),
                                            style: st,
                                          ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: 36,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        iconSize: 16,
                                        color: fg,
                                        tooltip: 'Play',
                                        icon: const Icon(
                                          Icons.play_circle_outline,
                                        ),
                                        onPressed: () => player.play(e),
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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
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

// ---- podcasts grid, show header, store ---------------------------------------

class _PodcastGrid extends StatelessWidget {
  const _PodcastGrid({required this.onOpen, required this.filter});
  final ValueChanged<String> onOpen;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final subs = lib.subscriptions
        .where(
          (p) =>
              filter.isEmpty ||
              p.displayTitle.toLowerCase().contains(filter.toLowerCase()),
        )
        .toList();
    if (subs.isEmpty) {
      return Center(
        child: Text(
          'No podcasts. Use Find Podcasts to subscribe.',
          style: TextStyle(color: pal.muted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: subs.length,
      itemBuilder: (c, i) {
        final p = subs[i];
        return GestureDetector(
          onSecondaryTapDown: (d) =>
              showPodcastMenu(c, d.globalPosition, p.feedUrl, onOpen: onOpen),
          child: InkWell(
            onTap: () => onOpen(p.feedUrl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Art(p.imageUrl, size: 170, radius: 0),
                ),
                const SizedBox(height: 6),
                Text(
                  p.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pal.text,
                  ),
                ),
                Text(
                  p.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: pal.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
          if (subscribed)
            IconButton(
              tooltip: 'Podcast settings',
              icon: const Icon(Icons.tune),
              onPressed: () => showPodcastSettings(context, widget.feedUrl),
            ),
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

class _StoreView extends StatefulWidget {
  const _StoreView({
    required this.onOpen,
    required this.initialQuery,
    required this.initialResults,
    required this.onSearched,
  });
  final ValueChanged<String> onOpen;
  final String initialQuery;
  final List<SearchResult> initialResults;
  final void Function(String query, List<SearchResult> results)
  onSearched; // so going back finds the results again

  @override
  State<_StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<_StoreView> {
  late final controller = TextEditingController(text: widget.initialQuery);
  late List<SearchResult> results = widget.initialResults;
  bool busy = false;
  String? error;

  Future<void> _go() async {
    final q = controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (q.startsWith('http://') || q.startsWith('https://')) {
        await context.read<Library>().subscribe(q);
        if (mounted) widget.onOpen(q);
      } else {
        results = await searchDirectory(q);
        widget.onSearched(q, results);
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => _go(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText:
                        'Search the podcast directory, or paste a feed address',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : _go,
                child: const Text('Search'),
              ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (c, i) {
              final r = results[i];
              return GestureDetector(
                onSecondaryTapDown: (d) {
                  lib.podcasts.putIfAbsent(
                    r.feedUrl,
                    () => Podcast(
                      feedUrl: r.feedUrl,
                      title: r.title,
                      author: r.author,
                      imageUrl: r.imageUrl,
                      subscribed: false,
                    ),
                  );
                  showPodcastMenu(
                    c,
                    d.globalPosition,
                    r.feedUrl,
                    onOpen: widget.onOpen,
                  );
                },
                child: ListTile(
                  dense: true,
                  leading: Art(r.imageUrl, size: 44, radius: 0),
                  title: Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    r.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: lib.isSubscribed(r.feedUrl)
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () async {
                    lib.podcasts.putIfAbsent(
                      r.feedUrl,
                      () => Podcast(
                        feedUrl: r.feedUrl,
                        title: r.title,
                        author: r.author,
                        imageUrl: r.imageUrl,
                        subscribed: false,
                      ),
                    );
                    try {
                      await lib.refreshFeed(r.feedUrl);
                    } catch (_) {}
                    widget.onOpen(r.feedUrl);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
