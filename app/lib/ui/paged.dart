import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';

/// A list that never scrolls: it shows as many fixed-height rows as fit and
/// moves between pages with Prev/Next buttons or a horizontal swipe.
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.items,
    required this.itemExtent,
    required this.itemBuilder,
    this.empty = 'Nothing here',
    this.extentOf,
    this.keepWithNext,
  });

  final List<T> items;
  final double itemExtent;

  /// Row height for one item, when rows differ (a heading is shorter than a setting).
  final double Function(T)? extentOf;

  /// Items (headings) that must not be left alone at the bottom of a page.
  final bool Function(T)? keepWithNext;
  final Widget Function(BuildContext, T) itemBuilder;
  final String empty;

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  int page = 0;
  static const barHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final swipe = context.read<Library>().settings.einkSwipe;
        // Bigger text needs taller rows, or fixed-height rows would clip.
        final scale = max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
        double extentFor(T item) =>
            (widget.extentOf?.call(item) ?? widget.itemExtent) * scale;
        final inset = MediaQuery.viewPaddingOf(context).bottom;
        final avail = c.maxHeight - barHeight - inset;
        // Fill each page with as many rows as fit; a heading never ends a page on its own.
        final ranges = <(int, int)>[];
        final all = widget.items;
        var from = 0;
        while (from < all.length) {
          var to = from;
          var used = 0.0;
          while (to < all.length &&
              (to == from || used + extentFor(all[to]) <= avail + 0.5)) {
            used += extentFor(all[to]);
            to++;
          }
          if (to < all.length &&
              to - from > 1 &&
              (widget.keepWithNext?.call(all[to - 1]) ?? false)) {
            to--;
          }
          ranges.add((from, to));
          from = to;
        }
        final pages = ranges.isEmpty ? 1 : ranges.length;
        if (page >= pages) page = pages - 1;
        final slice = ranges.isEmpty
            ? <T>[]
            : all.sublist(ranges[page].$1, ranges[page].$2);

        void go(int delta) {
          final n = (page + delta).clamp(0, pages - 1);
          if (n != page) setState(() => page = n);
        }

        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: !swipe
                    ? null
                    : (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v < -200) go(1);
                        if (v > 200) go(-1);
                      },
                child: widget.items.isEmpty
                    ? Center(
                        child: Text(
                          widget.empty,
                          style: const TextStyle(fontSize: 20),
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in slice)
                            SizedBox(
                              height: extentFor(item),
                              child: widget.itemBuilder(context, item),
                            ),
                        ],
                      ),
              ),
            ),
            SizedBox(
              height: barHeight + inset,
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: page > 0 ? () => go(-1) : null,
                        child: const Text(
                          '←  Prev',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    Text(
                      '${page + 1} / $pages',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: page < pages - 1 ? () => go(1) : null,
                        child: const Text(
                          'Next  →',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Long text split into screen-sized pages (for episode notes in e-ink mode).
class PagedText extends StatefulWidget {
  const PagedText(
    this.text, {
    super.key,
    this.style = const TextStyle(fontSize: 20, height: 1.35),
  });
  final String text;
  final TextStyle style;

  @override
  State<PagedText> createState() => _PagedTextState();
}

class _PagedTextState extends State<PagedText> {
  int page = 0;

  List<String> _paginate(double w, double h) {
    final pages = <String>[];
    var rest = widget.text.trim();
    if (rest.isEmpty) return [''];
    while (rest.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: rest, style: widget.style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      if (tp.height <= h) {
        pages.add(rest);
        break;
      }
      var end = tp
          .getPositionForOffset(Offset(w, h - widget.style.fontSize!))
          .offset;
      final space = rest.lastIndexOf(RegExp(r'\s'), end);
      if (space > end * 0.6) end = space;
      if (end <= 0) end = rest.length.clamp(1, 200);
      pages.add(rest.substring(0, end).trim());
      rest = rest.substring(end).trim();
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final pages = _paginate(c.maxWidth, c.maxHeight - 56);
        if (page >= pages.length) page = pages.length - 1;
        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -200 && page < pages.length - 1) {
                    setState(() => page++);
                  }
                  if (v > 200 && page > 0) setState(() => page--);
                },
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(pages[page], style: widget.style),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: page > 0 ? () => setState(() => page--) : null,
                      child: const Text(
                        '←  Prev',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  Text(
                    '${page + 1} / ${pages.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: page < pages.length - 1
                          ? () => setState(() => page++)
                          : null,
                      child: const Text(
                        'Next  →',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
