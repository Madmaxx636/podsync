import 'models.dart';

/// Where an episode plays when it is not on this device: a TV or speaker that speaks Cast. The
/// player hands play, pause, seek and "start this episode" to it while one is connected.
abstract class CastOutput {
  bool get playing;
  Future<void> toggle();
  Future<void> seek(Duration position);
  Future<void> load(Episode e, Duration start);
}
