import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/errors.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';
import '../core/opml.dart';
import '../core/player.dart';
import 'common.dart';
import 'pal.dart';
import 'sleep_ui.dart';

/// What the menu bar can ask the desktop shell to do.
class DesktopCommands {
  const DesktopCommands({
    required this.go,
    required this.focusSearch,
    required this.goPodcast,
    required this.openUpNext,
  });

  /// podcasts | episodes | queue | favorites | history | store | settings
  final void Function(String where) go;
  final VoidCallback focusSearch;
  final ValueChanged<String> goPodcast;
  final VoidCallback openUpNext;
}

const _sortLabels = {
  QueueSort.oldestFirst: 'Release Date, Oldest First',
  QueueSort.newestFirst: 'Release Date, Newest First',
  QueueSort.title: 'Title',
  QueueSort.podcast: 'Podcast',
  QueueSort.shortest: 'Time Left, Shortest First',
  QueueSort.longest: 'Time Left, Longest First',
};

/// iTunes' File / Edit / View / Controls / Account / Help menus, with shortcuts.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key, required this.commands});
  final DesktopCommands commands;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.watch<PlayerController>();
    final dm = context.watch<DownloadManager>();
    final pal = Pal.of(context);
    final s = lib.settings;

    SingleActivator ctrl(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool alt = false,
    }) => SingleActivator(k, control: true, shift: shift, alt: alt);

    Widget item(
      String label,
      VoidCallback? onPressed, {
      SingleActivator? shortcut,
      Widget? trailing,
    }) => MenuItemButton(
      onPressed: onPressed,
      // Only a label: the keys themselves are bound by desktopShortcuts(), so they keep working
      // when this menu bar is closed or hidden.
      trailingIcon: shortcut != null ? Text(shortcutLabel(shortcut)) : trailing,
      child: Text(label),
    );

    Widget toggle(String label, String key, {SingleActivator? shortcut}) =>
        CheckboxMenuButton(
          value: lib.settings[key] as bool,
          onChanged: (v) => lib.setSetting(key, v ?? false),
          child: Text(shortcut == null ? label : label),
        );

    final playing = player.current;
    final pin = playing?.id;

    return MenuBarTheme(
      data: MenuBarThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(pal.toolbarTop),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 4),
          ),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: pal.toolbarTop,
          border: Border(bottom: BorderSide(color: pal.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: MenuBar(
                style: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(pal.toolbarTop),
                  elevation: const WidgetStatePropertyAll(0),
                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                  minimumSize: const WidgetStatePropertyAll(
                    Size.fromHeight(28),
                  ),
                ),
                children: [
                  SubmenuButton(
                    menuChildren: [
                      item(
                        'Subscribe to Podcast by URL…',
                        () => subscribeByUrl(context, lib, commands),
                        shortcut: ctrl(LogicalKeyboardKey.keyU),
                      ),
                      item(
                        'Find Podcasts',
                        () => commands.go('store'),
                        shortcut: ctrl(LogicalKeyboardKey.keyF, shift: true),
                      ),
                      const Divider(height: 1),
                      item(
                        'Import AntennaPod Backup or OPML…',
                        () => commands.go('settings'),
                      ),
                      item(
                        'Export Subscriptions as OPML…',
                        () => exportOpml(context, lib),
                      ),
                      const Divider(height: 1),
                      item(
                        'Download Up Next Episodes',
                        lib.queueEpisodes.any(
                              (e) => !dm.isDownloaded(e.id) && !dm.isBusy(e.id),
                            )
                            ? () => dm.downloadAll(lib.queueEpisodes)
                            : null,
                      ),
                      item(
                        'Remove Played Downloads',
                        dm.doneIds.any((id) => lib.progressOf(id).played)
                            ? () async {
                                final n = await dm.deletePlayed();
                                if (context.mounted) {
                                  showSnack(context, 'Deleted $n played');
                                }
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      item(
                        'Refresh All Podcasts',
                        () => lib.refreshAll(),
                        shortcut: ctrl(LogicalKeyboardKey.keyR),
                      ),
                      item(
                        'Sync Now',
                        lib.syncEnabled ? () => lib.sync() : null,
                        shortcut: ctrl(LogicalKeyboardKey.keyR, shift: true),
                      ),
                      const Divider(height: 1),
                      item('Quit', () async {
                        await lib.saveNow();
                        exit(0);
                      }, shortcut: ctrl(LogicalKeyboardKey.keyQ)),
                    ],
                    child: const Text('File'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        lib.canUndoQueue
                            ? 'Undo ${lib.queueUndoLabel}'
                            : 'Undo',
                        lib.canUndoQueue ? () => lib.undoQueue() : null,
                        shortcut: ctrl(LogicalKeyboardKey.keyZ),
                      ),
                      const Divider(height: 1),
                      item(
                        'Find in Library',
                        commands.focusSearch,
                        shortcut: ctrl(LogicalKeyboardKey.keyF),
                      ),
                    ],
                    child: const Text('Edit'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        'Podcasts',
                        () => commands.go('podcasts'),
                        shortcut: ctrl(LogicalKeyboardKey.digit1),
                      ),
                      item(
                        'Episodes',
                        () => commands.go('episodes'),
                        shortcut: ctrl(LogicalKeyboardKey.digit2),
                      ),
                      item(
                        'Up Next',
                        () => commands.go('queue'),
                        shortcut: ctrl(LogicalKeyboardKey.digit3),
                      ),
                      item(
                        'Favorites',
                        () => commands.go('favorites'),
                        shortcut: ctrl(LogicalKeyboardKey.digit4),
                      ),
                      item(
                        'Recently Played',
                        () => commands.go('history'),
                        shortcut: ctrl(LogicalKeyboardKey.digit5),
                      ),
                      item(
                        'Downloads',
                        () => commands.go('downloads'),
                        shortcut: ctrl(LogicalKeyboardKey.digit6),
                      ),
                      item(
                        'Statistics',
                        () => commands.go('stats'),
                        shortcut: ctrl(LogicalKeyboardKey.digit7),
                      ),
                      const Divider(height: 1),
                      toggle('Show Sidebar', 'showSidebar'),
                      toggle('Show Artwork Pane', 'showArtworkPane'),
                      CheckboxMenuButton(
                        value: s.showDetails,
                        onChanged: (v) =>
                            lib.setSetting('showDetails', v ?? false),
                        child: const Text('Show Details Pane'),
                      ),
                      toggle('Show Status Bar', 'showStatusBar'),
                      SubmenuButton(
                        menuChildren: [
                          toggle('Download status', 'colDownload'),
                          toggle('Time', 'colTime'),
                          toggle('Starts in (Up Next)', 'colStarts'),
                          toggle('Podcast', 'colPodcast'),
                          toggle('Rating', 'colRating'),
                          toggle('Release Date', 'colDate'),
                        ],
                        child: const Text('Columns'),
                      ),
                      const Divider(height: 1),
                      item(
                        'Up Next Popover',
                        commands.openUpNext,
                        shortcut: ctrl(LogicalKeyboardKey.keyU, alt: true),
                      ),
                    ],
                    child: const Text('View'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        player.playing ? 'Pause' : 'Play',
                        playing == null ? null : player.toggle,
                        trailing: const Text('Space'),
                      ),
                      item(
                        'Skip Back ${lib.skipBackSec} s',
                        playing == null ? null : player.skipBack,
                        shortcut: ctrl(LogicalKeyboardKey.arrowLeft),
                      ),
                      item(
                        'Skip Forward ${lib.skipForwardSec} s',
                        playing == null ? null : player.skipForward,
                        shortcut: ctrl(LogicalKeyboardKey.arrowRight),
                      ),
                      item(
                        'Next in Up Next',
                        player.next,
                        shortcut: ctrl(
                          LogicalKeyboardKey.arrowRight,
                          alt: true,
                        ),
                      ),
                      item(
                        'Go to Current Episode',
                        playing == null
                            ? null
                            : () => commands.goPodcast(playing.feedUrl),
                        shortcut: ctrl(LogicalKeyboardKey.keyL),
                      ),
                      const Divider(height: 1),
                      item(
                        'Increase Volume',
                        () => player.changeVolume(0.1),
                        shortcut: ctrl(LogicalKeyboardKey.arrowUp),
                      ),
                      item(
                        'Decrease Volume',
                        () => player.changeVolume(-0.1),
                        shortcut: ctrl(LogicalKeyboardKey.arrowDown),
                      ),
                      CheckboxMenuButton(
                        value: s.muted,
                        onChanged: (_) => player.toggleMute(),
                        child: const Text('Mute'),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          for (final v in const [0.8, 1.0, 1.2, 1.5, 1.8, 2.0])
                            RadioMenuButton<double>(
                              value: v,
                              groupValue: lib.speedFor(playing?.feedUrl ?? ''),
                              onChanged: (x) => player.setSpeed(x ?? 1.0),
                              child: Text('$v×'),
                            ),
                        ],
                        child: const Text('Speed'),
                      ),
                      SubmenuButton(
                        menuChildren: [
                          if (player.sleepActive)
                            item(
                              '${sleepStatus(player)} (turn off)',
                              () => applySleepChoice(player, 'off'),
                            ),
                          for (final k in sleepChoices.keys)
                            item(k, () => applySleepChoice(player, k)),
                          item(
                            'End of Episode',
                            () => applySleepChoice(player, 'end'),
                          ),
                          if (player.sleepRemaining != null)
                            item(
                              'Add 10 Minutes',
                              () => applySleepChoice(player, 'plus'),
                            ),
                        ],
                        child: Text(
                          player.sleepActive
                              ? 'Sleep Timer (${sleepStatus(player)})'
                              : 'Sleep Timer',
                        ),
                      ),
                      const Divider(height: 1),
                      SubmenuButton(
                        menuChildren: [
                          SubmenuButton(
                            menuChildren: [
                              for (final e in _sortLabels.entries)
                                item(e.value, () {
                                  lib.sortQueue(e.key, pinId: pin);
                                  showQueueUndo(context, lib, 'Up Next sorted');
                                }),
                            ],
                            child: const Text('Sort By'),
                          ),
                          item('Shuffle', () {
                            lib.shuffleQueue(pinId: pin);
                            showQueueUndo(context, lib, 'Up Next shuffled');
                          }),
                          item('Remove Played Episodes', () {
                            final n = lib.removePlayedFromQueue();
                            showQueueUndo(
                              context,
                              lib,
                              n == 0
                                  ? 'No played episodes in Up Next'
                                  : 'Removed $n played',
                            );
                          }),
                          item(
                            'Clear Up Next',
                            lib.queue.isEmpty
                                ? null
                                : () {
                                    lib.clearQueue();
                                    showQueueUndo(
                                      context,
                                      lib,
                                      'Up Next cleared',
                                    );
                                  },
                          ),
                        ],
                        child: const Text('Up Next'),
                      ),
                    ],
                    child: const Text('Controls'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        'Settings…',
                        () => commands.go('settings'),
                        shortcut: ctrl(LogicalKeyboardKey.comma),
                      ),
                      item(
                        'Sync Now',
                        lib.syncEnabled ? () => lib.sync() : null,
                      ),
                    ],
                    child: const Text('Account'),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        'About PodSync',
                        () => showAboutDialog(
                          context: context,
                          applicationName: 'PodSync',
                          applicationVersion: '0.1.0',
                          applicationLegalese:
                              'A podcast app that syncs everything.',
                        ),
                      ),
                    ],
                    child: const Text('Help'),
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

