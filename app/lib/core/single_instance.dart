import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Keeps PodSync to one running copy. The first copy listens on a loopback port; a second
/// launch (the taskbar or desktop icon while PodSync sits in the tray) tells it to show its
/// window and then quits itself.
class SingleInstance {
  SingleInstance._();

  static const port = 47613;
  static const _hello = 'podsync-show';
  static ServerSocket? _server;

  /// True when another PodSync answered and was asked to show itself: this copy should exit.
  /// On any doubt (port taken by something else, no answer) this returns false and runs on.
  static Future<bool> handOverToRunning() async {
    try {
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      s.write('$_hello\n');
      await s.flush();
      final reply = await s
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
      await s.close();
      return reply.trim() == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Starts listening; [onShow] runs whenever another launch asks for the window.
  static Future<void> listen(void Function() onShow) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } catch (_) {
      return; // port in use: carry on without the guard
    }
    _server!.listen((c) {
      c.cast<List<int>>().transform(utf8.decoder).listen((data) {
        if (data.contains(_hello)) {
          onShow();
          c.write('ok\n');
        }
        c.close();
      }, onError: (_) => c.destroy());
    }, onError: (_) {});
  }
}
