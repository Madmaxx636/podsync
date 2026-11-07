import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/single_instance.dart';

void main() {
  test('a second launch asks the running copy to show itself', () async {
    // Its own folder, so a PodSync running on this machine cannot get in the way.
    SingleInstance.directory = Directory.systemTemp.createTempSync(
      'podsync_si',
    );
    addTearDown(() => SingleInstance.directory!.deleteSync(recursive: true));
    expect(
      await SingleInstance.handOverToRunning(),
      isFalse,
    ); // nobody is running yet
    var shown = 0;
    await SingleInstance.listen(() => shown++);
    expect(await SingleInstance.handOverToRunning(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(shown, 1);
  });

  test(
    'a window that fails to show still lets the second copy leave',
    () async {
      SingleInstance.directory = Directory.systemTemp.createTempSync(
        'podsync_si',
      );
      addTearDown(() => SingleInstance.directory!.deleteSync(recursive: true));
      await SingleInstance.listen(() => throw StateError('no window'));
      expect(await SingleInstance.handOverToRunning(), isTrue);
    },
  );

  test(
    'a stale port file from a closed copy does not block a new one',
    () async {
      final dir = Directory.systemTemp.createTempSync('podsync_si');
      addTearDown(() => dir.deleteSync(recursive: true));
      SingleInstance.directory = dir;
      File('${dir.path}/single_instance.port').writeAsStringSync('1');
      expect(await SingleInstance.handOverToRunning(), isFalse);
    },
  );
}
