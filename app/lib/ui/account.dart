import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/antennapod_import.dart';
import '../core/library.dart';
import '../core/opml.dart';
import 'common.dart';

enum AccountSection { podsync, gpodder, data }

const _tabLabels = {
  AccountSection.podsync: 'PodSync',
  AccountSection.gpodder: 'gPodder',
  AccountSection.data: 'Import',
};

/// Sync accounts and import. Shared by the mobile, e-ink and desktop shells; pass
/// [only] to show a single section without the tab chips.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, this.only});
  final AccountSection? only;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  late AccountSection tab = widget.only ?? AccountSection.podsync;
  final server = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  final gServer = TextEditingController(text: 'https://gpodder.net');
  final gUser = TextEditingController();
  final gPass = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final lib = context.read<Library>();
    server.text = lib.serverUrl;
    if (lib.gServer.isNotEmpty) gServer.text = lib.gServer;
    gUser.text = lib.gUser;
  }

  @override
  void dispose() {
    for (final c in [server, user, pass, gServer, gUser, gPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _syncStatus(Library lib) {
    if (lib.syncError != null) return lib.syncError!;
    final t = lib.lastSync;
    if (t == null) return '';
    return 'Last sync ${fmtDate(t.millisecondsSinceEpoch)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showReport(String title, String text) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final Widget body = switch (tab) {
      AccountSection.podsync => _podsync(lib),
      AccountSection.gpodder => _gpodder(lib),
      AccountSection.data => _data(lib),
    };

    return Column(children: [
      if (widget.only == null) Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          for (final t in AccountSection.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: SizedBox(width: double.infinity, child: Text(_tabLabels[t]!, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                  showCheckmark: false,
                  selected: tab == t,
                  onSelected: (_) => setState(() => tab = t),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          // E-ink mode never scrolls, except to keep a field visible above the keyboard.
          physics: lib.einkMode && !keyboardOpen ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [body]),
        ),
      ),
    ]);
  }

  // ---- PodSync server ---------------------------------------------------------

  Widget _podsync(Library lib) {
    if (lib.signedIn) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Signed in as ${lib.username}', style: Theme.of(context).textTheme.titleMedium),
        Text(lib.serverUrl),
        const SizedBox(height: 4),
        Text(_syncStatus(lib)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, children: [
          FilledButton.icon(
            onPressed: lib.syncing ? null : lib.sync,
            icon: const Icon(Icons.sync),
            label: Text(lib.syncing ? 'Syncing…' : 'Sync now'),
          ),
          OutlinedButton(onPressed: lib.signOut, child: const Text('Sign out')),
        ]),
        const SizedBox(height: 16),
        const Text('Syncs everything: subscriptions, progress, queue, favorites and playback settings.'),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: server, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://sync.example.com')),
      TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')),
      TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)')),
      const SizedBox(height: 12),
      Wrap(spacing: 12, children: [
        FilledButton(
          onPressed: busy ? null : () => _run(() async {
            await lib.signIn(server.text, user.text, pass.text);
            pass.clear();
          }),
          child: const Text('Sign in'),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => _run(() async {
            await lib.signIn(server.text, user.text, pass.text, register: true);
            pass.clear();
          }),
          child: const Text('Create account'),
        ),
      ]),
    ]);
  }

  // ---- gPodder ----------------------------------------------------------------

  Widget _gpodder(Library lib) {
    const note = 'gPodder syncs subscriptions and listening progress, so it works with AntennaPod, gPodder and other apps '
        'on the same account. It has no queue or favorites; use the PodSync server for those.';
    if (lib.gpodderEnabled) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Connected as ${lib.gUser}', style: Theme.of(context).textTheme.titleMedium),
        Text(lib.gServer),
        const SizedBox(height: 4),
        Text(_syncStatus(lib)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, children: [
          FilledButton.icon(
            onPressed: lib.syncing ? null : lib.sync,
            icon: const Icon(Icons.sync),
            label: Text(lib.syncing ? 'Syncing…' : 'Sync now'),
          ),
          OutlinedButton(onPressed: lib.disconnectGpodder, child: const Text('Disconnect')),
        ]),
        const SizedBox(height: 16),
        const Text(note),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: gServer, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://gpodder.net')),
      TextField(controller: gUser, decoration: const InputDecoration(labelText: 'Username')),
      TextField(controller: gPass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy ? null : () => _run(() async {
          await lib.connectGpodder(gServer.text, gUser.text, gPass.text);
          gPass.clear();
        }),
        child: const Text('Connect'),
      ),
      const SizedBox(height: 16),
      const Text(note),
    ]);
  }

  // ---- import / export --------------------------------------------------------

  Widget _data(Library lib) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('From AntennaPod', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('In AntennaPod open Settings > Import/Export > Database export, then choose that .db file here. '
          'It brings in subscriptions with their settings, every episode, played state and positions, listening history, '
          'the queue, favorites and chapters. AntennaPod\'s app settings and downloaded audio are not part of its backup.'),
      const SizedBox(height: 8),
      FilledButton.icon(
        icon: const Icon(Icons.restore),
        label: const Text('Import AntennaPod backup'),
        onPressed: busy ? null : () => _run(() async {
          final file = await pickTempFile();
          if (file == null) return;
          try {
            final report = importAntennaPodBackup(lib, file.path);
            if (mounted) await _showReport('Imported', report.summary());
          } finally {
            await file.delete();
          }
        }),
      ),
      const Divider(height: 32),
      Text('OPML (subscriptions only)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: busy ? null : () => _run(() async {
            final file = await pickTempFile();
            if (file == null) return;
            final String xml;
            try {
              xml = await file.readAsString();
            } finally {
              await file.delete();
            }
            final n = importOpml(lib, xml);
            if (mounted) showSnack(context, 'Added $n podcasts');
            lib.refreshAll();
          }),
          child: const Text('Import OPML'),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => _run(() async {
            final xml = buildOpml(lib.subscriptions);
            final bytes = Uint8List.fromList(utf8.encode(xml));
            final saved = await FilePicker.saveFile(fileName: 'podsync-subscriptions.opml', bytes: bytes, mimeType: 'text/x-opml');
            if (saved != null && mounted) showSnack(context, 'Exported ${lib.subscriptions.length} podcasts');
          }),
          child: const Text('Export OPML'),
        ),
      ]),
    ]);
  }
}
