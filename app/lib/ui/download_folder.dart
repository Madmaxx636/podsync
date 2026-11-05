import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/library.dart';
import '../core/storage_access.dart';
import 'common.dart';

/// What the setting shows: "In PodSync (default)" or the end of the chosen path.
String downloadFolderLabel(String dir) {
  if (dir.isEmpty) return 'In PodSync (default)';
  final parts = p.split(dir).where((x) => x != p.separator).toList();
  return parts.length <= 2
      ? dir
      : '…/${parts.sublist(parts.length - 2).join('/')}';
}

/// Lets the person pick where downloads are saved. Android offers the places that always work
/// (the app, phone storage, an SD card) and "Choose a folder…" for anywhere else, asking for
/// All files access when that is needed. Desktop opens the system folder picker.
Future<void> chooseDownloadFolder(BuildContext context, Library lib) async {
  final current = lib.settings.downloadDir;

  Future<void> use(String dir) async {
    if (dir.isNotEmpty && !await canWriteTo(dir)) {
      if (context.mounted) {
        showSnack(
          context,
          'PodSync cannot save files in $dir. Pick another place.',
        );
      }
      return;
    }
    lib.setSetting('downloadDir', dir);
    if (context.mounted) {
      showSnack(
        context,
        dir.isEmpty
            ? 'Downloads go in PodSync\'s own folder'
            : 'Downloads will be saved in $dir',
      );
    }
  }

  Future<void> pickAny() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where to save downloads',
    );
    if (picked == null || picked.isEmpty) return;
    if (!picked.startsWith('/') &&
        !(Platform.isWindows && picked.contains(':'))) {
      if (context.mounted) {
        showSnack(
          context,
          'That location cannot be used. Choose a folder on phone storage or an SD card.',
        );
      }
      return;
    }
    if (Platform.isAndroid && !await canWriteTo(picked)) {
      // Anywhere outside the app's own storage needs "All files access".
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Allow access to files'),
          content: Text(
            'To save downloads in\n$picked\nAndroid needs you to allow PodSync to manage files. '
            'Tap Open settings, switch it on, then come back and choose the folder again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (go != true) return;
      await requestAllFilesAccess();
      // Back from the system page: finish the choice if the permission was given.
      final back = Completer<void>();
      final listener = AppLifecycleListener(
        onResume: () {
          if (!back.isCompleted) back.complete();
        },
      );
      await back.future.timeout(const Duration(minutes: 5), onTimeout: () {});
      listener.dispose();
      if (await canWriteTo(picked)) {
        await use(picked);
      } else if (context.mounted) {
        showSnack(
          context,
          'Access was not allowed, so the folder was not changed.',
        );
      }
      return;
    }
    await use(picked);
  }

  if (!Platform.isAndroid) {
    // Desktop: the system's own folder picker, with a way back to the default.
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Download folder'),
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Choose a folder…'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Use PodSync\'s own folder (default)'),
            trailing: current.isEmpty ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(c, 'default'),
          ),
        ],
      ),
    );
    if (choice == 'pick') await pickAny();
    if (choice == 'default') await use('');
    return;
  }

  // Android: places that always work, then "anywhere".
  final places =
      <(String, String, String)>[]; // label, detail, path ('' = default)
  places.add((
    'In PodSync',
    'Private to the app; removed if you uninstall it',
    '',
  ));
  try {
    final dirs = await getExternalStorageDirectories(
      type: StorageDirectory.podcasts,
    );
    if (dirs != null) {
      for (var i = 0; i < dirs.length; i++) {
        places.add((
          i == 0 ? 'Phone storage' : 'SD card',
          dirs[i].path,
          dirs[i].path,
        ));
      }
    }
  } catch (_) {}
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Save downloads in',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          for (final (label, detail, path) in places)
            ListTile(
              leading: Icon(
                path.isEmpty
                    ? Icons.phone_android
                    : (label == 'SD card'
                          ? Icons.sd_card
                          : Icons.folder_outlined),
              ),
              title: Text(label),
              subtitle: Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: path == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, 'use:$path'),
            ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Choose a folder…'),
            subtitle: const Text('Any folder on the phone or an SD card'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Episodes you already downloaded stay where they are.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return;
  if (choice == 'pick') {
    await pickAny();
  } else {
    await use(choice.substring(4));
  }
}
