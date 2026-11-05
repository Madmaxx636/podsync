import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/library.dart';
import '../core/updater.dart';

/// Wraps the home screen: checks for a new release when the app opens (and once a day while
/// it stays open) and offers it in a dialog.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  Timer? _daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run(startup: true));
    _daily = Timer.periodic(const Duration(hours: 24), (_) => _run());
  }

  @override
  void dispose() {
    _daily?.cancel();
    super.dispose();
  }

  Future<void> _run({bool startup = false}) async {
    if (!mounted) return;
    final up = context.read<UpdateController>();
    final lib = context.read<Library>();
    await up.init();
    if (!lib.settings.updateCheck) return;
    await up.check();
    if (!mounted || !up.takeOffer()) return;
    // Only at start-up, so an update never restarts the app in the middle of listening.
    if (startup &&
        lib.settings.updateAuto &&
        !Platform.isAndroid &&
        up.canInstall) {
      await up.install();
      if (up.error == null) return; // the app restarts itself
    }
    if (mounted) await showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showUpdateDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _UpdateDialog(),
);

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UpdateController>();
    final a = up.available;
    if (a == null) return const SizedBox.shrink();
    final notes = a.notes.length > 500
        ? '${a.notes.substring(0, 500)}…'
        : a.notes;
    return AlertDialog(
      title: Text('PodSync ${a.version} is available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You have ${up.current}.'),
          if (notes.isNotEmpty) ...[const SizedBox(height: 12), Text(notes)],
          if (!up.canInstall) ...[
            const SizedBox(height: 12),
            const Text(
              'Download it from the releases page and install it over this one.',
            ),
          ],
          if (up.downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: up.progress == 0 ? null : up.progress,
            ),
            const SizedBox(height: 4),
            Text(
              up.progress == null || up.progress == 0
                  ? 'Starting…'
                  : 'Downloading ${(up.progress! * 100).round()}%',
            ),
          ],
          if (up.error != null) ...[
            const SizedBox(height: 12),
            Text(
              up.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (!up.downloading) ...[
          TextButton(
            onPressed: () {
              up.skipThisVersion();
              Navigator.pop(context);
            },
            child: const Text('Skip this version'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          if (up.canInstall)
            FilledButton(
              onPressed: () async {
                await up.install();
                if (context.mounted && up.error == null) Navigator.pop(context);
              },
              child: const Text('Install'),
            )
          else
            FilledButton(
              onPressed: () => openReleasePage(a.pageUrl),
              child: const Text('Open releases page'),
            ),
        ],
      ],
    );
  }
}

/// Opens a web page with the system browser (Linux, Windows) – used where an update cannot
/// be installed by the app.
void openReleasePage(String url) {
  if (Platform.isLinux) {
    Process.run('xdg-open', [url]);
  } else if (Platform.isWindows) {
    Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  }
}
