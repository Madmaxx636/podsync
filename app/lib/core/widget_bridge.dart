import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'models.dart';
import 'player.dart';

/// Android home-screen widgets: tells them what is playing and what is next in Up Next, and
/// plays the episode a widget row asks for.
class WidgetBridge {
  WidgetBridge(this.lib, this.player, {http.Client? client})
    : _http = client ?? http.Client();

  final Library lib;
  final PlayerController player;
  final http.Client _http;

  static const _channel = MethodChannel('dev.podsync/widgets');
  Timer? _debounce;
  String _lastSent = '';
  String _artFor = '';
  String _artPath = '';

  /// Asks Android to place a widget on the home screen: 'now', 'upnext' or 'playpause'.
  /// False when the launcher cannot do that (the person adds it from the widget list instead).
  static Future<bool> pin(String kind) async {
    try {
      return (await _channel.invokeMethod<bool>('pin', kind)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'episode') _play(call.arguments as String);
    });
    player.addListener(_changed);
    lib.addListener(_changed);
    _changed();
    // An episode a widget asked for while the app was closed.
    try {
      final id = await _channel.invokeMethod<String>('takePending');
      if (id != null) _play(id);
    } catch (_) {}
  }

  void _play(String id) {
    final e = lib.episodes[id];
    if (e == null) return;
    if (player.current?.id == id) {
      if (!player.playing) player.toggle();
    } else {
      player.play(e);
    }
  }

  /// Throttled, not debounced: while an episode plays the player ticks every half second, so
  /// waiting for quiet would never push anything. One push per second reads the latest state.
  void _changed() {
    if (_debounce?.isActive ?? false) return;
    _debounce = Timer(const Duration(seconds: 1), _push);
  }

  String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0
        ? '$h h ${m.toString().padLeft(2, '0')} min'
        : '${d.inMinutes} min';
  }

  Future<void> _push() async {
    final e = player.current;
    final art = e == null ? '' : await _artPathFor(e);
    final queue = lib.queueEpisodes
        .where((x) => x.id != e?.id)
        .take(4)
        .toList();
    final payload = <String, Object?>{
      'has': e != null,
      'playing': player.playing,
      'title': e?.title ?? '',
      'podcast': e == null ? '' : lib.podcastTitle(e.feedUrl),
      'art': art,
      'skipBack': lib.skipBackSec,
      'skipForward': lib.skipForwardSec,
      'positionMs': player.position.inMilliseconds,
      'durationMs': player.duration.inMilliseconds > 0
          ? player.duration.inMilliseconds
          : (e?.durationMs ?? 0),
      'queueCount': lib.queue.length,
      'queue': jsonEncode([
        for (final q in queue)
          {
            'id': q.id,
            'title': q.title,
            'sub':
                '${lib.podcastTitle(q.feedUrl)}${q.durationMs > 0 ? ' · ${_clock(q.durationMs)}' : ''}',
          },
      ]),
    };
    // Only wake the widgets when something they show changed (the position alone is rounded
    // to a few percent so a playing episode does not update them constantly).
    final shown = {
      ...payload,
      'positionMs': ((payload['positionMs'] as int) ~/ 15000),
    };
    final key = jsonEncode(shown);
    if (key == _lastSent) return;
    _lastSent = key;
    try {
      await _channel.invokeMethod<void>('update', payload);
    } catch (e) {
      debugPrint('widgets update failed: $e');
      _lastSent = ''; // try again on the next change
    }
  }

  /// The cover saved as a small file the widget can read; kept per episode image.
  Future<String> _artPathFor(Episode e) async {
    final url = e.imageUrl.isNotEmpty
        ? e.imageUrl
        : (lib.podcasts[e.feedUrl]?.imageUrl ?? '');
    if (url.isEmpty) return '';
    if (url == _artFor) return _artPath;
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'widget_art'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${url.hashCode.toUnsigned(32)}.img'));
      if (!await file.exists()) {
        final r = await _http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return _artPath;
        await file.writeAsBytes(r.bodyBytes);
      }
      _artFor = url;
      _artPath = file.path;
    } catch (_) {}
    return _artPath;
  }
}
