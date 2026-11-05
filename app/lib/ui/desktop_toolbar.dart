import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import 'common.dart';
import 'interface_menu.dart';
import 'mini_player.dart';
import 'pal.dart';
import 'zoom.dart';
import 'sleep_ui.dart';

/// iTunes' top bar: history arrows, transport, volume, the "LCD", Up Next, speed, search.
class DesktopToolbar extends StatelessWidget {
  const DesktopToolbar({
    super.key,
    required this.onSearch,
    required this.searchFocus,
    required this.onGoToPodcast,
    required this.onCustomize,
    required this.onOpenDownloads,
  });

  final ValueChanged<String> onSearch;
  final FocusNode searchFocus;
  final ValueChanged<String> onGoToPodcast;
  final VoidCallback onCustomize; // opens Settings > Interface
  final VoidCallback onOpenDownloads; // the full Downloads screen

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
      height: 68,
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
        onSecondaryTapDown: (d) => showToolbarMenu(
          context,
          Zoom.at(context, d.globalPosition),
          lib,
          onCustomize,
        ),
        child: Row(
          children: [
            if (ui.uiSkipButtons)
              IconButton(
                icon: const Icon(Icons.fast_rewind),
                iconSize: 28,
                color: pal.text,
                tooltip: 'Back ${lib.skipBackSec}s',
                onPressed: player.skipBack,
              ),
            IconButton(
              iconSize: 40,
              color: pal.text,
              tooltip: player.playing ? 'Pause' : 'Play',
              icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
              onPressed: player.current == null ? null : player.toggle,
            ),
            if (ui.uiSkipButtons) ...[
              IconButton(
                icon: const Icon(Icons.fast_forward),
                iconSize: 28,
                color: pal.text,
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
            if (ui.uiDownloadsButton)
              _DownloadsButton(onOpenDownloads: onOpenDownloads),
            if (ui.uiSleepTimer) const SleepTimerButton(),
            const SizedBox(width: 4),
            if (ui.uiSpeed)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: pal.muted),
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
                  activeTrackColor: Pal.of(context).muted,
                  inactiveTrackColor: Pal.of(context).rule,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 2,
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
      height: 56,
      decoration: BoxDecoration(
        color: pal.lcd,
        borderRadius: BorderRadius.circular(5),
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
                Tooltip(
                  message: 'Open the mini player',
                  child: InkWell(
                    onTap: MiniPlayer.open,
                    child: Art(e.imageUrl, size: 56, radius: 0),
                  ),
                ),
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
                            fontSize: 14.5,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
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
                              fontSize: 12.5,
                              height: 1.15,
                              color: pal.muted,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 18,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 50,
                                child: Text(
                                  fmtDuration(player.position),
                                  style: TextStyle(
                                    fontSize: 11.5,
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
                                  width: 58,
                                  child: Text(
                                    total <= 0
                                        ? ''
                                        : (remaining
                                              ? '-${fmtDuration(player.duration - player.position)}'
                                              : fmtDuration(player.duration)),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 11.5,
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
      child: Builder(
        builder: (button) => IconButton(
          icon: const Icon(Icons.format_list_numbered),
          tooltip: 'Up Next',
          onPressed: () => showUpNextPopover(
            context,
            onGoToPodcast: onGoToPodcast,
            anchor: button,
          ),
        ),
      ),
    );
  }
}

/// iTunes 12's "Up Next" dropdown: what is playing and what follows. Click to play, drag to reorder.
Future<void> showUpNextPopover(
  BuildContext context, {
  required ValueChanged<String> onGoToPodcast,
  BuildContext? anchor,
}) => _showPopover(
  context,
  'Close Up Next',
  anchor,
  (c) => _UpNextPanel(onGoToPodcast: onGoToPodcast),
);

/// Opens [panel] as a dropdown that hangs under [anchor] (the button that opened it), so Up Next
/// and Downloads each sit under their own button. Without an anchor it drops from the top centre.
Future<void> _showPopover(
  BuildContext context,
  String label,
  BuildContext? anchor,
  Widget Function(BuildContext) panel,
) {
  const panelWidth = 460.0;
  Rect? at;
  final box = anchor?.findRenderObject();
  final overlay = Overlay.of(context).context.findRenderObject();
  if (box is RenderBox && box.hasSize && overlay is RenderBox) {
    at = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (c, _, _) {
      if (at == null) {
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: panel(c),
          ),
        );
      }
      final width = MediaQuery.sizeOf(c).width;
      final left = (at.right - panelWidth).clamp(
        8.0,
        (width - panelWidth - 8).clamp(8.0, width),
      );
      return Stack(
        children: [Positioned(left: left, top: at.bottom + 6, child: panel(c))],
      );
    },
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

/// The downloads button: a ring while something downloads, and a count of what is running or waiting.
class _DownloadsButton extends StatelessWidget {
  const _DownloadsButton({required this.onOpenDownloads});
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final running = dm.activeIds.length + dm.queuedIds.length;
    final failed = dm.failedIds.length;
    final busy = dm.activeIds.isNotEmpty;
    return Badge(
      isLabelVisible: running > 0 || failed > 0,
      backgroundColor: running == 0 && failed > 0
          ? Theme.of(context).colorScheme.error
          : null,
      label: Text(running > 0 ? '$running' : '!'),
      offset: const Offset(-4, 4),
      child: Builder(
        builder: (button) => IconButton(
          tooltip: busy ? 'Downloads: $running in progress' : 'Downloads',
          icon: Icon(
            busy ? Icons.downloading : Icons.download_for_offline_outlined,
          ),
          onPressed: () => showDownloadsPopover(
            context,
            onOpenDownloads: onOpenDownloads,
            anchor: button,
          ),
        ),
      ),
    );
  }
}

/// A dropdown like Up Next's, for downloads: only what is in flight, with progress, what waits and
/// what failed. Finished downloads live on the Downloads screen.
Future<void> showDownloadsPopover(
  BuildContext context, {
  required VoidCallback onOpenDownloads,
  BuildContext? anchor,
}) => _showPopover(
  context,
  'Close Downloads',
  anchor,
  (c) => _DownloadsPanel(
    onOpenDownloads: () {
      Navigator.pop(c);
      onOpenDownloads();
    },
  ),
);

class _DownloadsPanel extends StatelessWidget {
  const _DownloadsPanel({required this.onOpenDownloads});
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final lib = context.watch<Library>();
    final pal = Pal.of(context);
    final active = dm.activeIds;
    final waiting = dm.queuedIds;
    final failed = dm.failedIds;
    final nothing = active.isEmpty && waiting.isEmpty && failed.isEmpty;

    Widget section(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: pal.muted,
        ),
      ),
    );

    Widget iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      tooltip: tip,
      icon: Icon(icon),
      onPressed: onTap,
    );

    Widget row(String id, {Widget? trailing}) {
      final e = lib.episodes[id];
      final info = dm.infoOf(id);
      if (e == null || info == null) return const SizedBox.shrink();
      final detail = switch (info.state) {
        DownloadState.downloading =>
          info.total > 0
              ? '${fmtBytes(info.bytes)} of ${fmtBytes(info.total)}'
              : fmtBytes(info.bytes),
        DownloadState.queued => info.error ?? 'Waiting',
        DownloadState.failed => 'Failed: ${info.error}',
        DownloadState.done => fmtBytes(info.bytes),
      };
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        child: Row(
          children: [
            Art(e.imageUrl, size: 36, radius: 2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: pal.text,
                    ),
                  ),
                  Text(
                    '${lib.podcastTitle(e.feedUrl)} · $detail',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: info.state == DownloadState.failed
                          ? Theme.of(context).colorScheme.error
                          : pal.muted,
                    ),
                  ),
                  if (info.state == DownloadState.downloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: LinearProgressIndicator(
                        value: info.fraction,
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
    }

    final summary = [
      if (active.isNotEmpty) '${active.length} downloading',
      if (waiting.isNotEmpty) '${waiting.length} waiting',
      if (failed.isNotEmpty) '${failed.length} failed',
      if (active.isEmpty && waiting.isEmpty && failed.isEmpty) 'All done',
    ].join(' · ');

    return Material(
      elevation: 12,
      color: pal.bg,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 560),
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
                          'Downloads',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: pal.text,
                          ),
                        ),
                        Text(
                          summary,
                          style: TextStyle(fontSize: 11, color: pal.muted),
                        ),
                      ],
                    ),
                  ),
                  if (active.isNotEmpty || waiting.isNotEmpty)
                    TextButton(
                      onPressed: dm.cancelAll,
                      child: const Text('Cancel All'),
                    ),
                  TextButton(
                    onPressed: onOpenDownloads,
                    child: const Text('Show All'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: pal.rule),
            if (nothing)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Nothing downloading right now.\nFinished downloads are under Show All.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (active.isNotEmpty) section('DOWNLOADING'),
                    for (final id in active)
                      row(
                        id,
                        trailing: iconBtn(
                          Icons.close,
                          'Cancel',
                          () => dm.cancel(id),
                        ),
                      ),
                    if (waiting.isNotEmpty) section('WAITING'),
                    for (final id in waiting)
                      row(
                        id,
                        trailing: iconBtn(
                          Icons.close,
                          'Cancel',
                          () => dm.cancel(id),
                        ),
                      ),
                    if (failed.isNotEmpty) section('FAILED'),
                    for (final id in failed)
                      row(
                        id,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconBtn(Icons.refresh, 'Retry', () => dm.retry(id)),
                            iconBtn(
                              Icons.close,
                              'Dismiss',
                              () => dm.delete(id),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The second toolbar row, like iTunes': back and forward as one joined control, a menu of the
/// places in the library, and Library / Store tabs in the middle.
class DesktopNavRow extends StatelessWidget {
  const DesktopNavRow({
    super.key,
    required this.onBack,
    required this.onForward,
    required this.title,
    required this.places,
    required this.storeActive,
    required this.onLibrary,
    required this.onStore,
  });
  final VoidCallback? onBack; // null when there is nowhere to go back to
  final VoidCallback? onForward;
  final String title; // where you are now
  final List<(String, VoidCallback)> places;
  final bool storeActive;
  final VoidCallback onLibrary;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final showArrows = context.select<Library, bool>(
      (l) => l.settings.uiBackForward,
    );

    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 26,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? pal.rule : pal.text,
          ),
        ),
      ),
    );

    Widget tab(String label, bool active, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: active ? pal.selected : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : pal.text,
          ),
        ),
      ),
    );

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: pal.bg,
        border: Border(bottom: BorderSide(color: pal.rule)),
      ),
      child: Row(
        children: [
          if (showArrows)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: pal.rule),
                borderRadius: BorderRadius.circular(5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  arrow(Icons.chevron_left, 'Go back', onBack),
                  Container(width: 1, height: 26, color: pal.rule),
                  arrow(Icons.chevron_right, 'Go forward', onForward),
                ],
              ),
            ),
          const SizedBox(width: 10),
          PopupMenuButton<int>(
            tooltip: 'Go to',
            onSelected: (i) => places[i].$2(),
            itemBuilder: (c) => [
              for (var i = 0; i < places.length; i++)
                PopupMenuItem(value: i, child: Text(places[i].$1)),
            ],
            child: Container(
              height: 26,
              padding: const EdgeInsets.only(left: 8, right: 4),
              decoration: BoxDecoration(
                border: Border.all(color: pal.rule),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.podcasts, size: 16, color: pal.muted),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: pal.text),
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 16, color: pal.muted),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tab('Library', !storeActive, onLibrary),
                  const SizedBox(width: 6),
                  tab('Store', storeActive, onStore),
                ],
              ),
            ),
          ),
          // Balances the left side so the tabs sit in the middle.
          SizedBox(width: showArrows ? 210 : 150),
        ],
      ),
    );
  }
}
