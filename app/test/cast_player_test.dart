import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/cast_output.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/models.dart';
import 'package:podsync/core/player.dart';

class _FakeCast implements CastOutput {
  final calls = <String>[];
  @override
  bool playing = true;
  @override
  Future<void> toggle() async => calls.add('toggle');
  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');
  @override
  Future<void> load(Episode e, Duration start) async =>
      calls.add('load ${e.id}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'while casting, play, seek and position go to the Cast device',
    () async {
      final player = PlayerController(Library());
      final cast = _FakeCast();
      await player.startCast(cast);
      await player.toggle();
      await player.seek(const Duration(seconds: 42));
      expect(cast.calls, ['toggle', 'seek 42']);
      expect(player.position, const Duration(seconds: 42));

      player.castUpdate(pos: const Duration(seconds: 50), isPlaying: true);
      expect(player.position, const Duration(seconds: 50));
      expect(player.playing, isTrue);

      await player.stopCast(resume: false);
      expect(player.cast, isNull);
      expect(player.playing, isFalse);
    },
  );
}
