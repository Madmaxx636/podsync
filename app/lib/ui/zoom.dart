import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';

/// Desktop zoom: the whole window scales (Ctrl + mouse wheel, Ctrl + and Ctrl -, Ctrl 0).
class Zoom {
  static const min = 0.7, max = 2.0, step = 0.1;

  static double of(Library lib) => Platform.isAndroid ? 1.0 : lib.settings.zoom;

  static void change(Library lib, double delta) => lib.setSetting(
    'zoom',
    ((lib.settings.zoom + delta).clamp(min, max) * 20).round() / 20,
  );

  static void reset(Library lib) => lib.setSetting('zoom', 1.0);

  /// A pointer position on screen, in the coordinates of the zoomed overlay, for menus.
  static Offset at(BuildContext context, Offset global) =>
      global / of(context.read<Library>());

  static Map<ShortcutActivator, VoidCallback> shortcuts(Library lib) => {
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
        change(lib, step),
    const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
        change(lib, step),
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () =>
        change(lib, step),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
        change(lib, -step),
    const SingleActivator(
      LogicalKeyboardKey.numpadSubtract,
      control: true,
    ): () =>
        change(lib, -step),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
        reset(lib),
    const SingleActivator(LogicalKeyboardKey.numpad0, control: true): () =>
        reset(lib),
  };
}

/// Wraps the whole app: lays it out at 1/zoom of the window and scales it up, so text and
/// icons stay sharp, and turns Ctrl + wheel into zoom.
class ZoomHost extends StatelessWidget {
  const ZoomHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<Library>();
    final z = context.select<Library, double>((l) => l.settings.zoom);
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          Zoom.change(lib, e.scrollDelta.dy < 0 ? Zoom.step : -Zoom.step);
        }
      },
      child: z == 1.0
          ? child
          : LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / z, h = box.maxHeight / z;
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: w,
                    maxWidth: w,
                    minHeight: h,
                    maxHeight: h,
                    child: Transform.scale(
                      scale: z,
                      alignment: Alignment.topLeft,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(size: Size(w, h)),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
