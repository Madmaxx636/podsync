import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/directory.dart';
import '../core/errors.dart';
import '../core/library.dart';
import '../core/models.dart';
import 'common.dart';
import 'context_menus.dart';
import 'paged.dart';
import 'pal.dart';
import 'zoom.dart';

/// What the store is showing: the chart for the chosen category, or search results. It lives for
/// the whole session, so going to a podcast and back finds the page as you left it.
class StoreController extends ChangeNotifier {
  StoreController(this.directory, this.library);

  final StoreDirectory directory;
  final Library library;

  String query = '';
  int? genreId;
  List<StorePodcast> results = const [];
  List<StorePodcast> top = const [];
  bool loading = false;
  String? error;
  int _generation = 0; // a newer request makes older answers irrelevant

  /// The shelves under the top charts on the front page: a dozen of the top podcasts of each of
  /// these categories, loaded one by one in the background.
  static const shelfGenres = [1489, 1303, 1318, 1324, 1321, 1488, 1533, 1545];
  final Map<int, List<StorePodcast>> shelves = {};
  final Set<int> _loadingShelves = {};

  void loadShelves() {
    if (searching || genreId != null) return;
    _applyCountry();
    for (final id in shelfGenres) {
      if (shelves.containsKey(id) || !_loadingShelves.add(id)) continue;
      directory
          .top(genreId: id, limit: 14)
          .then((r) {
            shelves[id] = r;
            notifyListeners();
          })
          .catchError((Object _) {
            // A shelf that fails is just left out; the chart above still works.
          })
          .whenComplete(() => _loadingShelves.remove(id));
    }
  }

  bool get searching => query.isNotEmpty;
  String get genreName =>
      storeGenres.where((g) => g.id == genreId).firstOrNull?.name ??
      'All Categories';

  void _applyCountry() {
    final c = library.settings.storeCountry.trim().toLowerCase();
    directory.country = c.length == 2 ? c : 'us';
  }

