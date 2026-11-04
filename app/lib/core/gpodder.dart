import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client for the gPodder v2 web API (gpodder.net, and self-hosted servers that
/// implement it such as opodsync or micro-gpodder-server).
/// Reference: https://gpoddernet.readthedocs.io/en/latest/api/reference/
class GpodderClient {
  GpodderClient({
    required String baseUrl,
    required this.username,
    required this.password,
    required this.deviceId,
    http.Client? client,
    this.userAgent = 'PodSync/0.1',
    this.timeout = const Duration(seconds: 30),
  })  : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final String deviceId;
  final String userAgent;
  final Duration timeout;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
      };

  String get _user => Uri.encodeComponent(username);

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Never _fail(http.Response r) {
    if (r.statusCode == 401) throw const GpodderException('Wrong username or password');
    if (r.statusCode == 404) throw const GpodderException('Not found, check the server address');
    throw GpodderException('gPodder server returned HTTP ${r.statusCode}');
  }

  Future<http.Response> _get(Uri u) => _http.get(u, headers: _headers).timeout(timeout);

  Future<http.Response> _post(Uri u, Object body) =>
      _http.post(u, headers: _headers, body: jsonEncode(body)).timeout(timeout * 2);

  /// Verifies the credentials.
  Future<void> login() async {
    final r = await _post(_uri('/api/2/auth/$_user/login.json'), {});
    if (r.statusCode != 200) _fail(r);
  }

  /// Creates this device on the server (or updates its name).
  Future<void> registerDevice(String caption, String type) async {
    final r = await _post(_uri('/api/2/devices/$_user/${Uri.encodeComponent(deviceId)}.json'), {'caption': caption, 'type': type});
    if (r.statusCode != 200) _fail(r);
  }

  Future<SubscriptionChanges> subscriptionChanges(int since) async {
    final r = await _get(_uri('/api/2/subscriptions/$_user/${Uri.encodeComponent(deviceId)}.json', {'since': '$since'}));
    if (r.statusCode != 200) _fail(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return SubscriptionChanges(
      List<String>.from(j['add'] ?? []),
      List<String>.from(j['remove'] ?? []),
      (j['timestamp'] as num?)?.toInt() ?? since,
    );
  }

  Future<int?> pushSubscriptions(List<String> add, List<String> remove) async {
    final r = await _post(
      _uri('/api/2/subscriptions/$_user/${Uri.encodeComponent(deviceId)}.json'),
      {'add': add, 'remove': remove},
    );
    if (r.statusCode != 200) _fail(r);
    return (jsonDecode(r.body)['timestamp'] as num?)?.toInt();
  }

  /// Latest action per episode since [since] (0 = everything).
  Future<EpisodeActions> episodeActions(int since) async {
    final r = await _get(_uri('/api/2/episodes/$_user.json', {'since': '$since', 'aggregated': 'true'}));
    if (r.statusCode != 200) _fail(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return EpisodeActions(
      [for (final a in (j['actions'] as List? ?? [])) Map<String, dynamic>.from(a)],
      (j['timestamp'] as num?)?.toInt() ?? since,
    );
  }

  Future<void> pushActions(List<Map<String, dynamic>> actions) async {
    final r = await _post(_uri('/api/2/episodes/$_user.json'), actions);
    if (r.statusCode != 200) _fail(r);
  }

  /// gPodder wants "2009-12-12T09:00:00" (UTC, no zone suffix).
  static String formatTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().split('.').first;

  /// Accepts ISO 8601 with or without a zone (no zone means UTC), or a unix timestamp.
  static int parseTime(Object? v) {
    if (v is num) return v > 100000000000 ? v.toInt() : (v * 1000).toInt();
    if (v is! String || v.isEmpty) return 0;
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(v);
    return DateTime.tryParse(hasZone ? v : '${v}Z')?.millisecondsSinceEpoch ?? 0;
  }
}

class GpodderException implements Exception {
  const GpodderException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SubscriptionChanges {
  SubscriptionChanges(this.add, this.remove, this.timestamp);
  final List<String> add;
  final List<String> remove;
  final int timestamp;
}

class EpisodeActions {
  EpisodeActions(this.actions, this.timestamp);
  final List<Map<String, dynamic>> actions;
  final int timestamp;
}
