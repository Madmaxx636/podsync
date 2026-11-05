import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';
import '../core/settings.dart';

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String fmtDurationMs(int ms) =>
    ms <= 0 ? '' : fmtDuration(Duration(milliseconds: ms));

const _mon = [
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

String fmtDate(int ms, {bool year = true}) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  switch (currentDateStyle) {
    case 'iso':
      return year
          ? '${d.year}-${two(d.month)}-${two(d.day)}'
          : '${two(d.month)}-${two(d.day)}';
    case 'dmy':
      return year
          ? '${d.day} ${_mon[d.month - 1]} ${d.year}'
          : '${d.day} ${_mon[d.month - 1]}';
    default:
      return year
          ? '${_mon[d.month - 1]} ${d.day}, ${d.year}'
          : '${_mon[d.month - 1]} ${d.day}';
  }
}

/// Podcast / episode artwork with a neutral placeholder.
class Art extends StatelessWidget {
  const Art(
    this.url, {
    super.key,
    this.size = 56,
    this.radius = 4,
    this.gray = false,
  });
  final String url;
  final double size;
  final double radius;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    final settings = context.select<Library, AppSettings>((l) => l.settings);
    final showArt = settings.showArtwork;
    final grayscale = gray && settings.einkGrayArt;
    final placeholder = Container(
      width: size,
      height: size,
      color: Colors.grey.shade300,
      child: Icon(
        Icons.podcasts,
        size: size * 0.5,
        color: Colors.grey.shade600,
      ),
    );
    Widget img = url.isEmpty || !showArt
        ? placeholder
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (_, child, p) => p == null ? child : placeholder,
          );
    if (grayscale && url.isNotEmpty && showArt) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Lets the user pick a file and copies it to a temp file, because on Android a pick
/// is a content:// URI with no path. The caller deletes the returned file.
Future<File?> pickTempFile() async {
  final picked = await FilePicker.pickFiles(type: FileType.any);
  if (picked.isEmpty) return null;
  final tmp = File(
    '${(await getTemporaryDirectory()).path}/import-${DateTime.now().microsecondsSinceEpoch}-${picked.first.name}',
  );
  final sink = tmp.openWrite();
  await sink.addStream(picked.first.readAsByteStream());
  await sink.close();
  return tmp;
}

/// Format used for "starts in" and queue totals: "Next", "42 m", "2 h 05 m".
String fmtLong(Duration d, {String zero = ''}) {
  if (d <= Duration.zero) return zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return d.inMinutes == 0 ? '<1 m' : '$m m';
  return '$h h ${m.toString().padLeft(2, '0')} m';
}

/// Five clickable stars, like iTunes' rating column. Clicking the current rating clears it.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 13,
    this.color,
    this.emptyColor,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  final Color? color;
  final Color? emptyColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          // A pointer-down listener, so the star responds at once even inside a row that also handles double-clicks.
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (e.buttons == kPrimaryButton) onChanged(value == i ? 0 : i);
            },
            child: Icon(
              i <= value ? Icons.star : Icons.star_border,
              size: size,
              color: i <= value ? color : (emptyColor ?? color),
            ),
          ),
      ],
    );
  }
}

/// "Up Next sorted" with an Undo button that puts the queue back.
void showQueueUndo(BuildContext context, Library lib, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        // A snackbar with an action stays up until dismissed unless told otherwise.
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: () => lib.undoQueue()),
      ),
    );
}

/// "12.4 MB", "1.3 GB".
String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

/// An icon button that responds the moment the mouse goes down, even inside a row that also
/// handles double-clicks (a normal button there would wait out the double-click window).
/// Touch input fires on release, if the finger did not drag, so scrolling past it is safe.
class InstantIconButton extends StatefulWidget {
  const InstantIconButton({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    required this.onTap,
    this.size = 16,
    this.color,
    this.width,
    this.height,
  });
  final IconData? icon;
  final Widget? child; // replaces the icon, e.g. a progress ring
  final String tooltip;
  final VoidCallback? onTap; // null = shown but inactive
  final double size;
  final Color? color;
  final double? width;
  final double? height;

  @override
  State<InstantIconButton> createState() => _InstantIconButtonState();
}

class _InstantIconButtonState extends State<InstantIconButton> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (onTap == null) return;
            if (e.kind == PointerDeviceKind.touch) {
              _down = e.position;
            } else if (e.buttons == kPrimaryButton) {
              onTap();
            }
          },
          onPointerUp: (e) {
            final start = _down;
            _down = null;
            if (onTap != null &&
                start != null &&
                (e.position - start).distance < 18) {
              onTap();
            }
          },
          child: SizedBox(
            width: widget.width ?? widget.size + 14,
            height: widget.height ?? widget.size + 10,
            child: Center(
              child:
                  widget.child ??
                  Icon(widget.icon, size: widget.size, color: widget.color),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain bordered button for e-ink: square corners, a solid black outline, and the selected one
/// inverted. Separate boxes with space between them are easier to hit and read than icons in circles.
class EinkButton extends StatelessWidget {
  const EinkButton(
    this.label, {
    super.key,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.height = 48,
    this.fontSize = 16,
    this.shrink = true,
  });
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final IconData? icon;
  final double height;
  final double fontSize;

  /// Scale the text down to fit (buttons with long labels); tabs turn it off so they all match.
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.black;
    return Listener(
      // Reacts on touch-down; waiting for the finger to lift feels slow on e-ink.
      onPointerDown: (_) => onTap?.call(),
      child: Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          border: Border.all(width: 2, color: Colors.black),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: shrink ? BoxFit.scaleDown : BoxFit.none,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 4, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