  Future<void> _run(Future<void> Function() work) async {
    final mine = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      _applyCountry();
      await work();
    } catch (e) {
      if (mine == _generation) error = cleanError(e);
    } finally {
      if (mine == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Loads the chart the first time the store is opened.
  Future<void> ensureTop() async {
    if (top.isEmpty && !loading && error == null) await loadTop();
    loadShelves();
  }

  Future<void> loadTop() => _run(() async {
    final mine = _generation;
    final r = await directory.top(genreId: genreId, limit: 30);
    if (mine == _generation) top = r;
    loadShelves();
  });

  Future<void> search(String text) async {
    query = text.trim();
    if (query.isEmpty) {
      results = const [];
      _generation++;
      error = null;
      loading = false;
      notifyListeners();
      return ensureTop();
    }
    await _run(() async {
      final mine = _generation;
      final r = await directory.search(query, genreId: genreId);
      if (mine == _generation) results = r;
    });
  }

  void setGenre(int? id) {
    genreId = id;
    shelves.clear();
    _loadingShelves.clear();
    top = const [];
    error = null;
    if (searching) {
      search(query);
    } else {
      loadTop();
    }
  }

  /// Re-asks the store after a failure or a change of country.
  Future<void> retry() => searching ? search(query) : loadTop();
}

/// Puts a store podcast in the library (not subscribed) so its page can show at once, and
/// fetches its episodes in the background.
void openStorePodcast(
  BuildContext context,
  StorePodcast p,
  ValueChanged<String> onOpen,
) {
  final lib = context.read<Library>();
  lib.podcasts.putIfAbsent(
    p.feedUrl,
    () => Podcast(
      feedUrl: p.feedUrl,
      title: p.title,
      author: p.author,
      imageUrl: p.imageUrl,
      subscribed: false,
    ),
  );
  onOpen(p.feedUrl);
  lib.refreshFeed(p.feedUrl).catchError((Object e) {
    if (context.mounted) {
      showSnack(context, 'Could not load ${p.title}: ${cleanError(e)}');
    }
  });
}

/// The blue "Subscribe" pill of the iTunes Store; becomes "Subscribed" once you are.
class SubscribePill extends StatefulWidget {
  const SubscribePill(this.podcast, {super.key, this.compact = false});
  final StorePodcast podcast;
  final bool compact;

  @override
  State<SubscribePill> createState() => _SubscribePillState();
}

class _SubscribePillState extends State<SubscribePill> {
  bool busy = false;

  Future<void> _subscribe() async {
    final lib = context.read<Library>();
    final p = widget.podcast;
    setState(() => busy = true);
    lib.podcasts.putIfAbsent(
      p.feedUrl,
      () => Podcast(
        feedUrl: p.feedUrl,
        title: p.title,
        author: p.author,
        imageUrl: p.imageUrl,
        subscribed: false,
      ),
    );
    try {
      await lib.subscribe(p.feedUrl);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not subscribe: ${cleanError(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = context.select<Library, bool>(
      (l) => l.isSubscribed(widget.podcast.feedUrl),
    );
    final scheme = Theme.of(context).colorScheme;
    final label = subscribed ? 'Subscribed' : 'Subscribe';
    final style = TextStyle(
      fontSize: widget.compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      color: subscribed ? scheme.outline : scheme.primary,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: subscribed || busy ? null : _subscribe,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : 14,
          vertical: widget.compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: subscribed ? null : scheme.primary.withValues(alpha: 0.10),
          border: subscribed ? Border.all(color: scheme.outlineVariant) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (subscribed)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(Icons.check, size: 14, color: scheme.outline),
                    ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---- desktop ----------------------------------------------------------------------

/// The desktop podcast store, laid out like the iTunes Store: a search bar and category menu on
/// top, then the top podcasts as covers and the full chart as a ranked list.
class StoreView extends StatefulWidget {
  const StoreView({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;

  @override
  State<StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<StoreView> {
  late final StoreController store = context.read<StoreController>();
  late final TextEditingController field = TextEditingController(
    text: store.query,
  );
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // After this frame: loading announces itself to listeners, which is not allowed mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => store.ensureTop());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    field.dispose();
    super.dispose();
  }

  /// A pasted feed address subscribes directly; anything else is a search.
  Future<void> _submit(String text) async {
    final q = text.trim();
    if (q.startsWith('http://') || q.startsWith('https://')) {
      final lib = context.read<Library>();
      try {
        await lib.subscribe(q);
        if (mounted) widget.onOpen(q);
      } catch (e) {
        if (mounted) {
          showSnack(context, 'Could not subscribe: ${cleanError(e)}');
        }
      }
      return;
    }
    store.search(q);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<StoreController>();
    final pal = Pal.of(context);
    final scheme = Theme.of(context).colorScheme;
    final shown = store.searching ? store.results : store.top;

    Widget header() => Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: BoxDecoration(
        color: pal.header,
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          Text(
            'Podcasts',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: pal.text,
            ),
          ),
          const Spacer(),
          PopupMenuButton<int>(
            tooltip: 'Categories',
            onSelected: (id) => store.setGenre(id == 0 ? null : id),
            itemBuilder: (c) => [
              CheckedPopupMenuItem(
                value: 0,
                checked: store.genreId == null,
                child: const Text('All Categories'),
              ),
              const PopupMenuDivider(),
              for (final g in storeGenres)
                CheckedPopupMenuItem(
                  value: g.id,
                  checked: store.genreId == g.id,
                  child: Text(g.name),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    store.genreName,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: scheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 300,
            height: 34,
            child: TextField(
              controller: field,
              onSubmitted: _submit,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  if (mounted && !v.trim().startsWith('http')) store.search(v);
                });
                setState(() {}); // shows or hides the clear button
              },
              style: TextStyle(fontSize: 14, color: pal.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.field,
                hintText: 'Search podcasts or paste a feed address',
                hintStyle: TextStyle(color: pal.muted),
                prefixIcon: Icon(Icons.search, size: 18, color: pal.muted),
                suffixIcon: field.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: Icon(Icons.cancel, size: 16, color: pal.muted),
                        onPressed: () {
                          field.clear();
                          store.search('');
                          setState(() {});
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide(color: pal.rule),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide(color: pal.rule),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget title(String text, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: pal.text,
            ),
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                sub,
                style: TextStyle(fontSize: 13, color: pal.muted),
              ),
            ),
        ],
      ),
    );

    Widget body() {
      if (store.error != null && shown.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.cloud_off, size: 40, color: pal.muted),
              const SizedBox(height: 10),
              Text(
                'The store could not be reached',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: pal.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                store.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.muted),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: store.retry,
                child: const Text('Try Again'),
              ),
            ],
          ),
        );
      }
      if (shown.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(60),
          child: Center(
            child: Text(
              store.loading
                  ? ''
                  : (store.searching
                        ? 'No podcasts found for “${store.query}”'
                        : 'No podcasts to show'),
              style: TextStyle(fontSize: 15, color: pal.muted),
            ),
          ),
        );
      }
      if (store.searching) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title(
              'Results for “${store.query}”',
              sub: '${shown.length} podcasts',
            ),
            for (final p in shown) _ResultRow(p, onOpen: widget.onOpen),
            const SizedBox(height: 24),
          ],
        );
      }
      final front = <Widget>[
        _Hero(podcasts: shown.take(5).toList(), onOpen: widget.onOpen),
        _Shelf(
          title: store.genreId == null
              ? 'Top Podcasts'
              : 'Top ${store.genreName}',
          podcasts: shown.take(14).toList(),
          onOpen: widget.onOpen,
        ),
        if (store.genreId == null)
          for (final id in StoreController.shelfGenres)
            if (store.shelves[id]?.isNotEmpty ?? false)
              _Shelf(
                title: storeGenres.firstWhere((g) => g.id == id).name,
                podcasts: store.shelves[id]!,
                onOpen: widget.onOpen,
                onSeeAll: () => store.setGenre(id),
              ),
        title(
          'Top Charts',
          sub: store.genreId == null ? 'All categories' : store.genreName,
        ),
        _ChartColumns(podcasts: shown, onOpen: widget.onOpen),
        const SizedBox(height: 30),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: front,
      );
    }