Future<void> subscribeByUrl(
  BuildContext context,
  Library lib,
  DesktopCommands commands,
) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Subscribe to Podcast'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(c, v),
          decoration: const InputDecoration(
            hintText: 'https://example.com/feed.xml',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text),
          child: const Text('Subscribe'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (url == null || url.trim().isEmpty || !context.mounted) return;
  final feed = url.trim();
  if (!feed.startsWith('http')) {
    showSnack(context, 'That does not look like a feed address');
    return;
  }
  try {
    await lib.subscribe(feed);
    commands.goPodcast(feed);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, 'Could not subscribe: ${cleanError(e)}');
    }
  }
}

Future<void> exportOpml(BuildContext context, Library lib) async {
  final bytes = Uint8List.fromList(utf8.encode(buildOpml(lib.subscriptions)));
  final saved = await FilePicker.saveFile(
    fileName: 'podsync-subscriptions.opml',
    bytes: bytes,
    mimeType: 'text/x-opml',
  );
  if (saved != null && context.mounted) {
    showSnack(context, 'Exported ${lib.subscriptions.length} podcasts');
  }
}

/// "Ctrl+Shift+F", for showing next to a menu item.
String shortcutLabel(SingleActivator a) {
  final key = a.trigger;
  final name = switch (key) {
    LogicalKeyboardKey.arrowLeft => 'Left',
    LogicalKeyboardKey.arrowRight => 'Right',
    LogicalKeyboardKey.arrowUp => 'Up',
    LogicalKeyboardKey.arrowDown => 'Down',
    LogicalKeyboardKey.comma => ',',
    _ => key.keyLabel.length == 1 ? key.keyLabel.toUpperCase() : key.keyLabel,
  };
  return [
    if (a.control) 'Ctrl',
    if (a.alt) 'Alt',
    if (a.shift) 'Shift',
    name,
  ].join('+');
}

