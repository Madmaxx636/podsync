import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';

/// Per-podcast settings: display name, playback speed and skipping. Synced.
Future<void> showPodcastSettings(BuildContext context, String feedUrl) {
  return showDialog<void>(context: context, builder: (_) => _PodcastSettings(feedUrl));
}

class _PodcastSettings extends StatefulWidget {
  const _PodcastSettings(this.feedUrl);
  final String feedUrl;

  @override
  State<_PodcastSettings> createState() => _PodcastSettingsState();
}

class _PodcastSettingsState extends State<_PodcastSettings> {
  late final TextEditingController name;
  double? speed; // null = use the global speed
  late int intro;
  late int ending;
  late int newAction; // AntennaPod codes: 0 default, 3 nothing, 2 add to queue

  static const _speeds = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0];
  static const _skips = [0, 5, 10, 15, 30, 45, 60, 90];

  @override
  void initState() {
    super.initState();
    final p = context.read<Library>().podcasts[widget.feedUrl]!;
    name = TextEditingController(text: p.customTitle);
    speed = p.speed;
    intro = p.skipIntroSec;
    ending = p.skipEndingSec;
    newAction = (p.extra['newEpisodesAction'] as int?) ?? 0;
    if (newAction == 1) newAction = 3; // AntennaPod's "inbox" has no equivalent here, so it means nothing
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Widget _row(String label, Widget control) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), control]);

  @override
  Widget build(BuildContext context) {
    final lib = context.read<Library>();
    final p = lib.podcasts[widget.feedUrl]!;
    return AlertDialog(
      title: const Text('Podcast settings'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: 'Custom name', hintText: p.title)),
          const SizedBox(height: 12),
          _row(
            'Playback speed',
            DropdownButton<double?>(
              value: speed,
              items: [
                const DropdownMenuItem(value: null, child: Text('Default')),
                for (final s in {..._speeds, ?speed}.toList()..sort()) DropdownMenuItem(value: s, child: Text('$s×')),
              ],
              onChanged: (v) => setState(() => speed = v),
            ),
          ),
          _row(
            'Skip intro',
            DropdownButton<int>(
              value: intro,
              items: [for (final s in {..._skips, intro}.toList()..sort()) DropdownMenuItem(value: s, child: Text(s == 0 ? 'Off' : '$s s'))],
              onChanged: (v) => setState(() => intro = v!),
            ),
          ),
          _row(
            'Skip ending',
            DropdownButton<int>(
              value: ending,
              items: [for (final s in {..._skips, ending}.toList()..sort()) DropdownMenuItem(value: s, child: Text(s == 0 ? 'Off' : '$s s'))],
              onChanged: (v) => setState(() => ending = v!),
            ),
          ),
          _row(
            'New episodes',
            DropdownButton<int>(
              value: newAction,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Default')),
                DropdownMenuItem(value: 3, child: Text('Do nothing')),
                DropdownMenuItem(value: 2, child: Text('Add to queue')),
              ],
              onChanged: (v) => setState(() => newAction = v!),
            ),
          ),
          if (p.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Tags: ${p.tags.join(', ')}')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            lib.updatePodcastSettings(
              widget.feedUrl,
              customTitle: name.text.trim(),
              speed: speed,
              clearSpeed: speed == null,
              skipIntroSec: intro,
              skipEndingSec: ending,
              newEpisodesAction: newAction,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
