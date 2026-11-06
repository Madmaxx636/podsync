import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/settings.dart';

void main() {
  test(
    'appearance, downloads and automation sync; this-device choices do not',
    () {
      final a = AppSettings()
        ..set('themeMode', 'dark')
        ..set('accent', 0xFF009688)
        ..set('autoDownloadNew', true)
        ..set('zoom', 1.5)
        ..set('downloadDir', '/home/a/podcasts')
        ..set('showSidebar', false)
        ..set('trayIcon', false);
      final sent = a.syncedJson();
      expect(sent['themeMode'], 'dark');
      for (final k in [
        'zoom',
        'downloadDir',
        'showSidebar',
        'trayIcon',
        'colWidths',
      ]) {
        expect(sent.containsKey(k), isFalse, reason: '$k stays on this device');
      }

      // The other device takes the synced ones and keeps its own.
      final b = AppSettings()
        ..set('downloadDir', '/storage/emulated/0/Podcasts')
        ..set('zoom', 1.0);
      b.applySynced(sent);
      expect(b.themeMode, 'dark');
      expect(b.accent, 0xFF009688);
      expect(b.autoDownloadNew, isTrue);
      expect(b.downloadDir, '/storage/emulated/0/Podcasts');
      expect(b.zoom, 1.0);
    },
  );
}
