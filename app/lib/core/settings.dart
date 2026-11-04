/// Every user-facing setting, with its default. Settings marked synced travel
/// with the account (PodSync server); the rest belong to this device only.
class AppSettings {
  static const Map<String, Object> defaults = {
    // Appearance (this device)
    'themeMode': 'system', // system | light | dark
    'accent': 0xFF2196F3,
    'textScale': 1.0,
    'compact': false,
    'showArtwork': true,
    'dateStyle': 'mdy', // mdy | dmy | iso

    // Network (this device)
    'requestTimeoutSec': 30,
    'userAgent': '',

    // Automation (this device)
    'refreshOnLaunch': true,
    'refreshIntervalMin': 0,
    'syncOnStart': true,
    'syncOnPause': true,
    'syncIntervalMin': 0,

    // E-ink (this device)
    'einkRowHeight': 88,
    'einkClockSec': 30,
    'einkGrayArt': true,
    'einkSwipe': true,

    // Desktop layout (this device)
    'sidebarWidth': 200.0,
    'tableRowHeight': 22,
    'colTime': true,
    'colPodcast': true,
    'colDate': true,

    // Playback (synced)
    'continueQueue': true,
    'removePlayedFromQueue': true,
    'smartRewindSec': 0,
    'autoPlayedRemainingSec': 0,
    'skipSilence': false,

    // Library (synced)
    'sortOldestFirst': false,
    'hidePlayed': false,
    'newEpisodesAction': 0, // 0 nothing | 1 add to end of queue | 2 add to front of queue
    'maxEpisodesPerFeed': 0, // 0 = keep everything
  };

  static const Set<String> synced = {
    'continueQueue',
    'removePlayedFromQueue',
    'smartRewindSec',
    'autoPlayedRemainingSec',
    'skipSilence',
    'sortOldestFirst',
    'hidePlayed',
    'newEpisodesAction',
    'maxEpisodesPerFeed',
  };

  final Map<String, Object> _v = {...defaults};

  AppSettings([Map<String, dynamic>? json]) {
    if (json != null) applyJson(json);
  }

  /// Takes values from [json] for known keys with the right type; anything else is ignored.
  void applyJson(Map<String, dynamic> json) {
    json.forEach((k, v) {
      final d = defaults[k];
      if (d == null) return;
      if (d is double && v is num) {
        _v[k] = v.toDouble();
      } else if (d is int && v is num) {
        _v[k] = v.toInt();
      } else if (d.runtimeType == v.runtimeType) {
        _v[k] = v as Object;
      }
    });
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_v);

  Map<String, dynamic> syncedJson() => {for (final k in synced) k: _v[k]};

  void applySynced(Map<String, dynamic> json) => applyJson({
        for (final e in json.entries)
          if (synced.contains(e.key)) e.key: e.value,
      });

  void set(String key, Object value) {
    assert(defaults.containsKey(key), 'unknown setting $key');
    _v[key] = value;
  }

  void reset(String key) => _v[key] = defaults[key]!;

  Object operator [](String key) => _v[key]!;

  T _get<T>(String k) => _v[k] as T;

  String get themeMode => _get('themeMode');
  int get accent => _get('accent');
  double get textScale => _get('textScale');
  bool get compact => _get('compact');
  bool get showArtwork => _get('showArtwork');
  String get dateStyle => _get('dateStyle');
  int get requestTimeoutSec => _get('requestTimeoutSec');
  String get userAgent => _get('userAgent');
  bool get refreshOnLaunch => _get('refreshOnLaunch');
  int get refreshIntervalMin => _get('refreshIntervalMin');
  bool get syncOnStart => _get('syncOnStart');
  bool get syncOnPause => _get('syncOnPause');
  int get syncIntervalMin => _get('syncIntervalMin');
  int get einkRowHeight => _get('einkRowHeight');
  int get einkClockSec => _get('einkClockSec');
  bool get einkGrayArt => _get('einkGrayArt');
  bool get einkSwipe => _get('einkSwipe');
  double get sidebarWidth => _get('sidebarWidth');
  int get tableRowHeight => _get('tableRowHeight');
  bool get colTime => _get('colTime');
  bool get colPodcast => _get('colPodcast');
  bool get colDate => _get('colDate');
  bool get continueQueue => _get('continueQueue');
  bool get removePlayedFromQueue => _get('removePlayedFromQueue');
  int get smartRewindSec => _get('smartRewindSec');
  int get autoPlayedRemainingSec => _get('autoPlayedRemainingSec');
  bool get skipSilence => _get('skipSilence');
  bool get sortOldestFirst => _get('sortOldestFirst');
  bool get hidePlayed => _get('hidePlayed');
  int get newEpisodesAction => _get('newEpisodesAction');
  int get maxEpisodesPerFeed => _get('maxEpisodesPerFeed');

  /// Changes whenever something that affects the app-wide theme changes.
  String get appearanceKey => '$themeMode|$accent|$textScale|$compact';

  String get effectiveUserAgent => userAgent.isEmpty ? 'PodSync/0.1' : userAgent;
}

/// Date style for [fmtDate]-style formatting, set by the library when settings load or change.
String currentDateStyle = 'mdy';
