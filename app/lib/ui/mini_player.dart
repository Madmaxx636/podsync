import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/library.dart';
import '../core/player.dart';
import 'common.dart';

/// The mini player: the window shrinks to a small always-on-top strip with the cover, title,
/// transport and a scrubber. Click the cover again (or the expand button) to get the full window back.
class MiniPlayer {
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static Size? _size;
  static Offset? _pos;
  static bool _wasMaximized = false;
  // The window's own frame (title bar, borders) counts in this size, so leave room for it.
  static const size = Size(320, 352);

  static Future<void> toggle() => active.value ? close() : open();

  /// Each window call is tried on its own: one the platform does not support (moving a window on
  /// Wayland, for instance) must not stop the others.
  static Future<void> _try(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }

  static Future<void> open() async {
    if (active.value) return;
    active.value = true;
    _size = null;
    _pos = null;
    await _try(() async => _size = await windowManager.getSize());
    await _try(() async => _pos = await windowManager.getPosition());
    await _try(() async {
      _wasMaximized = await windowManager.isMaximized();
      if (_wasMaximized) await windowManager.unmaximize();
    });
    await _try(() => windowManager.setMinimumSize(const Size(220, 250)));
    await _try(() => windowManager.setSize(size));
    await _try(() => windowManager.setAlwaysOnTop(true));
  }

  static Future<void> close() async {
    if (!active.value) return;
    active.value = false;
    await _try(() => windowManager.setAlwaysOnTop(false));
    await _try(() => windowManager.setMinimumSize(const Size(720, 480)));
    if (_size != null) await _try(() => windowManager.setSize(_size!));
    if (_pos != null) await _try(() => windowManager.setPosition(_pos!));
    if (_wasMaximized) await _try(windowManager.maximize);
  }
}

/// Like iTunes' mini player: the cover fills the window, with the title across the top and a dark,
/// translucent control panel over the bottom (transport, scrubber and the two times).
class MiniPlayerView extends StatelessWidget {
  const MiniPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.read<Library>();
    final e = player.current;
    final total = player.duration.inMilliseconds.toDouble();
    const ink = Colors.white;

    Widget button(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      double size = 26,
    }) => IconButton(
      icon: Icon(icon),
      iconSize: size,
      color: ink,
      disabledColor: Colors.white38,
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
      onPressed: onTap,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Drag the cover to move the window.
        onPanStart: (_) {
          try {
            windowManager.startDragging();
          } catch (_) {}
        },
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: e == null
                      ? SizedBox(
                          width: box.maxWidth,
                          height: box.maxHeight,
                          child: const Icon(
                            Icons.podcasts,
                            size: 72,
                            color: Colors.white24,
                          ),
                        )
                      : Art(
                          e.imageUrl,
                          size: box.maxWidth > box.maxHeight
                              ? box.maxWidth
                              : box.maxHeight,
                          radius: 0,
                        ),
                ),
              ),
              // Title strip across the top.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e?.title ?? 'Nothing playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            if (e != null)
                              Text(
                                lib.podcastTitle(e.feedUrl),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_full),
                        iconSize: 18,
                        color: ink,
                        tooltip: 'Back to the full window',
                        visualDensity: VisualDensity.compact,
                        onPressed: MiniPlayer.close,
                      ),
                    ],
                  ),
                ),
              ),
              // The control panel.
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          button(
                            Icons.fast_rewind,
                            'Back ${lib.skipBackSec}s',
                            player.skipBack,
                          ),
                          button(
                            player.playing ? Icons.pause : Icons.play_arrow,
                            player.playing ? 'Pause' : 'Play',
                            e == null ? null : player.toggle,
                            size: 36,
                          ),
                          button(
                            Icons.fast_forward,
                            'Forward ${lib.skipForwardSec}s',
                            player.skipForward,
                          ),
                          button(
                            Icons.skip_next,
                            'Next in Up Next',
                            player.next,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            fmtDuration(player.position),
                            style: const TextStyle(fontSize: 11.5, color: ink),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white30,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                value: player.position.inMilliseconds
                                    .toDouble()
                                    .clamp(0, total > 0 ? total : 1),
                                max: total > 0 ? total : 1,
                                onChanged: total > 0
                                    ? (v) => player.seek(
                                        Duration(milliseconds: v.round()),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            total <= 0
                                ? ''
                                : '-${fmtDuration(player.duration - player.position)}',
                            style: const TextStyle(fontSize: 11.5, color: ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
