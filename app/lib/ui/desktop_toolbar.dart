import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'interface_menu.dart';
import 'pal.dart';
import 'sleep_ui.dart';

/// iTunes' top bar: history arrows, transport, volume, the "LCD", Up Next, speed, search.
class DesktopToolbar extends StatelessWidget {
  const DesktopToolbar({
    super.key,
    required this.onSearch,
    required this.searchFocus,
    required this.onBack,
    required this.onForward,
    required this.onGoToPodcast,
    required this.onCustomize,
  });

  final ValueChanged<String> onSearch;
  final FocusNode searchFocus;
  final VoidCallback? onBack; // null when there is nowhere to go back to
  final VoidCallback? onForward;
  final ValueChanged<String> onGoToPodcast;
  final VoidCallback onCustomize; // opens Settings > Interface

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.watch<Library>();
    final ui = lib.settings;
    final pal = Pal.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: pal.rule),
    );
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.toolbarTop, pal.toolbarBottom],
        ),
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (d) =>
            showToolbarMenu(context, d.globalPosition, lib, onCustomize),
        child: Row(
          children: [
            if (ui.uiBackForward) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                iconSize: 18,
                tooltip: 'Go back',
                onPressed: onBack,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                iconSize: 18,
                tooltip: 'Go forward',
                onPressed: onForward,
              ),
              const SizedBox(width: 8),
            ],
            if (ui.uiSkipButtons)
              IconButton(
                icon: const Icon(Icons.fast_rewind),
                tooltip: 'Back ${lib.skipBackSec}s',
                onPressed: player.skipBack,
              ),
            IconButton(
              iconSize: 34,
              tooltip: player.playing ? 'Pause' : 'Play',
              icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
              onPressed: player.current == null ? null : player.toggle,
            ),
            if (ui.uiSkipButtons) ...[
              IconButton(
                icon: const Icon(Icons.fast_forward),
                tooltip: 'Forward ${lib.skipForwardSec}s',
                onPressed: player.skipForward,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Next in Up Next',
                onPressed: player.next,
              ),
            ],
            if (ui.uiVolume) ...[
              const SizedBox(width: 8),
              const VolumeControl(),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Lcd(player: player, onGoToPodcast: onGoToPodcast),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (ui.uiUpNextButton) _UpNextButton(onGoToPodcast: onGoToPodcast),
            if (ui.uiSleepTimer) const SleepTimerButton(),
            const SizedBox(width: 4),
            if (ui.uiSpeed)
              TextButton(
                onPressed: () {
                  const speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
                  final feed = player.current?.feedUrl ?? '';
                  final i = speeds.indexWhere(
                    (s) => (s - lib.speedFor(feed)).abs() < 0.01,
                  );
                  player.setSpeed(speeds[(i + 1) % speeds.length]);
                },
                child: Text('${lib.speedFor(player.current?.feedUrl ?? '')}×'),
              ),
            if (ui.uiSearch)
              SizedBox(
                width: 180,
                height: 30,
                child: TextField(
                  focusNode: searchFocus,
                  onChanged: onSearch,
                  style: TextStyle(fontSize: 13, color: pal.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: pal.field,
                    hintText: 'Search Library',
                    hintStyle: TextStyle(color: pal.muted),
                    prefixIcon: Icon(Icons.search, size: 16, color: pal.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: border,
                    enabledBorder: border,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Speaker button (click to mute) and a volume slider. The mouse wheel over it nudges the volume.
class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final s = context.select<Library, ({double volume, bool muted})>(
      (l) => (volume: l.settings.volume, muted: l.settings.muted),
    );
    final level = s.muted ? 0.0 : s.volume;
    final icon = level == 0
        ? Icons.volume_off
        : (level < 0.34
              ? Icons.volume_mute
              : (level < 0.67 ? Icons.volume_down : Icons.volume_up));
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          player.changeVolume(e.scrollDelta.dy < 0 ? 0.05 : -0.05);
        }
      },
      child: Tooltip(
        message: s.muted ? 'Muted' : 'Volume ${(level * 100).round()}%',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(icon),
              iconSize: 20,
              onPressed: player.toggleMute,
            ),
            SizedBox(
              width: 92,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(value: level, onChanged: player.setVolume),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The iTunes "LCD": artwork, title, podcast and a scrubber. Click the right-hand time to flip between
/// time left and total length. Click the podcast name to open it.
class Lcd extends StatelessWidget {
  const Lcd({super.key, required this.player, required this.onGoToPodcast});
  final PlayerController player;
  final ValueChanged<String> onGoToPodcast;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<Library>();
    final pal = Pal.of(context);
    final e = player.current;
    final total = player.duration.inMilliseconds.toDouble();
    final remaining = context.select<Library, bool>(
      (l) => l.settings.lcdRemaining,
    );
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: pal.lcd,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: pal.rule),
      ),
      child: e == null
          ? Center(
              child: Text(
                'PodSync',
                style: TextStyle(fontSize: 18, color: pal.muted),
              ),
            )
          : Row(
              children: [
                Art(e.imageUrl, size: 46, radius: 0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: pal.text,
                          ),
                        ),
                        InkWell(
                          onTap: () => onGoToPodcast(e.feedUrl),
                          child: Text(
                            lib.podcastTitle(e.feedUrl),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.15,
                              color: pal.muted,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 16,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 44,
                                child: Text(
                                  fmtDuration(player.position),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: pal.text,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 4,
                                    ),
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
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
                              InkWell(
                                onTap: () =>
                                    lib.setSetting('lcdRemaining', !remaining),
                                child: SizedBox(
                                  width: 52,
                                  child: Text(
                                    total <= 0
                                        ? ''
                                        : (remaining
                                              ? '-${fmtDuration(player.duration - player.position)}'
                                              : fmtDuration(player.duration)),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: pal.text,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _UpNextButton extends StatelessWidget {
  const _UpNextButton({required this.onGoToPodcast});
  final ValueChanged<String> onGoToPodcast;

  @override
  Widget build(BuildContext context) {
    final count = context.select<Library, int>((l) => l.queue.length);
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      offset: const Offset(-4, 4),
      child: IconButton(
        icon: const Icon(Icons.format_list_numbered),
        tooltip: 'Up Next',
        onPressed: () =>
            showUpNextPopover(context, onGoToPodcast: onGoToPodcast),
      ),
    );
  }
}

/// iTunes 12's "Up Next" dropdown: what is playing and what follows. Click to play, drag to reorder.
Future<void> showUpNextPopover(
  BuildContext context, {
  required ValueChanged<String> onGoToPodcast,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Up Next',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (c, _, _) => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: _UpNextPanel(onGoToPodcast: onGoToPodcast),
      ),
    ),
  );
}

class _UpNextPanel extends StatelessWidget {
  const _UpNextPanel({required this.onGoToPodcast});
  final ValueChanged<String> onGoToPodcast;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<PlayerController>();
    final currentId = context.select<PlayerController, String?>(
      (p) => p.current?.id,
    );
    final pal = Pal.of(context);
    final eps = lib.queueEpisodes;

    return Material(
      elevation: 12,
      color: pal.bg,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(
          border: Border.all(color: pal.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Up Next',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: pal.text,
                          ),
                        ),
                        Text(
                          eps.isEmpty
                              ? 'Nothing queued'
                              : '${eps.length} episodes · ${fmtLong(lib.queueRemaining)} left',
                          style: TextStyle(fontSize: 11, color: pal.muted),
                        ),
                      ],
                    ),
                  ),
                  if (lib.canUndoQueue)
                    TextButton(
                      onPressed: lib.undoQueue,
                      child: Text('Undo ${lib.queueUndoLabel}'),
                    ),
                  TextButton(
                    onPressed: eps.isEmpty ? null : lib.clearQueue,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: pal.rule),
            if (eps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Right-click an episode and choose Add to Up Next',
                  style: TextStyle(color: pal.muted),
                ),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: eps.length,
                  onReorderItem: (o, n) =>
                      lib.reorderQueue(o, n > o ? n + 1 : n),
                  itemBuilder: (c, i) => _UpNextRow(
                    key: ValueKey(eps[i].id),
                    index: i,
                    episode: eps[i],
                    playing: currentId == eps[i].id,
                    onPlay: () => player.play(eps[i]),
                    onOpen: () {
                      Navigator.pop(context);
                      onGoToPodcast(eps[i].feedUrl);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UpNextRow extends StatelessWidget {
  const _UpNextRow({
    super.key,
    required this.index,
    required this.episode,
    required this.playing,
    required this.onPlay,
    required this.onOpen,
  });
  final int index;
  final Episode episode;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<Library>();
    final pal = Pal.of(context);
    final left = lib.remainingOf(episode);
    return InkWell(
      onTap: onPlay,
      child: Container(
        height: 52,
        color: playing
            ? pal.selected.withValues(alpha: 0.18)
            : (index.isOdd ? pal.stripe : null),
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.drag_indicator, size: 16, color: pal.muted),
              ),
            ),
            Art(episode.imageUrl, size: 38, radius: 2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: playing ? FontWeight.bold : FontWeight.w500,
                      color: pal.text,
                    ),
                  ),
                  Text(
                    '${lib.podcastTitle(episode.feedUrl)}${left > Duration.zero ? '  ·  ${fmtLong(left)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ],
              ),
            ),
            if (playing) Icon(Icons.volume_up, size: 16, color: pal.selected),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: 'Go to podcast',
              icon: const Icon(Icons.open_in_new),
              onPressed: onOpen,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => lib.removeFromQueue(episode.id),
            ),
          ],
        ),
      ),
    );
  }
}
