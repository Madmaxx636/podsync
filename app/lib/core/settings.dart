/// Every user-facing setting, with its default. Settings marked synced travel
/// with the account (PodSync server); the rest belong to this device only.
class AppSettings {
  static const Map<String, Object> defaults = {
    // Appearance (this device)
    'themeMode': 'system', // system | light | dark
    'accent': 0xFF2196F3,
    'textScale': 1.0,
    'zoom':
        1.0, // desktop: scales the whole window (Ctrl + mouse wheel, Ctrl +/-)
    'compact': false,
    'showArtwork': true,
    'dateStyle': 'mdy', // mdy | dmy | iso
    // Desktop system integration (this device)
    'trayIcon': true, // a tray / notification-area icon with play controls
    'closeToTray':
        true, // closing the window keeps PodSync playing from the tray
    'startAtLogin': false,
    'startMinimized': true, // when started at login, stay in the tray instead of opening a window
    'mediaControls': true, // media keys and the system's now-playing controls
    'notifyNewEpisodes':
        true, // a desktop notification when a refresh finds new episodes
    'notifyDownloads': true, // ... when a download finishes
    'notifyNowPlaying': false, // ... when the next episode starts
    'taskbarControls':
        true, // Windows: play, pause and skip buttons in the taskbar preview
    // Which screen PodSync opens on (this device): '' = the usual one, 'last' = where you left off
    'startScreen': '',
    'lastScreen': '', // remembered when startScreen is 'last'
    // Updates (this device)
    'updateCheck': true,
    'updateAuto': true, // Windows and Linux: install a found update at start-up without asking
    'updateSkipped':
        '', // a version the person chose not to be told about again
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

    // Interface: what is shown (this device). Every one of these can be hidden; Settings itself cannot.
    'uiMenuBar': true,
    'uiBackForward': true,
    'uiSkipButtons': true,
    'uiVolume': true,
    'uiUpNextButton': true,
    'uiDownloadsButton': true,
    'uiSleepTimer': true,
    'uiSpeed': true,
    'uiSearch': true,
    'uiSidebarCounts': true,
    'uiNavPodcasts': true,
    'uiNavEpisodes': true,
    'uiNavUpNext': true,
    'uiNavFavorites': true,
    'uiNavHistory': true,
    'uiNavDownloads': true,
    'uiNavStats': true,
    'uiNavStore': true,
    'uiNavSubscriptions': true,
    'uiFilterBar': true,
    'uiPhoneDownloads': true,
    'uiPhoneStats': true,
    'uiMiniPlayer': true,
    'uiPlayerSleep': true,
    'uiPlayerVolume': true,
    'uiPlayerSpeed': true,
    'uiPhoneFilters': true,
    'uiRowDownloadIcon': true,

    // Podcast store (this device)
    'storeCountry': 'us',

    // Downloads (this device)
    'autoDownloadQueue': false, // keep the next Up Next episodes downloaded
    'autoDownloadQueueCount': 5, // how many; 0 = everything in Up Next
    'autoDownloadNew': false, // download new episodes of subscribed podcasts
    'autoDownloadNewLimit': 3, // at most this many per podcast per refresh
    'autoDeleteHours': -1, // -1 never, 0 as soon as played, otherwise hours after it was played
    'keepFavoriteDownloads': true,
    'maxDownloads': 2,
    'downloadWifiOnly': true,
    'downloadDir': '',
    'colDownload': true,

    // Volume (this device)
    'volume': 1.0,
    'muted': false,

    // Desktop layout (this device)
    'showSidebar': true,
    'showArtworkPane': true,
    'showDetails': false,
    'showStatusBar': true,
    'lcdRemaining': true, // the LCD's right-hand time counts down instead of showing the total
    'confirmClearQueue': false, // Clear has Undo, so asking first is optional
    'colRating': true,
    'colStarts': true,
    'navPosition': 'bottom', // phone: where the tabs sit, 'bottom' or 'top'
    'navTabs': 'queue,episodes,podcasts,add', // phone: the tabs shown, in order
    'playerBarSize': 'medium', // phone: height of the bar at the bottom, small|medium|large|huge
    'playerBarButtons':
        'rewind,play,forward,next', // phone: buttons on that bar, in order
    'podcastsTab':
        'unplayed', // desktop Podcasts section: unplayed | mine | list
    'podcastsSelected': '', // desktop My Podcasts: the show you were looking at
    'podcastOrder': '', // desktop My Podcasts: feed URLs in the order you dragged them, one per line
    'podcastsView': '', // phone: '' (grid, or list on e-ink) | grid | list
    'gridColumns': 3, // phone: podcasts per row in the grid
    'playerBarButtonPct': 100, // phone: size of the bar's buttons, percent
    'playerControlPct':
        100, // phone: size of the player screen's controls, percent
    'playerButtons': 'speed,rewind,play,forward,next', // phone player screen: buttons, in order
    'playerLift':
        0, // phone player screen: dp the buttons are raised from the bottom
    'autoScale':
        false, // scale the interface with the window size (this device)
    'colStartsAt': true,
    'colEndsAt': true,
    'sidebarWidth': 200.0,
    'settingsListWidth': 250.0, // the list of groups in Settings
    'detailsWidth': 300.0, // the info pane on the right
    'podsColumnWidth': 230.0, // the list of shows in Podcasts > My Podcasts
    'artworkSize':
        0.0, // the artwork square under the sidebar; 0 = as wide as the sidebar
    // Top bar layout (Customize Toolbar): the order of its parts and their sizes
    'toolbarOrder':
        'transport,volume,display,upnext,downloads,sleep,speed,search',
    'toolbarHeight': 58, // 54 to 90
    'toolbarScale': 1.0, // size of the buttons and icons
    'lcdWidth': 680.0, // the widest the display grows
    'searchWidth': 170.0,
    'volumeWidth': 100.0,
    'colWidths': '', // dragged column widths, like 'podcast=240,time=80'
    'tableRowHeight': 24,
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
    'newEpisodesAction':
        0, // 0 nothing | 1 add to end of queue | 2 add to front of queue
    'maxEpisodesPerFeed': 0, // 0 = keep everything
  };

