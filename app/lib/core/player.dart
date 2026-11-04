import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'downloads.dart';
import 'library.dart';
import 'models.dart';

/// Wraps just_audio, resumes from synced progress, saves position as it plays
/// and advances through the synced queue.
class PlayerController extends ChangeNotifier {
  PlayerController(this.library, {this.downloads}) {
    // A downloaded episode that is being listened to must not be cleaned up from under the player.
    downloads?.isInUse = (id) => current?.id == id;
    _player.positionStream.listen((pos) {
      position = pos;
      _maybeSave();
      _checkSkipEnding();
      // E-ink panels ghost on every refresh, so redraw the clock only every few seconds.
      if (library.einkMode &&
          (pos - _lastUiTick).abs() <
              Duration(seconds: library.settings.einkClockSec)) {
        return;
      }
      _lastUiTick = pos;
      notifyListeners();
    });
    _player.durationStream.listen((d) {
      if (d != null) duration = d;
      notifyListeners();
    });
    library.addListener(_onLibrary);
    _player.playerStateStream.listen((s) {
      playing = s.playing;
      if (s.processingState == ProcessingState.completed) _onCompleted();
      notifyListeners();
    });
  }

  final Library library;
  final DownloadManager? downloads;
  final AudioPlayer _player = AudioPlayer();

