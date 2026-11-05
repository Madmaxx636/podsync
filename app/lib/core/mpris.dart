import 'dart:ui' show VoidCallback;

import 'package:dbus/dbus.dart';

import 'library.dart';
import 'player.dart';

/// Linux media controls: publishes PodSync on the session bus as an MPRIS player, so the media
/// keys, the desktop's now-playing widget and `playerctl` can control it.
class MprisService extends DBusObject {
  MprisService({
    required this.player,
    required this.lib,
    required this.onRaise,
    required this.onQuit,
  }) : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final PlayerController player;
  final Library lib;
  final VoidCallback onRaise;
  final VoidCallback onQuit;

  DBusClient? _client;
  String _lastKey = '';
  static const _rootInterface = 'org.mpris.MediaPlayer2';
  static const _playerInterface = 'org.mpris.MediaPlayer2.Player';

  Future<void> start() async {
    final client = DBusClient.session();
    _client = client;
    await client.requestName(
      'org.mpris.MediaPlayer2.podsync',
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    await client.registerObject(this);
    player.addListener(_changed);
  }

  Future<void> stop() async {
    player.removeListener(_changed);
    await _client?.close();
    _client = null;
  }

  void _changed() {
    final key = '${player.current?.id}|${player.playing}';
    if (key == _lastKey) return;
    _lastKey = key;
    emitPropertiesChanged(_playerInterface, changedProperties: _playerProps());
  }

  Map<String, DBusValue> _rootProps() => {
    'CanQuit': DBusBoolean(true),
    'CanRaise': DBusBoolean(true),
    'HasTrackList': DBusBoolean(false),
    'Identity': DBusString('PodSync'),
    'DesktopEntry': DBusString('podsync'),
    'SupportedUriSchemes': DBusArray.string([]),
    'SupportedMimeTypes': DBusArray.string([]),
  };

  Map<String, DBusValue> _metadata() {
    final e = player.current;
    if (e == null) {
      return {
        'mpris:trackid': DBusObjectPath(
          '/org/mpris/MediaPlayer2/TrackList/NoTrack',
        ),
      };
    }
    final podcast = lib.podcastTitle(e.feedUrl);
    final length = player.duration.inMicroseconds;
    return {
      'mpris:trackid': DBusObjectPath(
        '/dev/podsync/track/${e.id.hashCode.abs()}',
      ),
      if (length > 0) 'mpris:length': DBusInt64(length),
      if (e.imageUrl.isNotEmpty) 'mpris:artUrl': DBusString(e.imageUrl),
      'xesam:title': DBusString(e.title),
      'xesam:artist': DBusArray.string([podcast]),
      'xesam:album': DBusString(podcast),
    };
  }

  Map<String, DBusValue> _playerProps() {
    final has = player.current != null;
    return {
      'PlaybackStatus': DBusString(
        !has ? 'Stopped' : (player.playing ? 'Playing' : 'Paused'),
      ),
      'LoopStatus': DBusString('None'),
      'Rate': DBusDouble(1.0),
      'Shuffle': DBusBoolean(false),
      'Metadata': DBusDict.stringVariant(_metadata()),
      'Volume': DBusDouble(lib.settings.volume),
      'Position': DBusInt64(player.position.inMicroseconds),
      'MinimumRate': DBusDouble(0.5),
      'MaximumRate': DBusDouble(3.0),
      'CanGoNext': DBusBoolean(true),
      'CanGoPrevious': DBusBoolean(true),
      'CanPlay': DBusBoolean(has),
      'CanPause': DBusBoolean(has),
      'CanSeek': DBusBoolean(has),
      'CanControl': DBusBoolean(true),
    };
  }

  Map<String, DBusValue>? _props(String interface) => switch (interface) {
    _rootInterface => _rootProps(),
    _playerInterface => _playerProps(),
    _ => null,
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final props = _props(interface);
    if (props == null) return DBusMethodErrorResponse.unknownInterface();
    final v = props[name];
    return v == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(v);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    final props = _props(interface);
    return props == null
        ? DBusMethodErrorResponse.unknownInterface()
        : DBusGetAllPropertiesResponse(props);
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface == _playerInterface && name == 'Volume') {
      player.setVolume(value.asDouble());
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.propertyReadOnly();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    final interface = methodCall.interface;
    if (interface == _rootInterface) {
      switch (methodCall.name) {
        case 'Raise':
          onRaise();
        case 'Quit':
          onQuit();
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
      return DBusMethodSuccessResponse();
    }
    if (interface == _playerInterface) {
      final has = player.current != null;
      switch (methodCall.name) {
        case 'Next':
          player.next();
        case 'Previous':
          player.skipBack();
        case 'Play':
          if (has && !player.playing) player.toggle();
        case 'Pause':
        case 'Stop':
          if (player.playing) player.toggle();
        case 'PlayPause':
          if (has) player.toggle();
        case 'Seek':
          player.seek(
            player.position +
                Duration(microseconds: methodCall.values[0].asInt64()),
          );
        case 'SetPosition':
          player.seek(Duration(microseconds: methodCall.values[1].asInt64()));
        case 'OpenUri':
          break;
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownInterface();
  }
}
