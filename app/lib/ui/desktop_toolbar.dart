import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/player.dart';
import '../core/settings.dart';
import 'common.dart';
import 'interface_menu.dart';
import 'mini_player.dart';
import 'pal.dart';
import 'zoom.dart';
import 'sleep_ui.dart';

/// Customize Toolbar: while on, the top bar shows an editor underneath it (reorder, hide, resize).
class ToolbarEditor {
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static void toggle() => active.value = !active.value;

  static const labels = {
    'transport': 'Play buttons',
    'volume': 'Volume',
    'display': 'Display',
    'upnext': 'Up Next',
    'downloads': 'Downloads',
    'sleep': 'Sleep timer',
    'speed': 'Speed',
    'search': 'Search',
  };

  /// The switch that shows or hides each part, if it has one.
  static const switches = {
    'transport': 'uiSkipButtons',
    'volume': 'uiVolume',
    'upnext': 'uiUpNextButton',
    'downloads': 'uiDownloadsButton',
    'sleep': 'uiSleepTimer',
    'speed': 'uiSpeed',
    'search': 'uiSearch',
  };

  static const defaults = [
    'toolbarOrder',
    'toolbarHeight',
    'toolbarScale',
    'lcdWidth',
    'searchWidth',
    'volumeWidth',
  ];
}

/// iTunes' top bar: transport, volume, the "LCD", Up Next, downloads, speed, search. The order and
/// sizes are the person's (Customize Toolbar).
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
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ToolbarEditor.active,
    builder: (context, editing, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(context, editing),
        if (editing) const _ToolbarEditorPanel(),
      ],
    ),
  );

  Widget _bar(BuildContext context, bool editing) {
    final player = context.watch<PlayerController>();
    final lib = context.watch<Library>();
    final ui = lib.settings;
    final pal = Pal.of(context);
    final scale = ui.toolbarScale;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: pal.rule),
    );
    final barHeight = ui.toolbarHeight.toDouble();

    Widget? part(String id) {
      switch (id) {
        case 'transport':
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // iTunes' transport: round buttons close together, the play button a little bigger.
              if (ui.uiSkipButtons) ...[
                _RoundButton(
                  icon: Icons.fast_rewind,
                  tooltip: 'Back ${lib.skipBackSec}s',
                  onTap: player.skipBack,
                ),
                const SizedBox(width: 6),
              ],
              _RoundButton(
                icon: player.playing ? Icons.pause : Icons.play_arrow,
                tooltip: player.playing ? 'Pause' : 'Play',
                diameter: 36,
                iconSize: 22,
                onTap: player.current == null ? null : player.toggle,
              ),
              if (ui.uiSkipButtons) ...[
                const SizedBox(width: 6),
                _RoundButton(
                  icon: Icons.fast_forward,
                  tooltip: 'Forward ${lib.skipForwardSec}s',
                  onTap: player.skipForward,
                ),
                const SizedBox(width: 6),
                _RoundButton(
                  icon: Icons.skip_next,
                  tooltip: 'Next in Up Next',
                  onTap: player.next,
                ),
              ],
            ],
          );
        case 'volume':
          return ui.uiVolume ? const VolumeControl() : null;
        case 'display':
          return null; // placed separately: it takes the space that is left
        case 'upnext':
          return ui.uiUpNextButton
              ? _UpNextButton(onGoToPodcast: onGoToPodcast)
              : null;
        case 'downloads':
          return ui.uiDownloadsButton
              ? _DownloadsButton(onOpenDownloads: onOpenDownloads)
              : null;
        case 'sleep':
          return ui.uiSleepTimer ? const SleepTimerButton() : null;
        case 'speed':
          if (!ui.uiSpeed) return null;
          return TextButton(
            style: TextButton.styleFrom(foregroundColor: pal.muted),
            onPressed: () {
              const speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
              final feed = player.current?.feedUrl ?? '';
              final i = speeds.indexWhere(
                (s) => (s - lib.speedFor(feed)).abs() < 0.01,
              );
              player.setSpeed(speeds[(i + 1) % speeds.length]);
            },
            child: Text(
              '${lib.speedFor(player.current?.feedUrl ?? '')}×',
              style: TextStyle(fontSize: 14 * scale),
            ),
          );
        case 'search':
          if (!ui.uiSearch) return null;
          return SizedBox(
            width: ui.searchWidth,
            height: 28 * scale,
            child: TextField(
              focusNode: searchFocus,
              onChanged: onSearch,
              style: TextStyle(fontSize: 13 * scale, color: pal.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.field,
                hintText: 'Search Library',
                hintStyle: TextStyle(color: pal.muted),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16 * scale,
                  color: pal.muted,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: border,
                enabledBorder: border,
              ),
            ),
          );
      }
      return null;
    }

    Widget framed(String id, Widget w) => !editing
        ? w
        : Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(2),
            child: w,
          );

    final children = <Widget>[];
    for (final id in ui.toolbarItems) {
      if (id == 'display') {
        children.add(
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: ui.lcdWidth),
                child: framed(
                  id,
                  Lcd(
                    player: player,
                    onGoToPodcast: onGoToPodcast,
                    height: (barHeight - 8).clamp(46.0, 84.0),
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final w = part(id);
      if (w != null) children.add(framed(id, w));
    }
    // Space between the parts; a wider gap on each side of the display.
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        final nearDisplay =
            children[i] is Expanded || children[i - 1] is Expanded;
        spaced.add(SizedBox(width: nearDisplay ? 16 : 12));
      }
      spaced.add(children[i]);
    }

    return Container(
      height: barHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
          onEditToolbar: ToolbarEditor.toggle,
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(iconSize: 24 * scale),
          ),
          child: IgnorePointer(
            ignoring: editing,
            child: Row(children: spaced),
          ),
        ),
      ),
    );
  }
}