    return Column(
      children: [
        header(),
        if (store.loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final main = ListView(children: [body()]);
              // Wide windows get the category list down the right side, like the iTunes Store's
              // Podcast Quick Links.
              if (c.maxWidth < 1000) return main;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: main),
                  _CategoryColumn(store: store),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The ranked chart, in up to three columns like the iTunes Store's Top Charts.
class _ChartColumns extends StatelessWidget {
  const _ChartColumns({required this.podcasts, required this.onOpen});
  final List<StorePodcast> podcasts;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 380).floor().clamp(1, 3);
        final perColumn = (podcasts.length / columns).ceil();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < columns; col++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == columns - 1 ? 0 : 20,
                    ),
                    child: Column(
                      children: [
                        for (
                          var i = col * perColumn;
                          i < (col + 1) * perColumn && i < podcasts.length;
                          i++
                        )
                          _ChartRow(
                            rank: i + 1,
                            p: podcasts[i],
                            onOpen: onOpen,
                          ),
                      ],
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

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.rank, required this.p, required this.onOpen});
  final int rank;
  final StorePodcast p;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return InkWell(
      onTap: () => openStorePodcast(context, p, onOpen),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: pal.rule.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: pal.muted,
                ),
              ),
            ),
            Art(p.imageUrl, size: 54, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: pal.text,
                    ),
                  ),
                  Text(
                    p.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: pal.muted),
                  ),
                  if (p.genre.isNotEmpty)
                    Text(
                      p.genre,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, color: pal.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SubscribePill(p, compact: true),
          ],
        ),
      ),
    );
  }
}

// ---- phone ------------------------------------------------------------------------

