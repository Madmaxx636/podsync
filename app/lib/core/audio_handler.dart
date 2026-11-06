import 'package:audio_service/audio_service.dart';

import 'library.dart';
import 'models.dart';
import 'player.dart';

/// Android: the notification, lock screen and headset buttons. PodSync plays one episode at a
/// time and keeps its own Up Next queue, so this describes that to Android directly: rewind,
/// play / pause, fast-forward and next, with the cover, the episode, the podcast and a seek bar.
class PodSyncAudioHandler extends BaseAudioHandler with SeekHandler {
  PodSyncAudioHandler(this.player, this.lib) {
    player.addListener(_sync);
    lib.addListener(_sync); // a changed skip length redraws the buttons
    _sync();
  }

  final PlayerController player;
  final Library lib;

  String? _shownId;
  String _stateKey = '';
  Duration _lastPosition = Duration.zero;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  /// The skip lengths that have a drawable with the seconds drawn in it (settings offers these).
  static const _backIcons = {5, 10, 15, 20, 30, 45, 60};
  static const _forwardIcons = {10, 15, 30, 45, 60, 90};

  /// The Android notification lists these in order; the first three show when it is collapsed.
  /// The skip buttons carry your own skip lengths, in the label and drawn on the icon.
  List<MediaControl> get _controls {
    final back = lib.skipBackSec, fwd = lib.skipForwardSec;
    return [
      MediaControl(
        androidIcon: _backIcons.contains(back)
            ? 'drawable/ic_skip_back_$back'
            : 'drawable/audio_service_fast_rewind',
        label: 'Back $back s',
        action: MediaAction.rewind,
      ),
      if (player.playing) MediaControl.pause else MediaControl.play,
      MediaControl(
        androidIcon: _forwardIcons.contains(fwd)
            ? 'drawable/ic_skip_fwd_$fwd'
            : 'drawable/audio_service_fast_forward',
        label: 'Forward $fwd s',
        action: MediaAction.fastForward,
      ),
      MediaControl.skipToNext,
    ];
  }

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
        '${e.id}|${player.playing}|${player.buffering}|$speed|${player.duration.inSeconds}'
        '|${lib.skipBackSec}|${lib.skipForwardSec}';
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
          MediaAction.rewind,
          MediaAction.fastForward,
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

  // ---- Android Auto and other browsers of the media session -----------------------------------
  // A short tree: Up Next, New episodes, Downloaded, and each podcast with its episodes. Folders
  // are not playable; episodes are, and play through the normal player.

  static const _queueId = 'folder:queue';
  static const _newId = 'folder:new';
  static const _downloadedId = 'folder:downloaded';
  static const _podcastsId = 'folder:podcasts';
  static const _feedPrefix = 'feed:';
  static const _limit = 60;

  MediaItem _folder(String id, String title, [String? subtitle]) =>
      MediaItem(id: id, title: title, artist: subtitle, playable: false);

  MediaItem _episodeItem(Episode e) => MediaItem(
    id: e.id,
    title: e.title,
    album: lib.podcastTitle(e.feedUrl),
    artist: lib.podcastTitle(e.feedUrl),
    artUri: e.imageUrl.isEmpty ? null : Uri.tryParse(e.imageUrl),
    duration: e.durationMs > 0 ? Duration(milliseconds: e.durationMs) : null,
    playable: true,
  );

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return [
          _folder(_queueId, 'Up Next', '${lib.queue.length} episodes'),
          _folder(_newId, 'New episodes'),
          _folder(_downloadedId, 'Downloaded'),
          _folder(_podcastsId, 'Podcasts'),
        ];
      case _queueId:
        return [
          for (final e in lib.queueEpisodes.take(_limit)) _episodeItem(e),
        ];
      case _newId:
        final fresh = [
          for (final e in lib.episodes.values)
            if (!lib.progressOf(e.id).played) e,
        ]..sort((a, b) => b.published.compareTo(a.published));
        return [for (final e in fresh.take(_limit)) _episodeItem(e)];
      case _downloadedId:
        final dl = player.downloads;
        if (dl == null) return const [];
        return [
          for (final id in dl.doneIds.take(_limit))
            if (lib.episodes[id] != null) _episodeItem(lib.episodes[id]!),
        ];
      case _podcastsId:
        return [
          for (final p in lib.subscriptions)
            _folder('$_feedPrefix${p.feedUrl}', p.displayTitle),
        ];
    }
    if (parentMediaId.startsWith(_feedPrefix)) {
      final eps = [
        ...lib.episodesOf(parentMediaId.substring(_feedPrefix.length)),
      ]..sort((a, b) => b.published.compareTo(a.published));
      return [for (final e in eps.take(_limit)) _episodeItem(e)];
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final e = lib.episodes[mediaId];
    return e == null ? null : _episodeItem(e);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final e = lib.episodes[mediaId];
    if (e != null) await player.play(e);
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
