import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';
import 'account.dart';
import 'common.dart';
import 'paged.dart';
import 'podcast_settings.dart';

// ---- model -------------------------------------------------------------------

sealed class SettingItem {
  const SettingItem(this.title, [this.subtitle = '']);
  final String title;
  final String subtitle;
}

class ToggleItem extends SettingItem {
  const ToggleItem(super.title, super.subtitle, this.get, this.set);
  final bool Function() get;
  final void Function(bool) set;
}

/// A pick-one setting. Not generic itself, so the row widget can handle any kind;
/// [ChoiceItem.typed] keeps the value type checked where the item is declared.
class ChoiceItem extends SettingItem {
  const ChoiceItem.typed(super.title, super.subtitle, this.get, this.set, this.options);
  final Object Function() get;
  final void Function(Object) set;
  final Map<String, Object> options; // label -> value
}

class TextItem extends SettingItem {
  const TextItem(super.title, super.subtitle, this.get, this.set, {this.hint = ''});
  final String Function() get;
  final void Function(String) set;
  final String hint;
}

class ActionItem extends SettingItem {
  const ActionItem(super.title, super.subtitle, this.run, {this.danger = false});
  final Future<void> Function(BuildContext) run;
  final bool danger;
}

class PageItem extends SettingItem {
  const PageItem(super.title, super.subtitle, this.page);
  final Widget Function() page;
}

class InfoItem extends SettingItem {
  const InfoItem(super.title, super.subtitle);
}

class SettingsCategory {
  const SettingsCategory(this.title, this.subtitle, this.icon, this.items);
  final String title;
  final String subtitle;
  final IconData icon;
  final List<SettingItem> items;
}

// ---- the settings themselves ----------------------------------------------------

String _speedLabel(double s) => '$s×';
String _secs(int s) => '$s s';
String _mins(int m) => m < 60 ? '$m min' : '${m ~/ 60} h';

Map<String, int> _ints(List<int> values, String Function(int) label, {String? zero}) =>
    {for (final v in values) (v == 0 && zero != null) ? zero : label(v): v};