/// Every keyboard shortcut of the desktop app. These live outside the menu bar on purpose, so they
/// work whether or not the menu bar is shown.
Map<ShortcutActivator, VoidCallback> desktopShortcuts(
  BuildContext context,
  DesktopCommands c,
) {
  final lib = context.read<Library>();
  final player = context.read<PlayerController>();
  SingleActivator ctrl(
    LogicalKeyboardKey k, {
    bool shift = false,
    bool alt = false,
  }) => SingleActivator(k, control: true, shift: shift, alt: alt);
  return {
    ctrl(LogicalKeyboardKey.keyU): () => subscribeByUrl(context, lib, c),
    ctrl(LogicalKeyboardKey.keyF, shift: true): () => c.go('store'),
    ctrl(LogicalKeyboardKey.keyR): () => lib.refreshAll(),
    ctrl(LogicalKeyboardKey.keyR, shift: true): () {
      if (lib.syncEnabled) lib.sync();
    },
    ctrl(LogicalKeyboardKey.keyQ): () async {
      await lib.saveNow();
      exit(0);
    },
    ctrl(LogicalKeyboardKey.keyZ): () {
      if (lib.canUndoQueue) lib.undoQueue();
    },
    ctrl(LogicalKeyboardKey.keyF): c.focusSearch,
    ctrl(LogicalKeyboardKey.digit1): () => c.go('podcasts'),
    ctrl(LogicalKeyboardKey.digit2): () => c.go('episodes'),
    ctrl(LogicalKeyboardKey.digit3): () => c.go('queue'),
    ctrl(LogicalKeyboardKey.digit4): () => c.go('favorites'),
    ctrl(LogicalKeyboardKey.digit5): () => c.go('history'),
    ctrl(LogicalKeyboardKey.digit6): () => c.go('downloads'),
    ctrl(LogicalKeyboardKey.digit7): () => c.go('stats'),
    ctrl(LogicalKeyboardKey.keyU, alt: true): c.openUpNext,
    ctrl(LogicalKeyboardKey.arrowLeft): () {
      if (player.current != null) player.skipBack();
    },
    ctrl(LogicalKeyboardKey.arrowRight): () {
      if (player.current != null) player.skipForward();
    },
    ctrl(LogicalKeyboardKey.arrowRight, alt: true): player.next,
    ctrl(LogicalKeyboardKey.keyL): () {
      final now = player.current; // read when the keys are pressed, not when the shell last built
      if (now != null) c.goPodcast(now.feedUrl);
    },
    ctrl(LogicalKeyboardKey.arrowUp): () => player.changeVolume(0.1),
    ctrl(LogicalKeyboardKey.arrowDown): () => player.changeVolume(-0.1),
    ctrl(LogicalKeyboardKey.comma): () => c.go('settings'),
  };
}