  Episode? current;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  String? error;
  bool _endHandled = false;
  bool _markedPlayedEarly = false;
  bool? _silenceApplied;
  DateTime? _pausedAt;
  Duration _lastUiTick = Duration.zero;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> play(Episode e, {bool fromQueue = false}) async {
    await _saveNow();
    current = e;
    error = null;
    final podcast = library.podcasts[e.feedUrl];
    final saved = library.progressOf(e.id);
    position = Duration(milliseconds: saved.played ? 0 : saved.positionMs);
    _endHandled = false;
    _markedPlayedEarly = false;
    _pausedAt = null;
    // A podcast's "skip intro" only applies when starting from the beginning.
    if (position == Duration.zero &&
        podcast != null &&
        podcast.skipIntroSec > 0) {
      position = Duration(seconds: podcast.skipIntroSec);
    }
    duration = Duration(milliseconds: e.durationMs);
    notifyListeners();
    try {
      final tag = MediaItem(
        id: e.id,
        title: e.title,
        artist: podcast?.displayTitle ?? '',
        artUri: e.imageUrl.isEmpty ? null : Uri.tryParse(e.imageUrl),
      );
      // Prefer the downloaded copy; if it will not open, fall back to streaming.
      final local = downloads?.pathOf(e.id);
      var started = false;
      if (local != null) {
        try {
          await _player.setAudioSource(
            AudioSource.file(local, tag: tag),
            initialPosition: position,
          );
          started = true;
        } catch (err) {
          debugPrint(
            'Downloaded file would not open ($err), streaming instead',
          );
        }
      }
      if (!started) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(e.audioUrl), tag: tag),
          initialPosition: position,
        );
      }
      await _player.setSpeed(library.speedFor(e.feedUrl));
      _silenceApplied = null;
      await _applySkipSilence();
      _volumeApplied = null;
      await _applyVolume();
      _player.play();
    } catch (err) {
      error = 'Could not play this episode: $err';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (_player.playing) return pause();
    // Smart rewind: after a longer pause, step back a little to catch up on context.
    final rewind = library.settings.smartRewindSec;
    final paused = _pausedAt;
    if (rewind > 0 &&
        paused != null &&
        DateTime.now().difference(paused) > const Duration(seconds: 30)) {
      await _player.seek(_clamp(_player.position - Duration(seconds: rewind)));
    }
    _pausedAt = null;
    _player.play();
  }

  Future<void> pause() async {
    _pausedAt = DateTime.now();
    await _player.pause();
    await _saveNow();
  }

  double? _volumeApplied;

  void _onLibrary() {
    _applySkipSilence();
    _applyVolume();
  }

  /// 0 to 1, or 0 while muted.
  double get effectiveVolume =>
      library.settings.muted ? 0.0 : library.settings.volume;

  Future<void> _applyVolume() async {
    final v = effectiveVolume;
    if (_volumeApplied == v) return;
    _volumeApplied = v;
    try {
      await _player.setVolume(v);
    } catch (e) {
      debugPrint('volume: $e');
    }
  }

  /// Sets the app volume (0 to 1). Turning it up also unmutes.
  void setVolume(double v) {
    library.setSetting('volume', v.clamp(0.0, 1.0));
    if (v > 0 && library.settings.muted) library.setSetting('muted', false);
  }

  void changeVolume(double delta) => setVolume(
    (library.settings.muted ? 0.0 : library.settings.volume) + delta,
  );

  void toggleMute() => library.setSetting('muted', !library.settings.muted);

  /// Skip-silence is only available on Android.
  Future<void> _applySkipSilence() async {
    final want = library.settings.skipSilence;
    if (!Platform.isAndroid || current == null || _silenceApplied == want) {
      return;
    }
    _silenceApplied = want;
    try {
      await _player.setSkipSilenceEnabled(want);
    } catch (e) {
      debugPrint('skip silence: $e');
    }
  }

  Future<void> seek(Duration d) async {
    await _player.seek(d);
    _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
    _maybeSave();
  }

  Future<void> skipBack() =>
      seek(_clamp(position - Duration(seconds: library.skipBackSec)));
  Future<void> skipForward() =>
      seek(_clamp(position + Duration(seconds: library.skipForwardSec)));

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && d > duration) return duration;
    return d;
  }

  Future<void> setSpeed(double s) async {
    final cur = current;
    if (cur != null) {
      library.setSpeedFor(cur.feedUrl, s);
    } else {
      library.setPrefs(speed: s);
    }
    await _player.setSpeed(s);
  }

  /// Applies the podcast's "skip ending" setting by treating the episode as finished early.
  void _checkSkipEnding() {
    final cur = current;
    if (cur == null ||
        _endHandled ||
        duration == Duration.zero ||
        !_player.playing) {
      return;
    }
    final remaining = duration - position;
    // "Mark as played when X seconds remain" keeps playing; only the flag changes.
    final markAt = library.settings.autoPlayedRemainingSec;
    if (markAt > 0 &&
        !_markedPlayedEarly &&
        remaining <= Duration(seconds: markAt)) {
      _markedPlayedEarly = true;
      library.setProgress(
        cur.id,
        position.inMilliseconds,
        duration.inMilliseconds,
        played: true,
      );
    }
    final skip = library.podcasts[cur.feedUrl]?.skipEndingSec ?? 0;
    if (skip > 0 && remaining <= Duration(seconds: skip)) _onCompleted();
  }

  Future<void> next() async {
    final cur = current;
    final q = library.queueEpisodes;
    final i = cur == null ? -1 : q.indexWhere((e) => e.id == cur.id);
    final target = i >= 0
        ? (i + 1 < q.length ? q[i + 1] : null)
        : (q.isNotEmpty ? q.first : null);
    if (target != null) await play(target, fromQueue: true);
  }

  @visibleForTesting
  void episodeCompletedForTest() {
    _endHandled =
        false; // a real play() resets this; tests start from a hand-set episode
    _onCompleted();
  }

  void _onCompleted() {
    final cur = current;
    if (cur == null || _endHandled) return;
    _endHandled = true;
    library.setProgress(cur.id, 0, duration.inMilliseconds, played: true);
    final q = library.queueEpisodes;
    final i = q.indexWhere((e) => e.id == cur.id);
    Episode? following = i >= 0 && i + 1 < q.length
        ? q[i + 1]
        : (i < 0 && q.isNotEmpty ? q.first : null);
    if (library.settings.removePlayedFromQueue) {
      library.removeFromQueue(cur.id, undoable: false);
    }
    if (library.settings.syncOnPause) library.sync();
    // "Stop after this episode" sleep timer: finish here instead of moving on.
    final stopHere = sleepAtEpisodeEnd;
    if (stopHere) {
      sleepAtEpisodeEnd = false;
      notifyListeners();
    }
    if (following != null && library.settings.continueQueue && !stopHere) {
      play(following, fromQueue: true);
    } else {
      _player.pause();
    }
  }

  void _maybeSave() {
    final cur = current;
    if (cur == null || !_player.playing) return;
    final now = DateTime.now();
    if (now.difference(_lastSave) < const Duration(seconds: 5)) return;
    _lastSave = now;
    library.setProgress(
      cur.id,
      position.inMilliseconds,
      duration.inMilliseconds,
    );
  }

  Future<void> _saveNow() async {
    final cur = current;
    if (cur == null) return;
    library.setProgress(
      cur.id,
      _player.position.inMilliseconds,
      duration.inMilliseconds,
    );
    if (library.settings.syncOnPause) library.sync();
  }

  // ---- sleep timer -------------------------------------------------------------

  Timer? _sleepTimer;
  Duration? sleepRemaining; // null when no timer is counting down
  bool sleepAtEpisodeEnd = false;
  static const sleepFade = Duration(seconds: 10);

  bool get sleepActive => sleepRemaining != null || sleepAtEpisodeEnd;

  /// Pauses after [d]. The volume eases down over the last ten seconds.
  void startSleepTimer(Duration d) {
    cancelSleepTimer();
    sleepRemaining = d;
    _sleepTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sleepTick(),
    );
    notifyListeners();
  }

  /// Pauses when the current episode ends, instead of starting the next one.
  void sleepAfterEpisode() {
    cancelSleepTimer();
    sleepAtEpisodeEnd = true;
    notifyListeners();
  }

  void extendSleepTimer(Duration d) {
    if (sleepRemaining == null) {
      startSleepTimer(d);
    } else {
      sleepRemaining = sleepRemaining! + d;
      _applyVolumeNow();
      notifyListeners();
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final wasActive = sleepActive;
    sleepRemaining = null;
    sleepAtEpisodeEnd = false;
    if (wasActive) {
      _applyVolumeNow();
      notifyListeners();
    }
  }

  void _applyVolumeNow() {
    _volumeApplied = null;
    _applyVolume();
  }

  void _sleepTick() {
    final left = sleepRemaining;
    if (left == null) return;
    final next = left - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      _sleepTimer?.cancel();
      _sleepTimer = null;
      sleepRemaining = null;
      pause().then((_) => _applyVolumeNow());
      notifyListeners();
      return;
    }
    sleepRemaining = next;
    if (next <= sleepFade) {
      final factor = next.inMilliseconds / sleepFade.inMilliseconds;
      _volumeApplied = null;
      _player
          .setVolume(effectiveVolume * factor)
          .catchError((Object e) => debugPrint('fade: $e'));
    }
    // On e-ink, redrawing every second would ghost; the countdown only ticks over every ten seconds.
    if (!library.einkMode || next.inSeconds % 10 == 0) notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    library.removeListener(_onLibrary);
    _player.dispose();
    super.dispose();
  }
}