/// Every setting in the app, grouped. The same list drives the phone, e-ink and desktop screens.
List<SettingsCategory> settingsCategories(Library lib, {required bool android}) {
  ToggleItem tog(String key, String title, String sub) =>
      ToggleItem(title, sub, () => lib.settings[key] as bool, (v) => lib.setSetting(key, v));

  ChoiceItem choice<T extends Object>(String key, String title, String sub, Map<String, T> options) =>
      ChoiceItem.typed(title, sub, () => lib.settings[key] as T, (v) => lib.setSetting(key, v as T), options);

  ChoiceItem custom<T extends Object>(String title, String sub, T Function() get, void Function(T) set, Map<String, T> options) =>
      ChoiceItem.typed(title, sub, get, (v) => set(v as T), options);

  return [
    SettingsCategory('Appearance', 'Theme, colours, text size', Icons.palette_outlined, [
      choice<String>('themeMode', 'Theme', 'Follow the system, or always light or dark', {'Follow system': 'system', 'Light': 'light', 'Dark': 'dark'}),
      choice<int>('accent', 'Accent colour', 'Used for buttons and highlights', {
        'Blue': 0xFF2196F3,
        'Teal': 0xFF009688,
        'Green': 0xFF4CAF50,
        'Orange': 0xFFFF9800,
        'Red': 0xFFF44336,
        'Purple': 0xFF9C27B0,
        'Pink': 0xFFE91E63,
        'Slate': 0xFF607D8B,
      }),
      choice<double>('textScale', 'Text size', 'Scales all text in the app', {'Small': 0.85, 'Default': 1.0, 'Large': 1.15, 'Larger': 1.3, 'Largest': 1.5}),
      tog('compact', 'Compact layout', 'Tighter spacing so more fits on screen'),
      tog('showArtwork', 'Show artwork', 'Turn off to save data and keep lists plain'),
      choice<String>('dateStyle', 'Date format', 'How release dates are written', {'Nov 4, 2026': 'mdy', '4 Nov 2026': 'dmy', '2026-11-04': 'iso'}),
    ]),
    SettingsCategory('Playback', 'Speed, skipping, queue behaviour', Icons.play_circle_outline, [
      custom<double>(
        'Default speed',
        'Podcasts can override this in their own settings',
        () => lib.speed,
        (v) => lib.setPrefs(speed: v),
        {for (final s in [0.5, 0.75, 0.8, 0.9, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]) _speedLabel(s): s},
      ),
      custom<int>('Skip back', 'Length of the back button', () => lib.skipBackSec, (v) => lib.setPrefs(skipBackSec: v), _ints([5, 10, 15, 20, 30, 45, 60], _secs)),
      custom<int>('Skip forward', 'Length of the forward button', () => lib.skipForwardSec, (v) => lib.setPrefs(skipForwardSec: v), _ints([10, 15, 30, 45, 60, 90], _secs)),
      choice<int>('smartRewindSec', 'Smart rewind', 'After a pause of 30 s or more, step back when you resume', _ints([0, 3, 5, 10, 15, 30], _secs, zero: 'Off')),
      tog('continueQueue', 'Play next in queue', 'Start the next episode when one finishes'),
      tog('removePlayedFromQueue', 'Remove finished episodes from queue', 'Take an episode off the queue when it ends'),
      choice<int>('autoPlayedRemainingSec', 'Mark as played early', 'Count an episode as played when this much is left (it keeps playing)', _ints([0, 10, 30, 60, 120], _secs, zero: 'Only at the end')),
      if (android) tog('skipSilence', 'Skip silence', 'Shorten quiet gaps while playing (Android only)'),
    ]),
    SettingsCategory('Library and feeds', 'Refreshing, sorting, new episodes', Icons.rss_feed, [
      tog('refreshOnLaunch', 'Refresh when the app starts', 'Check every podcast for new episodes on launch'),
      choice<int>('refreshIntervalMin', 'Refresh while open', 'Check for new episodes on a timer', _ints([0, 15, 30, 60, 120, 360], _mins, zero: 'Never')),
      choice<int>('newEpisodesAction', 'New episodes', 'What to do when a new episode appears (podcasts can override)', {'Do nothing': 0, 'Add to end of queue': 1, 'Add to front of queue': 2}),
      choice<bool>('sortOldestFirst', 'Episode order', 'Order of episode lists', {'Newest first': false, 'Oldest first': true}),
      tog('hidePlayed', 'Hide played episodes', 'In podcast pages'),
      choice<int>('maxEpisodesPerFeed', 'Episodes to keep per podcast', 'Older ones are dropped unless played, queued or favorited', _ints([0, 25, 50, 100, 200, 500], (v) => '$v', zero: 'All')),
      choice<int>('requestTimeoutSec', 'Network timeout', 'How long to wait for a server', _ints([10, 15, 30, 60, 120], _secs)),
      TextItem('User agent', 'Sent with feed and sync requests', () => lib.settings.userAgent, (v) => lib.setSetting('userAgent', v.trim()), hint: 'PodSync/0.1'),
    ]),
    SettingsCategory('Sync', 'Accounts and when to sync', Icons.sync, [
      PageItem('PodSync server', lib.signedIn ? 'Signed in as ${lib.username}' : 'Syncs everything: progress, queue, favorites, settings', () => const _AccountPage('PodSync server', AccountSection.podsync)),
      PageItem('gPodder', lib.gpodderEnabled ? 'Connected as ${lib.gUser}' : 'Subscriptions and progress, shared with other apps', () => const _AccountPage('gPodder', AccountSection.gpodder)),
      tog('syncOnStart', 'Sync when the app starts', ''),
      tog('syncOnPause', 'Sync when pausing or finishing', 'Keeps other devices close behind'),
      choice<int>('syncIntervalMin', 'Sync while open', 'Also sync on a timer', _ints([0, 5, 15, 30, 60], _mins, zero: 'Never')),
      ActionItem('Sync now', lib.syncEnabled ? '' : 'Sign in to a sync service first', (c) async {
        if (lib.syncEnabled) await lib.sync();
        if (c.mounted) showSnack(c, lib.syncError ?? (lib.syncEnabled ? 'Synced' : 'Nothing to sync with'));
      }),
    ]),
    SettingsCategory('Podcasts', 'Settings for each subscription', Icons.podcasts, [
      if (lib.subscriptions.isEmpty) const InfoItem('No subscriptions yet', 'Subscribe to a podcast to change its speed, skipping and name'),
      for (final p in lib.subscriptions)
        ActionItem(p.displayTitle, [
          if (p.speed != null) 'Speed ${p.speed}×',
          if (p.skipIntroSec > 0) 'Skip intro ${p.skipIntroSec} s',
          if (p.skipEndingSec > 0) 'Skip ending ${p.skipEndingSec} s',
          if (p.customTitle.isNotEmpty) 'Renamed',
          if (p.tags.isNotEmpty) p.tags.join(', '),
        ].join(' · '), (c) => showPodcastSettings(c, p.feedUrl)),
    ]),
    SettingsCategory('Import and backup', 'AntennaPod, OPML, library backup', Icons.import_export, [
      PageItem('Import', 'From an AntennaPod backup or an OPML file', () => const _AccountPage('Import', AccountSection.data)),
      ActionItem('Back up library', 'Save subscriptions, progress, queue, favorites and settings to a file', (c) async {
        final bytes = Uint8List.fromList(utf8.encode(lib.exportBackup()));
        final saved = await FilePicker.saveFile(fileName: 'podsync-backup.json', bytes: bytes, mimeType: 'application/json');
        if (saved != null && c.mounted) showSnack(c, 'Backup saved');
      }),
      ActionItem('Restore library', 'Replace the library with a PodSync backup file', (c) async {
        final file = await pickTempFile();
        if (file == null || !c.mounted) return;
        if (!await _confirm(c, 'Restore library?', 'This replaces your current podcasts, progress, queue and settings with the backup. Sign-ins stay.', 'Restore')) {
          await file.delete();
          return;
        }
        try {
          lib.restoreBackup(await file.readAsString());
          if (c.mounted) showSnack(c, 'Library restored');
        } on FormatException catch (e) {
          if (c.mounted) showSnack(c, e.message);
        } finally {
          await file.delete();
        }
      }),
    ]),
    if (android)
      SettingsCategory('E-ink', 'Paged display for e-paper screens', Icons.menu_book_outlined, [
        ToggleItem('E-ink mode', 'Black and white, paged lists, no scrolling or animation', () => lib.einkMode, lib.setEink),
        choice<int>('einkRowHeight', 'Row size', 'Bigger rows mean fewer per page', {'Compact': 72, 'Normal': 88, 'Large': 112, 'Extra large': 136}),
        choice<int>('einkClockSec', 'Redraw playback clock', 'How often the time updates while playing; slower means less ghosting', _ints([5, 15, 30, 60, 120], _secs)),
        tog('einkGrayArt', 'Grayscale artwork', 'Convert covers to grayscale'),
        tog('einkSwipe', 'Swipe to turn pages', 'In addition to the Prev and Next buttons'),
      ])
    else
      SettingsCategory('Desktop layout', 'Sidebar and table', Icons.view_sidebar_outlined, [
        choice<double>('sidebarWidth', 'Sidebar width', '', {'Narrow': 160.0, 'Normal': 200.0, 'Wide': 240.0, 'Wider': 280.0}),
        choice<int>('tableRowHeight', 'Table row height', '', {'Compact': 20, 'Normal': 22, 'Comfortable': 26, 'Large': 32}),
        tog('colTime', 'Show Time column', ''),
        tog('colPodcast', 'Show Podcast column', ''),
        tog('colDate', 'Show Release Date column', ''),
      ]),
    SettingsCategory('Advanced and about', 'Reset, data location', Icons.info_outline, [
      InfoItem('Version', 'PodSync 0.1.0'),
      InfoItem('Library', '${lib.subscriptions.length} podcasts, ${lib.episodes.length} episodes'),
      if (lib.dataPath.isNotEmpty) InfoItem('Data file', lib.dataPath),
      ActionItem('Refresh all podcasts now', '', (c) async {
        await lib.refreshAll();
        if (c.mounted) showSnack(c, 'Refreshed');
      }),
      ActionItem('Reset all settings', 'Put every setting above back to its default', (c) async {
        if (await _confirm(c, 'Reset all settings?', 'Your podcasts and progress are not touched.', 'Reset')) lib.resetSettings();
      }, danger: true),
      ActionItem('Delete all local data', 'Removes podcasts, progress, queue and sign-ins from this device. Servers keep their copy.', (c) async {
        if (await _confirm(c, 'Delete all local data?', 'This cannot be undone on this device. If you are signed in to a sync service, sign in again to get your data back.', 'Delete')) {
          await lib.wipeAll();
        }
      }, danger: true),
    ]),
  ];
}

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

