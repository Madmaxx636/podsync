import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/episode_view.dart';
import '../core/library.dart';
import 'common.dart';
import 'settings.dart';

/// Opens a podcast's own settings: a full page on the phone, a window on the desktop.
Future<void> showPodcastSettings(BuildContext context, String feedUrl) {
  if (Platform.isAndroid) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PodcastSettingsPage(feedUrl)),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        height: 680,
        child: PodcastSettingsPage(feedUrl),
      ),
    ),
  );
}

/// AntennaPod's "Podcast settings": playback, which episodes to show and how to sort them,
/// automation and the feed's login. Every change applies at once and syncs.
class PodcastSettingsPage extends StatelessWidget {
  const PodcastSettingsPage(this.feedUrl, {super.key});
  final String feedUrl;

  static const _speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
  static const _skips = [0, 5, 10, 15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final p = lib.podcasts[feedUrl];
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Podcast settings')),
        body: const Center(
          child: Text('This podcast is no longer in your library'),
        ),
      );
    }

    void update({
      String? customTitle,
      double? speed,
      bool clearSpeed = false,
      int? skipIntroSec,
      int? skipEndingSec,
      int? newEpisodesAction,
      Map<String, Object>? extra,
      List<String>? tags,
    }) => lib.updatePodcastSettings(
      feedUrl,
      customTitle: customTitle,
      speed: speed,
      clearSpeed: clearSpeed,
      skipIntroSec: skipIntroSec,
      skipEndingSec: skipEndingSec,
      newEpisodesAction: newEpisodesAction,
      extra: extra,
      tags: tags,
    );

    ChoiceItem choice<T extends Object>(
      String title,
      String sub,
      T Function() get,
      void Function(T) set,
      Map<String, T> options,
    ) => ChoiceItem.typed(title, sub, get, (v) => set(v as T), options);

    int extraInt(String key) => (p.extra[key] as int?) ?? 0;
    const followGlobal = {'Global default': 0, 'Always': 1, 'Never': 2};

    final items = <SettingItem>[
      const HeaderItem('General'),
      TextItem(
        'Custom name',
        'Shown instead of the name the feed gives itself',
        () => p.customTitle,
        (v) => update(customTitle: v.trim()),
        hint: p.title,
      ),
      TextItem(
        'Tags',
        'Separate with commas, to organise your subscriptions',
        () => p.tags.join(', '),
        (v) => update(
          tags: [
            for (final t in v.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
        ),
        empty: 'None',
      ),
      const HeaderItem('Episodes'),
      ActionItem(
        'Episode filter',
        EpisodeView.filterSummary(p),
        (c) => showEpisodeFilter(c, feedUrl),
      ),
      ActionItem(
        'Episode sort order',
        EpisodeView.sortLabel(EpisodeView.sortOf(p)),
        (c) => showEpisodeSort(c, feedUrl),
      ),
      const HeaderItem('Playback'),
      choice<double>(
        'Playback speed',
        'The speed to use when starting episodes of this podcast',
        () => p.speed ?? 0.0,
        (v) => v == 0.0 ? update(clearSpeed: true) : update(speed: v),
        {
          'Global default': 0.0,
          for (final s in {..._speeds, ?p.speed}.toList()..sort()) '$s×': s,
        },
      ),
      choice<int>(
        'Skip intro',
        'Jump past the start when an episode begins',
        () => p.skipIntroSec,
        (v) => update(skipIntroSec: v),
        {
          for (final s in {..._skips, p.skipIntroSec}.toList()..sort())
            s == 0 ? 'Off' : '$s s': s,
        },
      ),
      choice<int>(
        'Skip ending',
        'Move on this long before an episode ends',
        () => p.skipEndingSec,
        (v) => update(skipEndingSec: v),
        {
          for (final s in {..._skips, p.skipEndingSec}.toList()..sort())
            s == 0 ? 'Off' : '$s s': s,
        },
      ),
      const HeaderItem('Automation'),
      ToggleItem(
        'Keep updated',
        'Include this podcast when refreshing all podcasts',
        () => p.extra['keepUpdated'] != false && p.extra['keepUpdated'] != 0,
        (v) => update(extra: {'keepUpdated': v}),
      ),
      choice<int>(
        'Episode notifications',
        'A notification when a new episode comes out (desktop)',
        () => extraInt('notifyNew'),
        (v) => update(extra: {'notifyNew': v}),
        {'Global default': 0, 'On': 1, 'Off': 2},
      ),
      choice<int>(
        'Delete after playing',
        'Remove the downloaded file once an episode is played',
        () => extraInt('autoDeleteAction'),
        (v) => update(extra: {'autoDeleteAction': v}),
        followGlobal,
      ),
      choice<int>(
        'New episodes action',
        'What happens to new episodes of this podcast',
        () => switch (p.extra['newEpisodesAction']) {
          2 => 2,
          1 || 3 => 3,
          _ => 0,
        },
        (v) => update(newEpisodesAction: v),
        {'Global default': 0, 'Do nothing': 3, 'Add to queue': 2},
      ),
      choice<int>(
        'Include in auto downloads',
        'Download new episodes of this podcast automatically',
        () => extraInt('autoDownloadNew'),
        (v) => update(extra: {'autoDownloadNew': v}),
        followGlobal,
      ),
      const HeaderItem('Advanced'),
      ActionItem(
        'Authentication',
        p.username.isEmpty
            ? 'Sign-in for password-protected feeds'
            : 'Signed in as ${p.username}',
        (c) => _askLogin(c, lib, p.feedUrl, p.username, p.password),
      ),
      ActionItem('Copy feed address', p.feedUrl, (c) async {
        await Clipboard.setData(ClipboardData(text: p.feedUrl));
        if (c.mounted) showSnack(c, 'Feed address copied');
      }),
      ActionItem('Unsubscribe', 'Remove this podcast from your library', (
        c,
      ) async {
        final ok = await showDialog<bool>(
          context: c,
          builder: (d) => AlertDialog(
            title: const Text('Unsubscribe?'),
            content: Text('Remove ${p.displayTitle} from your library.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Unsubscribe'),
              ),
            ],
          ),
        );
        if (ok == true) {
          lib.unsubscribe(feedUrl);
          if (c.mounted) Navigator.pop(c);
        }
      }, danger: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Podcast settings', style: TextStyle(fontSize: 20)),
            Text(
              p.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: SafeArea(child: SettingItemsView(items)),
    );
  }

  Future<void> _askLogin(
    BuildContext context,
    Library lib,
    String feedUrl,
    String user,
    String pass,
  ) async {
    final u = TextEditingController(text: user);
    final w = TextEditingController(text: pass);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: u,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: w,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      lib.updatePodcastSettings(
        feedUrl,
        username: u.text.trim(),
        password: w.text,
      );
    }
    u.dispose();
    w.dispose();
  }
}

