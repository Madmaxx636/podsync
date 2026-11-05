import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.podsync/storage');

/// Android's "All files access", which saving downloads to a folder of your choice outside the
/// app's own storage needs. Always true elsewhere.
Future<bool> hasAllFilesAccess() async {
  if (!Platform.isAndroid) return true;
  try {
    return (await _channel.invokeMethod<bool>('hasAllFilesAccess')) ?? false;
  } catch (_) {
    return false;
  }
}

/// Opens the system page where the person allows it (they come back with the back button).
Future<void> requestAllFilesAccess() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('requestAllFilesAccess');
  } catch (_) {}
}

/// Whether files can be written in [dir]: creates it if needed and saves and removes a tiny file.
Future<bool> canWriteTo(String dir) async {
  try {
    final d = Directory(dir);
    await d.create(recursive: true);
    final probe = File('${d.path}/.podsync-write-test');
    await probe.writeAsString('ok');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}