/// The phone version: search, a category picker and a ranked list. On e-ink the list is paged.
class PhoneStore extends StatefulWidget {
  const PhoneStore({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;

  @override
  State<PhoneStore> createState() => _PhoneStoreState();
}

class _PhoneStoreState extends State<PhoneStore> {
  late final StoreController store = context.read<StoreController>();
  late final TextEditingController field = TextEditingController(
    text: store.query,
  );

  @override
  void initState() {
    super.initState();
    // After this frame: loading announces itself to listeners, which is not allowed mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => store.ensureTop());
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    final q = text.trim();
    if (q.startsWith('http://') || q.startsWith('https://')) {
      try {
        await context.read<Library>().subscribe(q);
        if (mounted) {
          showSnack(context, 'Subscribed');
          field.clear();
        }
      } catch (e) {
        if (mounted) {
          showSnack(context, 'Could not subscribe: ${cleanError(e)}');
        }
      }
      return;
    }
    store.search(q);
  }

  Future<void> _pickGenre() async {
    final choice = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Category'),
        children: [
          SizedBox(
            width: 300,
            height: 420,
            child: ListView(
              children: [
                ListTile(
                  dense: true,
                  title: const Text('All Categories'),
                  trailing: store.genreId == null
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(c, 0),
                ),
                for (final g in storeGenres)
                  ListTile(
                    dense: true,
                    title: Text(g.name),
                    trailing: store.genreId == g.id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(c, g.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice != null) store.setGenre(choice == 0 ? null : choice);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<StoreController>();
    final eink = context.select<Library, bool>((l) => l.einkMode);
    final shown = store.searching ? store.results : store.top;

    Widget row(BuildContext c, StorePodcast p) {
      final rank = shown.indexOf(p) + 1;
      return InkWell(
        onTap: () => openStorePodcast(c, p, widget.onOpen),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (!store.searching)
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                ),
              Art(p.imageUrl, size: 60, radius: 6, gray: eink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      p.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SubscribePill(p, compact: true),
            ],
          ),
        ),
      );
    }

    final Widget list;
    if (store.error != null && shown.isEmpty) {
      list = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 36),
              const SizedBox(height: 8),
              const Text('The store could not be reached'),
              Text(
                store.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: store.retry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else if (eink) {
      list = PagedList<StorePodcast>(
        items: shown,
        itemExtent: 88,
        itemBuilder: row,
        empty: store.loading
            ? 'Loading…'
            : (store.searching ? 'Nothing found' : 'Search for a podcast'),
      );
    } else if (shown.isEmpty) {
      list = Center(
        child: Text(
          store.loading
              ? ''
              : (store.searching
                    ? 'No podcasts found for “${store.query}”'
                    : 'Search for a podcast'),
        ),
      );
    } else {
      list = ListView.builder(
        itemCount: shown.length,
        itemExtent: 88,
        itemBuilder: (c, i) => row(c, shown[i]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: field,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search podcasts or paste a feed address',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => _submit(field.text),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  store.searching
                      ? 'Results for “${store.query}”'
                      : (store.genreId == null
                            ? 'Top podcasts'
                            : 'Top ${store.genreName}'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: _pickGenre,
                icon: const Icon(Icons.category_outlined, size: 18),
                label: Text(store.genreName),
              ),
            ],
          ),
        ),
        if (store.loading && !eink) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: list),
      ],
    );
  }
}

// ---- front page pieces -------------------------------------------------------------------

/// The big banner at the top: the number one podcast with its cover, summary and Subscribe, and
/// arrows to move through the next four.
class _Hero extends StatefulWidget {
  const _Hero({required this.podcasts, required this.onOpen});
  final List<StorePodcast> podcasts;
  final ValueChanged<String> onOpen;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.podcasts.isEmpty) return const SizedBox.shrink();
    final pal = Pal.of(context);
    final n = widget.podcasts.length;
    final i = _i.clamp(0, n - 1);
    final p = widget.podcasts[i];
    Widget arrow(IconData icon, int by) => IconButton(
      tooltip: by < 0 ? 'Previous' : 'Next',
      icon: Icon(icon, size: 30, color: pal.muted),
      onPressed: n < 2 ? null : () => setState(() => _i = (i + by + n) % n),
    );
    return GestureDetector(
      onSecondaryTapDown: (d) => _storeMenu(context, d, p, widget.onOpen),
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pal.header, pal.stripe],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: pal.rule),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            arrow(Icons.chevron_left, -1),
            GestureDetector(
              onSecondaryTapDown: (d) =>
                  _storeMenu(context, d, p, widget.onOpen),
              child: InkWell(
                onTap: () => openStorePodcast(context, p, widget.onOpen),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Art(p.imageUrl, size: 180, radius: 8),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${i + 1} IN PODCASTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: pal.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => openStorePodcast(context, p, widget.onOpen),
                    child: Text(
                      p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: pal.text,
                      ),
                    ),
                  ),
                  Text(
                    [p.author, p.genre].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 14, color: pal.muted),
                  ),
                  if (p.summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      p.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: pal.text,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SubscribePill(p),
                      const Spacer(),
                      for (var d = 0; d < n; d++)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d == i
                                ? pal.selected
                                : pal.muted.withValues(alpha: 0.35),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            arrow(Icons.chevron_right, 1),
          ],
        ),
      ),
    );
  }
}

