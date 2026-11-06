import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'cast_net/device.dart';
import 'cast_net/session.dart';
import 'cast_net/session_manager.dart';
import 'cast_output.dart';
import 'library.dart';
import 'models.dart';
import 'player.dart';

/// Sends the playing episode to a Chromecast, Google TV or other Cast device on the same Wi-Fi,
/// using Google's Default Media Receiver, so nothing has to be installed on the TV. The episode
/// streams to the device straight from its own address; this phone only tells it what to do.
class CastController extends ChangeNotifier implements CastOutput {
  CastController(this.player, this.lib);

  final PlayerController player;
  final Library lib;

  /// The one controller, set at start-up on Android (null elsewhere, where there is no Cast button).
  static CastController? instance;

  static const _receiverApp = 'CC1AD845'; // Default Media Receiver

  CastSession? _session;
  CastDevice? device;
  Timer? _poll;
  int _requestId = 0;
  int _mediaSessionId = 0;
  Episode? _pending; // loaded as soon as the receiver is up
  Duration _pendingStart = Duration.zero;
  bool _playing = false;

  /// '' when idle, otherwise what to tell the person ("Connecting to Living Room TV…").
  String status = '';
  String? error;

  bool get connected => device != null && _session != null;
  @override
  bool get playing => _playing;

  /// Looks for Cast devices on the Wi-Fi network (mDNS, `_googlecast._tcp`), for a few seconds.
  Future<List<CastDevice>> search() async {
    final found = <String, CastDevice>{};
    final client = MDnsClient();
    try {
      await client.start();
      const wait = Duration(seconds: 4);
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_googlecast._tcp'),
        timeout: wait,
      )) {
        String? name;
        await for (final txt in client.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(ptr.domainName),
          timeout: const Duration(seconds: 1),
        )) {
          for (final line in txt.text.split('\n')) {
            if (line.startsWith('fn=')) name = line.substring(3);
          }
        }
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 1),
        )) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 1),
          )) {
            found[ptr.domainName] = CastDevice(
              serviceName: ptr.domainName,
              name: name ?? ptr.domainName.split('._googlecast').first,
              host: ip.address.address,
              port: srv.port,
            );
            break;
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('cast search: $e');
    } finally {
      client.stop();
    }
    return found.values.toList();
  }

  /// Connects to [d] and starts the playing episode there from where it is now.
  Future<void> start(CastDevice d) async {
    final e = player.current;
    if (e == null) return;
    await stop(resume: false);
    error = null;
    status = 'Connecting to ${d.name}…';
    device = d;
    _pending = e;
    _pendingStart = player.position;
    notifyListeners();
    try {
      final s = await CastSessionManager().startSession(
        d,
        const Duration(seconds: 10),
      );
      _session = s;
      s.messageStream.listen(_onMessage, onError: (_) {});
      s.stateStream.listen((st) {
        if (st == CastSessionState.connected) {
          final p = _pending;
          if (p != null) {
            _pending = null;
            unawaited(_send(p, _pendingStart));
          }
        } else if (st == CastSessionState.closed) {
          _lost();
        }
      });
      s.sendMessage(CastSession.kNamespaceReceiver, {
        'type': 'LAUNCH',
        'appId': _receiverApp,
        'requestId': ++_requestId,
      });
      await player.startCast(this);
    } catch (err) {
      error = 'Could not connect to ${d.name}: $err';
      _reset();
    }
  }

  Future<void> _send(Episode e, Duration start) async {
    final s = _session;
    if (s == null) return;
    final art = e.imageUrl.isNotEmpty
        ? e.imageUrl
        : (lib.podcasts[e.feedUrl]?.imageUrl ?? '');
    s.sendMessage(CastSession.kNamespaceMedia, {
      'type': 'LOAD',
      'requestId': ++_requestId,
      'autoplay': true,
      'currentTime': start.inMilliseconds / 1000.0,
      'media': {
        'contentId': e.audioUrl,
        'contentType': _contentType(e.audioUrl),
        'streamType': 'BUFFERED',
        'metadata': {
          'metadataType': 3,
          'title': e.title,
          'artist': lib.podcastTitle(e.feedUrl),
          if (art.isNotEmpty)
            'images': [
              {'url': art},
            ],
        },
      },
    });
    status = 'Casting to ${device?.name ?? 'the TV'}';
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _ask());
    notifyListeners();
  }

  static String _contentType(String url) {
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.m4a') || u.endsWith('.mp4') || u.endsWith('.aac')) {
      return 'audio/mp4';
    }
    if (u.endsWith('.ogg') || u.endsWith('.opus')) return 'audio/ogg';
    return 'audio/mpeg';
  }

  void _ask() {
    final s = _session;
    if (s == null) return;
    s.sendMessage(CastSession.kNamespaceMedia, {
      'type': 'GET_STATUS',
      'requestId': ++_requestId,
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['type'] != 'MEDIA_STATUS') return;
    final list = m['status'];
    if (list is! List || list.isEmpty) return;
    final st = list.first as Map<String, dynamic>;
    _mediaSessionId =
        (st['mediaSessionId'] as num?)?.toInt() ?? _mediaSessionId;
    final state = st['playerState'] as String? ?? '';
    final time = (st['currentTime'] as num?)?.toDouble();
    _playing = state == 'PLAYING' || state == 'BUFFERING';
    final ended = state == 'IDLE' && st['idleReason'] == 'FINISHED';
    player.castUpdate(
      pos: time == null ? null : Duration(milliseconds: (time * 1000).round()),
      isPlaying: _playing,
      ended: ended,
    );
    if (ended) _poll?.cancel();
  }

  void _media(String type, [Map<String, dynamic> extra = const {}]) {
    final s = _session;
    if (s == null || _mediaSessionId == 0) return;
    s.sendMessage(CastSession.kNamespaceMedia, {
      'type': type,
      'requestId': ++_requestId,
      'mediaSessionId': _mediaSessionId,
      ...extra,
    });
  }

  @override
  Future<void> toggle() async {
    _media(_playing ? 'PAUSE' : 'PLAY');
    _playing = !_playing;
    player.castUpdate(isPlaying: _playing);
  }

  @override
  Future<void> seek(Duration position) async =>
      _media('SEEK', {'currentTime': position.inMilliseconds / 1000.0});

  @override
  Future<void> load(Episode e, Duration start) => _send(e, start);

  void _lost() {
    if (!connected) return;
    error = 'Lost the connection to ${device?.name ?? 'the TV'}';
    unawaited(stop());
  }

  /// Ends casting. With [resume] the episode carries on on this device from where the TV was.
  Future<void> stop({bool resume = true}) async {
    final s = _session;
    final had = connected;
    _poll?.cancel();
    if (s != null) {
      _media('STOP');
      unawaited(CastSessionManager().endSession(s.sessionId));
    }
    _reset();
    if (had) await player.stopCast(resume: resume);
  }

  void _reset() {
    _poll?.cancel();
    _session = null;
    device = null;
    _pending = null;
    _mediaSessionId = 0;
    _playing = false;
    status = '';
    notifyListeners();
  }
}
