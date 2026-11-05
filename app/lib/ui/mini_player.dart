import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/library.dart';
import '../core/player.dart';
import 'common.dart';
import 'pal.dart';

/// The mini player: the window shrinks to a small always-on-top strip with the cover, title,
/// transport and a scrubber. Click the cover again (or the expand button) to get the full window back.
class MiniPlayer {
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static Size? _size;
  static Offset? _pos;
  static const size = Size(430, 118);

  static Future<void> toggle() => active.value ? close() : open();

  static Future<void> open() async {
    if (active.value) return;
    active.value = true;
    try {
      _size = await windowManager.getSize();
      _pos = await windowManager.getPosition();
      await windowManager.setMinimumSize(size);
      await windowManager.setSize(size);
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      // No window to resize (tests): the mini view still shows.
    }
  }

  static Future<void> close() async {
    if (!active.value) return;
    active.value = false;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(720, 480));
      if (_size != null) await windowManager.setSize(_size!);
      if (_pos != null) await windowManager.setPosition(_pos!);
    } catch (_) {}
  }
}

class MiniPlayerView extends StatelessWidget {
  const MiniPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.read<Library>();
    final pal = Pal.of(context);
    final e = player.current;
    final total = player.duration.inMilliseconds.toDouble();
    return Scaffold(
      backgroundColor: pal.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Drag the strip anywhere to move the window.
        onPanStart: (_) {
          try {
            windowManager.startDragging();
          } catch (_) {}
        },
        child: Row(
          children: [
            Tooltip(
              message: 'Back to the full window',
              child: InkWell(
                onTap: MiniPlayer.close,
                child: e == null
                    ? SizedBox(
                        width: 118,
                        height: 118,
                        child: Icon(Icons.podcasts, size: 40, color: pal.muted),
                      )
                    : Art(e.imageUrl, size: 118, radius: 0),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: pal.text,
                      ),
                    ),
                    Text(
                      e == null ? '' : lib.podcastTitle(e.feedUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: pal.muted),
                    ),
                    Row(
                      children: [
                        Text(
                          fmtDuration(player.position),
                          style: TextStyle(fontSize: 11.5, color: pal.text),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
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
                          style: TextStyle(fontSize: 11.5, color: pal.text),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.fast_rewind),
                          iconSize: 22,
                          color: pal.text,
                          tooltip: 'Back ${lib.skipBackSec}s',
                          onPressed: player.skipBack,
                        ),
                        IconButton(
                          icon: Icon(
                            player.playing ? Icons.pause : Icons.play_arrow,
                          ),
                          iconSize: 32,
                          color: pal.text,
                          tooltip: player.playing ? 'Pause' : 'Play',
                          onPressed: e == null ? null : player.toggle,
                        ),
                        IconButton(
                          icon: const Icon(Icons.fast_forward),
                          iconSize: 22,
                          color: pal.text,
                          tooltip: 'Forward ${lib.skipForwardSec}s',
                          onPressed: player.skipForward,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          iconSize: 22,
                          color: pal.text,
                          tooltip: 'Next in Up Next',
                          onPressed: player.next,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.open_in_full),
                          iconSize: 18,
                          color: pal.muted,
                          tooltip: 'Back to the full window',
                          onPressed: MiniPlayer.close,
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
    );
  }
}
