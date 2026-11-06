import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/single_instance.dart';

void main() {
  test('a second launch asks the running copy to show itself', () async {
    // A real PodSync running on this machine already owns the port: nothing to test then.
    if (await SingleInstance.handOverToRunning()) return;
    var shown = 0;
    await SingleInstance.listen(() => shown++);
    expect(await SingleInstance.handOverToRunning(), isTrue);
    expect(shown, 1);
  });
}
