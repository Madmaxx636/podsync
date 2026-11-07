import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps PodSync to one running copy. The first copy listens on a loopback port that the system
/// picks and writes it to a small file in its data folder; a second launch (the taskbar or Start
/// menu icon while PodSync sits in the tray) reads that file, tells the first copy to show its
/// window and quits itself.
///
/// The port is picked by the system, not fixed, because Windows reserves ranges of port numbers
/// on many machines (Hyper-V, WSL, Docker) and a fixed one can fail to bind there, which used to
/// leave the first copy unreachable and let a second one start.
class SingleInstance {
  SingleInstance._();

  static const _hello = 'podsync-show';
  static const _fileName = 'single_instance.port';

  /// Where the port file lives; set by tests, otherwise the app's data folder.
  static Directory? directory;

  static Future<File> _file() async => File(
    p.join(
      (directory ?? await getApplicationSupportDirectory()).path,
      _fileName,
    ),
  );

  /// True when another PodSync answered and was asked to show itself: this copy should exit.
  /// On any doubt (no file, nobody home, no answer) this returns false and runs on.
  static Future<bool> handOverToRunning() async {
    try {
      final file = await _file();
      if (!await file.exists()) return false;
      final port = int.tryParse((await file.readAsString()).trim());
      if (port == null) return false;
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      s.write('$_hello\n');
      await s.flush();
      final reply = await s
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      await s.close();
      return reply.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Starts listening; [onShow] runs whenever another launch asks for the window.
  static Future<void> listen(void Function() onShow) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString('${server.port}');
      server.listen((c) {
        c.cast<List<int>>().transform(utf8.decoder).listen((data) {
          if (data.contains(_hello)) {
            // Answer first, so the second copy leaves even if showing the window fails.
            c.write('ok\n');
            try {
              onShow();
            } catch (_) {}
          }
          c.close();
        }, onError: (_) => c.destroy());
      }, onError: (_) {});
    } catch (_) {
      // No guard this time; PodSync still runs.
    }
  }
}
