import 'package:flutter/material.dart';

import '../core/library.dart';

/// One show/hide switch in a right-click menu.
class _Toggle {
  const _Toggle(this.key, this.label);
  final String key;
  final String label;
}

const _toolbarToggles = [
  _Toggle('uiMenuBar', 'Menu Bar'),
  _Toggle('uiBackForward', 'Back and Forward Arrows'),
  _Toggle('uiSkipButtons', 'Skip and Next Buttons'),
  _Toggle('uiVolume', 'Volume'),
  _Toggle('uiUpNextButton', 'Up Next Button'),
  _Toggle('uiSleepTimer', 'Sleep Timer'),
  _Toggle('uiSpeed', 'Speed Button'),
  _Toggle('uiSearch', 'Search Field'),
];

const _sidebarToggles = [
  _Toggle('uiNavPodcasts', 'Podcasts'),
  _Toggle('uiNavEpisodes', 'Episodes'),
  _Toggle('uiNavUpNext', 'Up Next'),
  _Toggle('uiNavFavorites', 'Favorites'),
  _Toggle('uiNavHistory', 'Recently Played'),
  _Toggle('uiNavDownloads', 'Downloads'),
  _Toggle('uiNavStats', 'Statistics'),
  _Toggle('uiNavStore', 'Find Podcasts'),
  _Toggle('uiNavSubscriptions', 'Subscriptions List'),
  _Toggle('uiSidebarCounts', 'Counts'),
];

Future<void> _show(
  BuildContext context,
  Offset at,
  Library lib,
  List<_Toggle> toggles,
  VoidCallback onMore,
) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(at, at),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final t in toggles)
        CheckedPopupMenuItem(
          value: t.key,
          checked: lib.settings[t.key] as bool,
          child: Text(t.label),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: '_more', child: Text('Customize Interface…')),
    ],
  );
  if (choice == null) return;
  if (choice == '_more') {
    onMore();
  } else {
    lib.setSetting(choice, !(lib.settings[choice] as bool));
  }
}

/// Right-click on the toolbar: choose what it shows, like a browser's "customize toolbar".
/// This also means a hidden menu bar can always be brought back.
Future<void> showToolbarMenu(
  BuildContext context,
  Offset at,
  Library lib,
  VoidCallback onMore,
) => _show(context, at, lib, _toolbarToggles, onMore);

/// Right-click on the sidebar: choose which sections it lists.
Future<void> showSidebarMenu(
  BuildContext context,
  Offset at,
  Library lib,
  VoidCallback onMore,
) => _show(context, at, lib, _sidebarToggles, onMore);
