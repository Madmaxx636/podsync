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
  }

  Future<void> loadTop() => _run(() async {
    final mine = _generation;
    final r = await directory.top(genreId: genreId, limit: 30);
    if (mine == _generation) top = r;
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
            _CoverGrid(podcasts: shown, onOpen: widget.onOpen),
          ],
        );
      }
      final shelf = shown.take(12).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(
            store.genreId == null ? 'Top Podcasts' : 'Top ${store.genreName}',
          ),
          _CoverGrid(podcasts: shelf, onOpen: widget.onOpen),
          title(
            'Top Charts',
            sub: store.genreId == null ? 'All categories' : store.genreName,
          ),
          _ChartColumns(podcasts: shown, onOpen: widget.onOpen),
          const SizedBox(height: 30),
        ],
      );
    }

    return Column(
      children: [
        header(),
        if (store.loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(child: ListView(children: [body()])),
      ],
    );
  }
}

/// Covers in a wrapping grid, each with its title, author and Subscribe pill.
class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.podcasts, required this.onOpen});
  final List<StorePodcast> podcasts;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisExtent: 292,
          mainAxisSpacing: 14,
          crossAxisSpacing: 18,
        ),
        itemCount: podcasts.length,
        itemBuilder: (c, i) => _Cover(podcasts[i], onOpen: onOpen),
      ),
    );
  }
}

class _Cover extends StatefulWidget {
  const _Cover(this.p, {required this.onOpen});
  final StorePodcast p;
  final ValueChanged<String> onOpen;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = widget.p;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) {
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
            onOpen: widget.onOpen,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => openStorePodcast(context, p, widget.onOpen),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: hover ? 0.35 : 0.2),
                      blurRadius: hover ? 12 : 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Art(p.imageUrl, size: 190, radius: 8),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => openStorePodcast(context, p, widget.onOpen),
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
            Align(
              alignment: Alignment.centerLeft,
              child: SubscribePill(p, compact: true),
            ),
          ],
        ),
      ),
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
