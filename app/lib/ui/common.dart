import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

String fmtDurationMs(int ms) => ms <= 0 ? '' : fmtDuration(Duration(milliseconds: ms));

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String fmtDate(int ms, {bool year = true}) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  switch (currentDateStyle) {
    case 'iso':
      return year ? '${d.year}-${two(d.month)}-${two(d.day)}' : '${two(d.month)}-${two(d.day)}';
    case 'dmy':
      return year ? '${d.day} ${_mon[d.month - 1]} ${d.year}' : '${d.day} ${_mon[d.month - 1]}';
    default:
      return year ? '${_mon[d.month - 1]} ${d.day}, ${d.year}' : '${_mon[d.month - 1]} ${d.day}';
  }
}

/// Podcast / episode artwork with a neutral placeholder.
class Art extends StatelessWidget {
  const Art(this.url, {super.key, this.size = 56, this.radius = 4, this.gray = false});
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
      child: Icon(Icons.podcasts, size: size * 0.5, color: Colors.grey.shade600),
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
  final tmp = File('${(await getTemporaryDirectory()).path}/import-${DateTime.now().microsecondsSinceEpoch}-${picked.first.name}');
  final sink = tmp.openWrite();
  await sink.addStream(picked.first.readAsByteStream());
  await sink.close();
  return tmp;
}
