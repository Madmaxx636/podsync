import 'package:audio_service/audio_service.dart';

import 'library.dart';
import 'player.dart';

/// Android: the notification, lock screen and headset buttons. PodSync plays one episode at a
/// time and keeps its own Up Next queue, so this describes that to Android directly: rewind,
/// play / pause, fast-forward and next, with the cover, the episode, the podcast and a seek bar.
class PodSyncAudioHandler extends BaseAudioHandler with SeekHandler {
  PodSyncAudioHandler(this.player, this.lib) {
    player.addListener(_sync);
    _sync();
  }

  final PlayerController player;
  final Library lib;

  String? _shownId;
  String _stateKey = '';
  Duration _lastPosition = Duration.zero;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  /// The Android notification lists these in order; the first three show when it is collapsed.
  List<MediaControl> get _controls => [
    MediaControl.rewind,
    if (player.playing) MediaControl.pause else MediaControl.play,
    MediaControl.fastForward,
    MediaControl.skipToNext,
  ];

  void _sync() {
    final e = player.current;
    if (e == null) {
      if (_shownId != null) {
        _shownId = null;
        mediaItem.add(null);
        playbackState.add(
          PlaybackState(
            processingState: AudioProcessingState.idle,
            playing: false,
            controls: [MediaControl.play],
          ),
        );
      }
      return;
    }
    if (e.id != _shownId) {
      _shownId = e.id;
      mediaItem.add(
        MediaItem(
          id: e.id,
          title: e.title,
          album: lib.podcastTitle(e.feedUrl),
          artist: lib.podcastTitle(e.feedUrl),
          artUri: e.imageUrl.isEmpty ? null : Uri.tryParse(e.imageUrl),
          duration: player.duration > Duration.zero
              ? player.duration
              : Duration(milliseconds: e.durationMs),
        ),
      );
    }
    final speed = lib.speedFor(e.feedUrl);
    // Android works out the moving position itself, so only push when something changed or the
    // position jumped (a seek); not on every tick.
    final key =
        '${e.id}|${player.playing}|${player.buffering}|$speed|${player.duration.inSeconds}';
    final expected =
        _lastPosition +
        (player.playing
            ? Duration(
                milliseconds:
                    (DateTime.now().difference(_lastPush).inMilliseconds *
                            speed)
                        .round(),
              )
            : Duration.zero);
    final jumped =
        (player.position - expected).abs() > const Duration(seconds: 2);
    if (key == _stateKey && !jumped) return;
    _stateKey = key;
    _lastPosition = player.position;
    _lastPush = DateTime.now();

    final shown = mediaItem.value;
    if (shown != null &&
        player.duration > Duration.zero &&
        shown.duration != player.duration) {
      mediaItem.add(shown.copyWith(duration: player.duration));
    }
    playbackState.add(
      PlaybackState(
        controls: _controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: player.error != null
            ? AudioProcessingState.error
            : (player.buffering
                  ? AudioProcessingState.buffering
                  : AudioProcessingState.ready),
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.position,
        speed: speed,
      ),
    );
  }

  @override
  Future<void> play() => player.playFromAnywhere();

  @override
  Future<void> pause() async {
    if (player.playing) await player.toggle();
  }

  @override
  Future<void> stop() async {
    if (player.playing) await player.toggle();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.skipBack();

  @override
  Future<void> fastForward() => player.skipForward();

  @override
  Future<void> rewind() => player.skipBack();
}