/// A row of covers that scrolls sideways (arrows at the right of the heading move it), with the
/// heading and, for a category, "See All".
class _Shelf extends StatefulWidget {
  const _Shelf({
    required this.title,
    required this.podcasts,
    required this.onOpen,
    this.onSeeAll,
  });
  final String title;
  final List<StorePodcast> podcasts;
  final ValueChanged<String> onOpen;
  final VoidCallback? onSeeAll;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(int dir) {
    if (!_scroll.hasClients) return;
    final step = _scroll.position.viewportDimension * 0.8;
    _scroll.animateTo(
      (_scroll.offset + dir * step).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (widget.podcasts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Row(
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: pal.text,
                ),
              ),
              if (widget.onSeeAll != null)
                TextButton(
                  onPressed: widget.onSeeAll,
                  child: Text(
                    'See All >',
                    style: TextStyle(fontSize: 12.5, color: scheme.primary),
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Scroll left',
                icon: Icon(Icons.chevron_left, color: pal.muted),
                onPressed: () => _move(-1),
              ),
              IconButton(
                tooltip: 'Scroll right',
                icon: Icon(Icons.chevron_right, color: pal.muted),
                onPressed: () => _move(1),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 268,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: widget.podcasts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (c, i) => SizedBox(
              width: 150,
              child: _ShelfTile(widget.podcasts[i], onOpen: widget.onOpen),
            ),
          ),
        ),
      ],
    );
  }
}

/// Right-click on a store podcast: the same menu as for one you already have.
void _storeMenu(
  BuildContext context,
  TapDownDetails d,
  StorePodcast p,
  ValueChanged<String> onOpen,
) {
  context.read<Library>().podcasts.putIfAbsent(
    p.feedUrl,
    () => Podcast(
      feedUrl: p.feedUrl,
      title: p.title,
      author: p.author,
      imageUrl: p.imageUrl,
      subscribed: false,
    ),
  );
  showPodcastMenu(
    context,
    Zoom.at(context, d.globalPosition),
    p.feedUrl,
    onOpen: onOpen,
  );
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile(this.p, {required this.onOpen});
  final StorePodcast p;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return GestureDetector(
      onSecondaryTapDown: (d) => _storeMenu(context, d, p, onOpen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => openStorePodcast(context, p, onOpen),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Art(p.imageUrl, size: 150, radius: 6),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => openStorePodcast(context, p, onOpen),
            child: Text(
              p.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: pal.text,
              ),
            ),
          ),
          Text(
            p.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: pal.muted),
          ),
          const Spacer(),
          SubscribePill(p, compact: true),
        ],
      ),
    );
  }
}

/// A search result: cover, name, author and category, the start of the description and a
/// Subscribe button, in a row rather than a tile so there is room to say what it is.
class _ResultRow extends StatelessWidget {
  const _ResultRow(this.p, {required this.onOpen});
  final StorePodcast p;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return InkWell(
      onTap: () => openStorePodcast(context, p, onOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: pal.rule.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Art(p.imageUrl, size: 76, radius: 6),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: pal.text,
                    ),
                  ),
                  Text(
                    [p.author, p.genre].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: pal.muted),
                  ),
                  if (p.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        p.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: pal.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SubscribePill(p),
          ],
        ),
      ),
    );
  }
}

/// "All Categories" and each category as a plain list down the right side; the open one is bold.
class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({required this.store});
  final StoreController store;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget link(String text, int? id) {
      final sel = store.genreId == id;
      return InkWell(
        onTap: () => store.setGenre(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
              color: sel ? pal.text : scheme.primary,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: pal.rule.withValues(alpha: 0.6)),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Categories',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: pal.muted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            link('All Podcasts', null),
            for (final g in storeGenres) link(g.name, g.id),
          ],
        ),
      ),
    );
  }
}
