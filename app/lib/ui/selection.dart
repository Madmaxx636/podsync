import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../core/downloads.dart';
import '../core/library.dart';

/// The episodes picked on a phone (long-press an episode, then tap more). One selection for the
/// whole app, so it survives going from the queue into a podcast.
class EpisodeSelection extends ChangeNotifier {
  EpisodeSelection._();
  static final instance = EpisodeSelection._();

  final Set<String> ids = {};
  bool get active => ids.isNotEmpty;
  bool has(String id) => ids.contains(id);

  void toggle(String id) {
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    notifyListeners();
  }

  void add(String id) {
    if (ids.add(id)) notifyListeners();
  }

  void clear() {
    if (ids.isEmpty) return;
    ids.clear();
    notifyListeners();
  }
}

/// The action row shown at the bottom while episodes are selected: the same things the
/// long-press list offers, applied to all of them.
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: EpisodeSelection.instance,
    builder: (context, _) {
      final sel = EpisodeSelection.instance;
      if (!sel.active) return const SizedBox.shrink();
      final lib = context.watch<Library>();
      final dm = context.watch<DownloadManager>();
      final ids = sel.ids.where(lib.episodes.containsKey).toList();
      final eps = [for (final id in ids) lib.episodes[id]!];
      final allQueued = ids.every(lib.queue.contains);
      final allPlayed = ids.every((id) => lib.progressOf(id).played);
      final allFav = ids.every(lib.isFavorite);
      final allDownloaded = ids.every(dm.isDownloaded);
      final eink = lib.einkMode;

      void after(VoidCallback run) {
        run();
        sel.clear();
      }

      Widget act(IconData icon, String label, VoidCallback run) => Expanded(
        child: InkWell(
          onTap: () => after(run),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      void more() => showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: context.read<Library>().einkMode
            ? AnimationStyle.noAnimation
            : null,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Play next'),
                onTap: () {
                  Navigator.pop(c);
                  after(() => lib.enqueueAll(ids, next: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.vertical_align_top),
                title: const Text('Move to top of the queue'),
                enabled: ids.any(lib.queue.contains),
                onTap: () {
                  Navigator.pop(c);
                  after(() => lib.moveInQueue(ids, toTop: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('Move to bottom of the queue'),
                enabled: ids.any(lib.queue.contains),
                onTap: () {
                  Navigator.pop(c);
                  after(() => lib.moveInQueue(ids, toTop: false));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove downloads'),
                enabled: ids.any(dm.isDownloaded),
                onTap: () {
                  Navigator.pop(c);
                  after(() {
                    for (final id in ids.where(dm.isDownloaded)) {
                      dm.delete(id);
                    }
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.select_all),
                title: const Text('Clear selection'),
                onTap: () {
                  Navigator.pop(c);
                  sel.clear();
                },
              ),
            ],
          ),
        ),
      );

      return Material(
        color: eink
            ? Colors.white
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        elevation: eink ? 0 : 8,
        child: Container(
          decoration: eink
              ? const BoxDecoration(border: Border(top: BorderSide(width: 2)))
              : null,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                act(
                  allQueued ? Icons.remove_from_queue : Icons.add_to_queue,
                  allQueued ? 'Unqueue' : 'Queue',
                  () {
                    if (allQueued) {
                      lib.removeAllFromQueue(ids);
                    } else {
                      lib.enqueueAll(
                        ids.where((id) => !lib.queue.contains(id)).toList(),
                      );
                    }
                  },
                ),
                act(
                  allDownloaded ? Icons.delete_outline : Icons.download,
                  allDownloaded ? 'Remove' : 'Download',
                  () {
                    if (allDownloaded) {
                      for (final id in ids) {
                        dm.delete(id);
                      }
                    } else {
                      dm.downloadAll(eps);
                    }
                  },
                ),
                act(
                  allPlayed ? Icons.visibility_off : Icons.check,
                  allPlayed ? 'Unplayed' : 'Played',
                  () => lib.markAllPlayed(ids, !allPlayed),
                ),
                act(
                  allFav ? Icons.star : Icons.star_border,
                  allFav ? 'Unfavorite' : 'Favorite',
                  () => lib.setFavorites(ids, !allFav),
                ),
                Expanded(
                  child: InkWell(
                    onTap: more,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_vert, size: 24),
                          SizedBox(height: 2),
                          Text(
                            'More',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