class _AccountPage extends StatelessWidget {
  const _AccountPage(this.title, this.section);
  final String title;
  final AccountSection section;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: SafeArea(child: AccountPanel(only: section)));
}

// ---- rendering ------------------------------------------------------------------

/// Settings on a phone or e-ink screen: a list of groups, each opening its own page.
class SettingsHome extends StatelessWidget {
  const SettingsHome({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final cats = settingsCategories(lib, android: Platform.isAndroid);
    final eink = lib.einkMode;
    Widget row(BuildContext c, SettingsCategory cat) => InkWell(
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SettingsPage(cat.title))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(cat.icon, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cat.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(cat.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        );
    if (eink) return PagedList<SettingsCategory>(items: cats, itemExtent: 92, itemBuilder: row);
    return ListView(children: [for (final c in cats) SizedBox(height: 72, child: row(context, c))]);
  }
}

/// One group of settings as a full page (phone and e-ink).
class SettingsPage extends StatelessWidget {
  const SettingsPage(this.categoryTitle, {super.key});
  final String categoryTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(categoryTitle)),
        body: SafeArea(child: SettingsItems(categoryTitle)),
      );
}

/// The rows of one settings group. Paged on e-ink, scrolling otherwise.
class SettingsItems extends StatelessWidget {
  const SettingsItems(this.categoryTitle, {super.key});
  final String categoryTitle;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final cat = settingsCategories(lib, android: Platform.isAndroid).firstWhere((c) => c.title == categoryTitle);
    if (lib.einkMode) {
      return PagedList<SettingItem>(items: cat.items, itemExtent: 96 * lib.settings.einkRowHeight / 88, itemBuilder: (c, i) => SettingRow(i, fixed: true));
    }
    return ListView(children: [for (final i in cat.items) SettingRow(i)]);
  }
}

