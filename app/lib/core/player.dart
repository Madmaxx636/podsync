import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'library.dart';
import 'models.dart';

/// Wraps just_audio, resumes from synced progress, saves position as it plays
/// and advances through the synced queue.
class PlayerController extends ChangeNotifier {
  PlayerController(this.library) {
    _player.positionStream.listen((pos) {
      position = pos;
      _maybeSave();
      _checkSkipEnding();
      // E-ink panels ghost on every refresh, so redraw the clock only every few seconds.
      if (library.einkMode && (pos - _lastUiTick).abs() < Duration(seconds: library.settings.einkClockSec)) return;
      _lastUiTick = pos;
      notifyListeners();
    });
    _player.durationStream.listen((d) {
      if (d != null) duration = d;
      notifyListeners();
    });
    library.addListener(_applySkipSilence);
    _player.playerStateStream.listen((s) {
      playing = s.playing;
      if (s.processingState == ProcessingState.completed) _onCompleted();
      notifyListeners();
    });
  }

  final Library library;
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
    if (position == Duration.zero && podcast != null && podcast.skipIntroSec > 0) {
      position = Duration(seconds: podcast.skipIntroSec);
    }
    duration = Duration(milliseconds: e.durationMs);
    notifyListeners();
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(e.audioUrl),
          tag: MediaItem(
            id: e.id,
            title: e.title,
            artist: podcast?.displayTitle ?? '',
            artUri: e.imageUrl.isEmpty ? null : Uri.tryParse(e.imageUrl),
          ),
        ),
        initialPosition: position,
      );
      await _player.setSpeed(library.speedFor(e.feedUrl));
      _silenceApplied = null;
      await _applySkipSilence();
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
    if (rewind > 0 && paused != null && DateTime.now().difference(paused) > const Duration(seconds: 30)) {
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

  /// Skip-silence is only available on Android.
  Future<void> _applySkipSilence() async {
    final want = library.settings.skipSilence;
    if (!Platform.isAndroid || current == null || _silenceApplied == want) return;
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

  Future<void> skipBack() => seek(_clamp(position - Duration(seconds: library.skipBackSec)));
  Future<void> skipForward() => seek(_clamp(position + Duration(seconds: library.skipForwardSec)));

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
    if (cur == null || _endHandled || duration == Duration.zero || !_player.playing) return;
    final remaining = duration - position;
    // "Mark as played when X seconds remain" keeps playing; only the flag changes.
    final markAt = library.settings.autoPlayedRemainingSec;
    if (markAt > 0 && !_markedPlayedEarly && remaining <= Duration(seconds: markAt)) {
      _markedPlayedEarly = true;
      library.setProgress(cur.id, position.inMilliseconds, duration.inMilliseconds, played: true);
    }
    final skip = library.podcasts[cur.feedUrl]?.skipEndingSec ?? 0;
    if (skip > 0 && remaining <= Duration(seconds: skip)) _onCompleted();
  }

  Future<void> next() async {
    final cur = current;
    final q = library.queueEpisodes;
    final i = cur == null ? -1 : q.indexWhere((e) => e.id == cur.id);
    final target = i >= 0 ? (i + 1 < q.length ? q[i + 1] : null) : (q.isNotEmpty ? q.first : null);
    if (target != null) await play(target, fromQueue: true);
  }

  void _onCompleted() {
    final cur = current;
    if (cur == null || _endHandled) return;
    _endHandled = true;
    library.setProgress(cur.id, 0, duration.inMilliseconds, played: true);
    final q = library.queueEpisodes;
    final i = q.indexWhere((e) => e.id == cur.id);
    Episode? following = i >= 0 && i + 1 < q.length ? q[i + 1] : (i < 0 && q.isNotEmpty ? q.first : null);
    if (library.settings.removePlayedFromQueue) library.removeFromQueue(cur.id);
    if (library.settings.syncOnPause) library.sync();
    if (following != null && library.settings.continueQueue) {
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
    library.setProgress(cur.id, position.inMilliseconds, duration.inMilliseconds);
  }

  Future<void> _saveNow() async {
    final cur = current;
    if (cur == null) return;
    library.setProgress(cur.id, _player.position.inMilliseconds, duration.inMilliseconds);
    if (library.settings.syncOnPause) library.sync();
  }

  @override
  void dispose() {
    library.removeListener(_applySkipSilence);
    _player.dispose();
    super.dispose();
  }
}