/// What shows under the top bar while Customize Toolbar is on: the parts to drag into order and tick
/// on or off, and a slider for each size.
class _ToolbarEditorPanel extends StatelessWidget {
  const _ToolbarEditorPanel();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final s = lib.settings;
    final pal = Pal.of(context);
    final items = s.toolbarItems;
    final scheme = Theme.of(context).colorScheme;

    Widget slider(
      String label,
      String key,
      double value,
      double min,
      double max, {
      bool whole = false,
    }) => SizedBox(
      width: 250,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: pal.text),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) => lib.setSetting(
                key,
                whole ? v.round() : (v * 20).round() / 20,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      color: pal.header,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Customize Toolbar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: pal.text,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Drag to reorder, tick to show. Parts left of the display sit on its left.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: pal.muted),
                ),
              ),
              TextButton(
                onPressed: () {
                  for (final k in ToolbarEditor.defaults) {
                    lib.settings.reset(k);
                  }
                  lib.setSetting(
                    'toolbarOrder',
                    AppSettings.defaults['toolbarOrder']! as String,
                  );
                },
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: ToolbarEditor.toggle,
                child: const Text('Done'),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (o, n) {
                final next = [...items];
                next.insert(n, next.removeAt(o));
                lib.setSetting('toolbarOrder', next.join(','));
              },
              itemBuilder: (c, i) {
                final id = items[i];
                final sw = ToolbarEditor.switches[id];
                final on = sw == null || (s[sw] as bool);
                return ReorderableDragStartListener(
                  key: ValueKey(id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: id == 'display'
                              ? scheme.primary.withValues(alpha: 0.15)
                              : pal.bg,
                          border: Border.all(color: pal.rule),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: pal.muted,
                            ),
                            if (sw != null)
                              SizedBox(
                                width: 32,
                                child: Checkbox(
                                  value: on,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) =>
                                      lib.setSetting(sw, v ?? true),
                                ),
                              )
                            else
                              const SizedBox(width: 8),
                            Text(
                              ToolbarEditor.labels[id]!,
                              style: TextStyle(
                                fontSize: 13,
                                color: on ? pal.text : pal.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Wrap(
            spacing: 18,
            children: [
              slider(
                'Bar height',
                'toolbarHeight',
                s.toolbarHeight.toDouble(),
                54,
                90,
                whole: true,
              ),
              slider('Button size', 'toolbarScale', s.toolbarScale, 0.8, 1.6),
              slider('Display width', 'lcdWidth', s.lcdWidth, 280, 1100),
              slider('Search width', 'searchWidth', s.searchWidth, 100, 340),
              slider('Volume width', 'volumeWidth', s.volumeWidth, 50, 200),
            ],
          ),
        ],
      ),
    );
  }
}

/// A round, slightly raised button like iTunes' transport controls.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.diameter = 28,
    this.iconSize = 16,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double diameter, iconSize;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final k = context.select<Library, double>((l) => l.settings.toolbarScale);
    final diameter = this.diameter * k, iconSize = this.iconSize * k;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: pal.rule),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [pal.toolbarTop, pal.toolbarBottom],
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: onTap == null
                  ? pal.muted.withValues(alpha: 0.5)
                  : pal.text,
            ),
          ),
        ),
      ),
    );
  }
}

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
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: player.toggleMute,
            ),
            SizedBox(
              width: context.select<Library, double>(
                (l) => l.settings.volumeWidth,
              ),
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

/// The iTunes "LCD": artwork, centred title and podcast, and a scrubber with the time on each end.
/// Click the right-hand time to flip between time left and total length. Click the podcast name to
/// open it, the cover for the mini player.
class Lcd extends StatelessWidget {
  const Lcd({
    super.key,
    required this.player,
    required this.onGoToPodcast,
    this.height = 50,
  });
  final double height;
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
    final k = height / 50; // text and cover grow with the bar
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: pal.lcd,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: pal.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: e == null
          ? Center(
              child: Text(
                'PodSync',
                style: TextStyle(fontSize: 17 * k, color: pal.muted),
              ),
            )
          : Row(
              children: [
                Tooltip(
                  message: 'Open the mini player',
                  child: InkWell(
                    onTap: MiniPlayer.open,
                    child: Art(e.imageUrl, size: height - 2, radius: 0),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5 * k,
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
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12 * k,
                              height: 1.15,
                              color: pal.muted,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 14 * k,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 46 * k,
                                child: Text(
                                  fmtDuration(player.position),
                                  style: TextStyle(
                                    fontSize: 11 * k,
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
                                  width: 54 * k,
                                  child: Text(
                                    total <= 0
                                        ? ''
                                        : (remaining
                                              ? '-${fmtDuration(player.duration - player.position)}'
                                              : fmtDuration(player.duration)),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 11 * k,
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
