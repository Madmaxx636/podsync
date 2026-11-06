import 'package:flutter/material.dart';

import '../core/cast.dart';
import '../core/cast_net/device.dart';

/// The cast icon on the player screen: pick a TV or speaker, or see and stop what is casting.
/// Not shown where there is no [CastController] (everything but Android).
class CastButton extends StatelessWidget {
  const CastButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cast = CastController.instance;
    if (cast == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) => IconButton(
        tooltip: cast.connected ? 'Casting to ${cast.device!.name}' : 'Cast',
        icon: Icon(cast.connected ? Icons.cast_connected : Icons.cast),
        onPressed: () => showCastSheet(context, cast),
      ),
    );
  }
}

/// "Casting to Living Room TV" with a Stop button, shown under the episode while casting.
class CastStrip extends StatelessWidget {
  const CastStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final cast = CastController.instance;
    if (cast == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final text = cast.error ?? cast.status;
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cast_connected, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (cast.connected)
                TextButton(
                  onPressed: cast.stop,
                  child: const Text('Stop casting'),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> showCastSheet(BuildContext context, CastController cast) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: cast.connected
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.cast_connected),
                  title: Text('Casting to ${cast.device!.name}'),
                ),
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Play on this device instead'),
                  onTap: () {
                    Navigator.pop(c);
                    cast.stop();
                  },
                ),
              ],
            )
          : _DevicePicker(cast: cast),
    ),
  );
}

class _DevicePicker extends StatefulWidget {
  const _DevicePicker({required this.cast});
  final CastController cast;

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  late Future<List<CastDevice>> _devices = widget.cast.search();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CastDevice>>(
    future: _devices,
    builder: (context, snap) {
      final children = <Widget>[
        const ListTile(
          title: Text(
            'Cast to',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          subtitle: Text('TVs and speakers on this Wi-Fi network'),
        ),
      ];
      if (snap.connectionState != ConnectionState.done) {
        children.add(
          const ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Looking for devices…'),
          ),
        );
      } else if (snap.hasError || (snap.data ?? const []).isEmpty) {
        children.add(
          ListTile(
            leading: const Icon(Icons.search_off),
            title: const Text('No devices found'),
            subtitle: const Text(
              'Make sure the TV is on and on the same Wi-Fi as this phone.',
            ),
            trailing: TextButton(
              onPressed: () => setState(() => _devices = widget.cast.search()),
              child: const Text('Search again'),
            ),
          ),
        );
      } else {
        for (final d in snap.data!) {
          children.add(
            ListTile(
              leading: const Icon(Icons.tv),
              title: Text(d.name),
              onTap: () {
                Navigator.pop(context);
                widget.cast.start(d);
              },
            ),
          );
        }
      }
      return SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    },
  );
}
