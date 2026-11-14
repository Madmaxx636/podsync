// Local tool, not part of the suite: renders the desktop UI to a PNG with real fonts.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/core/player.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:provider/provider.dart';

import '../test/fixtures.dart';

Future<void> loadFonts() async {
  final dir = Platform.environment['MATERIAL_FONTS']!;
  Future<ByteData> bytes(String f) async => ByteData.view(
    Uint8List.fromList(File('$dir/$f').readAsBytesSync()).buffer,
  );
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  testWidgets('screenshot', (tester) async {
    await tester.runAsync(loadFonts);
    final w = double.parse(Platform.environment['W'] ?? '1300');
    final h = double.parse(Platform.environment['H'] ?? '850');
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final path = makeAntennaPodBackup();
    final lib = Library();
    importAntennaPodBackup(lib, path);
    final player = PlayerController(lib);
    player.current = lib.episodes['http://a.test/feed.xml|guid-2'];
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: testProviders(lib, player: player),
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2196F3),
              ),
            ),
            home: const DesktopShell(),
          ),
        ),
      ),
    );
    await tester.pump();
    final tap = Platform.environment['TAP'];
    if (tap != null) {
      await tester.tap(find.text(tap).first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        Platform.environment['SHOT_OUT'] ?? '/tmp/podsync-gold/desktop.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