/// Settings on the desktop: group list on the left, the selected group on the right.
class SettingsPane extends StatefulWidget {
  const SettingsPane({super.key});

  @override
  State<SettingsPane> createState() => _SettingsPaneState();
}

class _SettingsPaneState extends State<SettingsPane> {
  String selected = 'Appearance';

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final cats = settingsCategories(lib, android: Platform.isAndroid);
    if (!cats.any((c) => c.title == selected)) selected = cats.first.title;
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      SizedBox(
        width: 220,
        child: ListView(children: [
          for (final c in cats)
            ListTile(
              dense: true,
              leading: Icon(c.icon, size: 20),
              title: Text(c.title),
              selected: c.title == selected,
              selectedTileColor: scheme.primary.withValues(alpha: 0.12),
              onTap: () => setState(() => selected = c.title),
            ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: SettingsItems(selected)),
        ),
      ),
    ]);
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow(this.item, {super.key, this.fixed = false});
  final SettingItem item;
  final bool fixed; // fixed-height row (e-ink pages): clip long text instead of growing

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    Widget tile({Widget? trailing, VoidCallback? onTap, Color? titleColor, String? value}) {
      final sub = item.subtitle;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, maxLines: fixed ? 1 : null, overflow: fixed ? TextOverflow.ellipsis : null, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: titleColor)),
                if (sub.isNotEmpty) Text(sub, maxLines: fixed ? 2 : null, overflow: fixed ? TextOverflow.ellipsis : null, style: TextStyle(fontSize: 13, color: muted)),
              ]),
            ),
            if (value != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
          ]),
        ),
      );
    }

    switch (item) {
      case ToggleItem():
        final on = item.get();
        return tile(onTap: () => item.set(!on), trailing: Switch(value: on, onChanged: item.set));
      case ChoiceItem():
        return _choiceTile(context, item, tile);
      case TextItem():
        final v = item.get();
        return tile(value: v.isEmpty ? 'Default' : v, onTap: () => _editText(context, item));
      case ActionItem():
        return tile(titleColor: item.danger ? Theme.of(context).colorScheme.error : null, onTap: () => item.run(context));
      case PageItem():
        return tile(trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.page())));
      case InfoItem():
        return tile();
    }
  }

  Widget _choiceTile(BuildContext context, ChoiceItem item, Widget Function({Widget? trailing, VoidCallback? onTap, Color? titleColor, String? value}) tile) {
    final current = item.get();
    final options = Map<String, Object>.of(item.options);
    // A value that is not in the list (e.g. from a synced device) still shows and stays selectable.
    if (!options.containsValue(current)) options['$current'] = current;
    final label = options.entries.firstWhere((e) => e.value == current).key;
    return tile(
      value: label,
      onTap: () => showDialog<void>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(item.title),
          children: [
            SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final e in options.entries)
                    ListTile(
                      dense: true,
                      title: Text(e.key),
                      trailing: e.value == current ? const Icon(Icons.check) : null,
                      onTap: () {
                        item.set(e.value);
                        Navigator.pop(c);
                      },
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editText(BuildContext context, TextItem item) async {
    final controller = TextEditingController(text: item.get());
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(item.title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: item.hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Use default')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) item.set(result);
  }
}