// ---- episode filter and sort ----------------------------------------------------------

/// A two-column button: filled when chosen. On e-ink the chosen one is inverted instead.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
    this.label,
    this.selected,
    this.onTap, {
    required this.eink,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool eink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? (eink ? Colors.black : cs.primaryContainer)
        : (eink ? Colors.white : cs.surface);
    final fg = selected
        ? (eink ? Colors.white : cs.onPrimaryContainer)
        : (eink ? Colors.black : cs.onSurface);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(
            width: eink ? 2 : 1,
            color: eink ? Colors.black : cs.outlineVariant,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which episodes of this podcast to show, as pairs of choices; Confirm applies them.
Future<void> showEpisodeFilter(BuildContext context, String feedUrl) {
  final lib = context.read<Library>();
  final p = lib.podcasts[feedUrl];
  if (p == null) return Future.value();
  final working = Map<String, bool>.of(EpisodeView.filterOf(p));
  final eink = lib.einkMode;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, yes, no) in EpisodeView.filterPairs)
                Row(
                  children: [
                    for (final (label, value) in [(yes, true), (no, false)])
                      Expanded(
                        child: _ChoiceButton(
                          label,
                          working[key] == value,
                          () => setState(() {
                            if (working[key] == value) {
                              working.remove(key);
                            } else {
                              working[key] = value;
                            }
                          }),
                          eink: eink,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        lib.updatePodcastSettings(
                          feedUrl,
                          extra: {'epFilter': <String, Object>{}},
                        );
                        Navigator.pop(c);
                      },
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        lib.updatePodcastSettings(
                          feedUrl,
                          extra: {'epFilter': Map<String, Object>.of(working)},
                        );
                        Navigator.pop(c);
                      },
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// How to sort this podcast's episodes. Tapping the chosen one again flips its direction.
Future<void> showEpisodeSort(BuildContext context, String feedUrl) {
  final lib = context.read<Library>();
  final eink = lib.einkMode;
  return showModalBottomSheet<void>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) => Consumer<Library>(
      builder: (c, lib, _) {
        final sort = lib.podcasts[feedUrl]?.extra['epSort'] as String? ?? '';
        String arrow(String key) =>
            sort == '${key}Asc' ? ' ▲' : (sort == '${key}Desc' ? ' ▼' : '');
        void pick(String key) {
          // Date opens newest first, the others A to Z / shortest first.
          final next = sort == '${key}Asc'
              ? '${key}Desc'
              : (sort == '${key}Desc'
                    ? '${key}Asc'
                    : (key == 'date' ? 'dateDesc' : '${key}Asc'));
          lib.updatePodcastSettings(feedUrl, extra: {'epSort': next});
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        'Episode title${arrow('title')}',
                        sort.startsWith('title'),
                        () => pick('title'),
                        eink: eink,
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        'Duration${arrow('duration')}',
                        sort.startsWith('duration'),
                        () => pick('duration'),
                        eink: eink,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        'Date${arrow('date')}',
                        sort.startsWith('date'),
                        () => pick('date'),
                        eink: eink,
                      ),
                    ),
                    Expanded(
                      child: _ChoiceButton(
                        'Global default',
                        sort.isEmpty,
                        () => lib.updatePodcastSettings(
                          feedUrl,
                          extra: {'epSort': ''},
                        ),
                        eink: eink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