  /// Travel with the account to every device. Anything about this device's own window, folders,
  /// tray, e-ink screen or which buttons are shown stays here.
  static const Set<String> synced = {
    // Playback
    'continueQueue',
    'removePlayedFromQueue',
    'smartRewindSec',
    'autoPlayedRemainingSec',
    'skipSilence',
    // Library
    'sortOldestFirst',
    'hidePlayed',
    'newEpisodesAction',
    'maxEpisodesPerFeed',
    // Appearance
    'themeMode',
    'accent',
    'textScale',
    'compact',
    'showArtwork',
    'dateStyle',
    // Downloads
    'autoDownloadQueue',
    'autoDownloadQueueCount',
    'autoDownloadNew',
    'autoDownloadNewLimit',
    'autoDeleteHours',
    'keepFavoriteDownloads',
    'maxDownloads',
    'downloadWifiOnly',
    // Automation and notifications
    'refreshOnLaunch',
    'refreshIntervalMin',
    'syncOnStart',
    'syncOnPause',
    'syncIntervalMin',
    'notifyNewEpisodes',
    'notifyDownloads',
    'confirmClearQueue',
    'storeCountry',
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
  double get zoom => _get('zoom');
  String get toolbarOrder => _get('toolbarOrder');
  int get toolbarHeight => _get('toolbarHeight');
  double get toolbarScale => _get('toolbarScale');
  double get lcdWidth => _get('lcdWidth');
  double get searchWidth => _get('searchWidth');
  double get volumeWidth => _get('volumeWidth');

  static const toolbarParts = [
    'transport',
    'volume',
    'display',
    'upnext',
    'downloads',
    'sleep',
    'speed',
    'search',
  ];

  /// The top bar's parts in the order chosen; unknown names are dropped and missing ones go last.
  List<String> get toolbarItems {
    final out = <String>[];
    for (final k in toolbarOrder.split(',')) {
      if (toolbarParts.contains(k) && !out.contains(k)) out.add(k);
    }
    for (final k in toolbarParts) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  String get colWidths => _get('colWidths');

  /// The column widths the person dragged to, by column key.
  Map<String, double> get colWidthMap {
    final out = <String, double>{};
    for (final part in colWidths.split(',')) {
      final kv = part.split('=');
      final w = kv.length == 2 ? double.tryParse(kv[1]) : null;
      if (w != null && w > 0) out[kv[0]] = w;
    }
    return out;
  }

  bool get compact => _get('compact');
  bool get showArtwork => _get('showArtwork');
  String get dateStyle => _get('dateStyle');
  int get requestTimeoutSec => _get('requestTimeoutSec');
  String get userAgent => _get('userAgent');
  bool get trayIcon => _get('trayIcon');
  bool get closeToTray => _get('closeToTray');
  bool get startAtLogin => _get('startAtLogin');
  bool get startMinimized => _get('startMinimized');
  bool get mediaControls => _get('mediaControls');
  bool get notifyNewEpisodes => _get('notifyNewEpisodes');
  bool get notifyDownloads => _get('notifyDownloads');
  bool get notifyNowPlaying => _get('notifyNowPlaying');
  bool get taskbarControls => _get('taskbarControls');
  String get startScreen => _get('startScreen');
  String get lastScreen => _get('lastScreen');
  bool get updateCheck => _get('updateCheck');
  bool get updateAuto => _get('updateAuto');
  String get updateSkipped => _get('updateSkipped');
  bool get refreshOnLaunch => _get('refreshOnLaunch');
  int get refreshIntervalMin => _get('refreshIntervalMin');
  bool get syncOnStart => _get('syncOnStart');
  bool get syncOnPause => _get('syncOnPause');
  int get syncIntervalMin => _get('syncIntervalMin');
  int get einkRowHeight => _get('einkRowHeight');
  int get einkClockSec => _get('einkClockSec');
  bool get einkGrayArt => _get('einkGrayArt');
  bool get einkSwipe => _get('einkSwipe');
  double get volume => _get('volume');
  bool get muted => _get('muted');
  bool get showSidebar => _get('showSidebar');
  bool get showArtworkPane => _get('showArtworkPane');
  bool get showDetails => _get('showDetails');
  bool get showStatusBar => _get('showStatusBar');
  bool get lcdRemaining => _get('lcdRemaining');
  bool get confirmClearQueue => _get('confirmClearQueue');
  bool get colRating => _get('colRating');
  bool get uiMenuBar => _get('uiMenuBar');
  bool get uiBackForward => _get('uiBackForward');
  bool get uiSkipButtons => _get('uiSkipButtons');
  bool get uiVolume => _get('uiVolume');
  bool get uiUpNextButton => _get('uiUpNextButton');
  bool get uiDownloadsButton => _get('uiDownloadsButton');
  bool get uiSleepTimer => _get('uiSleepTimer');
  bool get uiSpeed => _get('uiSpeed');
  bool get uiSearch => _get('uiSearch');
  bool get uiSidebarCounts => _get('uiSidebarCounts');
  bool get uiNavPodcasts => _get('uiNavPodcasts');
  bool get uiNavEpisodes => _get('uiNavEpisodes');
  bool get uiNavUpNext => _get('uiNavUpNext');
  bool get uiNavFavorites => _get('uiNavFavorites');
  bool get uiNavHistory => _get('uiNavHistory');
  bool get uiNavDownloads => _get('uiNavDownloads');
  bool get uiNavStats => _get('uiNavStats');
  bool get uiNavStore => _get('uiNavStore');
  bool get uiNavSubscriptions => _get('uiNavSubscriptions');
  bool get uiFilterBar => _get('uiFilterBar');
  bool get uiPhoneDownloads => _get('uiPhoneDownloads');
  bool get uiPhoneStats => _get('uiPhoneStats');
  bool get uiMiniPlayer => _get('uiMiniPlayer');
  bool get uiPlayerSleep => _get('uiPlayerSleep');
  bool get uiPlayerVolume => _get('uiPlayerVolume');
  bool get uiPlayerSpeed => _get('uiPlayerSpeed');
  bool get uiPhoneFilters => _get('uiPhoneFilters');
  bool get uiRowDownloadIcon => _get('uiRowDownloadIcon');
  bool get colStarts => _get('colStarts');
  String get navPosition => _get('navPosition') == 'top' ? 'top' : 'bottom';

  /// The phone tabs that are switched on, in order; never empty.
  List<String> get navTabs {
    const all = ['queue', 'episodes', 'podcasts', 'add'];
    final out = {
      for (final k in (_get('navTabs') as String).split(','))
        if (all.contains(k.trim())) k.trim(),
    }.toList();
    return out.isEmpty ? ['queue'] : out;
  }

  String get playerBarSize => _get('playerBarSize');
  List<String> get playerBarButtons {
    const all = ['rewind', 'play', 'forward', 'next'];
    final out = {
      for (final k in (_get('playerBarButtons') as String).split(','))
        if (all.contains(k.trim())) k.trim(),
    }.toList();
    return out.contains('play') ? out : ['play', ...out];
  }

  /// 'grid' or 'list': what you chose, else a grid in colour and a list on e-ink.
  String podcastsViewFor(bool eink) {
    final v = _get('podcastsView');
    return v == 'grid' || v == 'list' ? v : (eink ? 'list' : 'grid');
  }

  int get gridColumns => (_get('gridColumns') as int).clamp(2, 6);
  int get playerBarButtonPct => _get('playerBarButtonPct');
  int get playerControlPct => _get('playerControlPct');
  int get playerLift => _get('playerLift');
  List<String> get playerButtons {
    const all = ['speed', 'rewind', 'play', 'forward', 'next'];
    final out = {
      for (final k in (_get('playerButtons') as String).split(','))
        if (all.contains(k.trim())) k.trim(),
    }.toList();
    return out.contains('play') ? out : [...out, 'play'];
  }

  bool get autoScale => _get('autoScale');
  bool get colStartsAt => _get('colStartsAt');
  bool get colEndsAt => _get('colEndsAt');
  bool get colDownload => _get('colDownload');
  String get storeCountry => _get('storeCountry');
  bool get autoDownloadQueue => _get('autoDownloadQueue');
  int get autoDownloadQueueCount => _get('autoDownloadQueueCount');
  bool get autoDownloadNew => _get('autoDownloadNew');
  int get autoDownloadNewLimit => _get('autoDownloadNewLimit');
  int get autoDeleteHours => _get('autoDeleteHours');
  bool get keepFavoriteDownloads => _get('keepFavoriteDownloads');
  int get maxDownloads => _get('maxDownloads');
  bool get downloadWifiOnly => _get('downloadWifiOnly');
  String get downloadDir => _get('downloadDir');
  double get sidebarWidth => _get('sidebarWidth');
  double get settingsListWidth => _get('settingsListWidth');
  double get detailsWidth => _get('detailsWidth');
  double get podsColumnWidth => _get('podsColumnWidth');
  double get artworkSize => _get('artworkSize');
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

  /// The keys of every show/hide switch in the interface.
  static final List<String> interfaceKeys = [
    for (final k in defaults.keys)
      if (k.startsWith('ui') && k.length > 2 && k[2] == k[2].toUpperCase()) k,
  ];

  /// Changes whenever something that affects the app-wide theme changes.
  String get appearanceKey =>
      '$themeMode|$accent|$textScale|$compact|$zoom|$autoScale';

  String get effectiveUserAgent =>
      userAgent.isEmpty ? 'PodSync/0.1' : userAgent;
}

/// Date style for [fmtDate]-style formatting, set by the library when settings load or change.
String currentDateStyle = 'mdy';
