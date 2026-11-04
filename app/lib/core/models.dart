class Podcast {
  final String feedUrl;
  String title;
  String customTitle;
  String author;
  String imageUrl;
  String description;
  String link;
  String language;
  bool subscribed;
  int updatedAt;

  // Per-podcast settings (these sync).
  double? speed; // null = use the global speed
  int skipIntroSec;
  int skipEndingSec;
  List<String> tags;

  /// Everything else AntennaPod stores per feed (filters, auto-download, auto-delete,
  /// volume adaption, notifications...). Kept verbatim so a backup loses nothing.
  Map<String, dynamic> extra;

  /// Credentials for password-protected feeds. Stay on this device; never synced.
  String username;
  String password;

  Podcast({
    required this.feedUrl,
    this.title = '',
    this.customTitle = '',
    this.author = '',
    this.imageUrl = '',
    this.description = '',
    this.link = '',
    this.language = '',
    this.subscribed = true,
    this.updatedAt = 0,
    this.speed,
    this.skipIntroSec = 0,
    this.skipEndingSec = 0,
    List<String>? tags,
    Map<String, dynamic>? extra,
    this.username = '',
    this.password = '',
  })  : tags = tags ?? [],
        extra = extra ?? {};

  String get displayTitle => customTitle.isNotEmpty ? customTitle : title;

  Map<String, dynamic> toJson() => {
        'feedUrl': feedUrl,
        'title': title,
        'customTitle': customTitle,
        'author': author,
        'imageUrl': imageUrl,
        'description': description,
        'link': link,
        'language': language,
        'subscribed': subscribed,
        'updatedAt': updatedAt,
        'speed': speed,
        'skipIntroSec': skipIntroSec,
        'skipEndingSec': skipEndingSec,
        'tags': tags,
        'extra': extra,
        'username': username,
        'password': password,
      };

  factory Podcast.fromJson(Map<String, dynamic> j) => Podcast(
        feedUrl: j['feedUrl'],
        title: j['title'] ?? '',
        customTitle: j['customTitle'] ?? '',
        author: j['author'] ?? '',
        imageUrl: j['imageUrl'] ?? '',
        description: j['description'] ?? '',
        link: j['link'] ?? '',
        language: j['language'] ?? '',
        subscribed: j['subscribed'] ?? true,
        updatedAt: j['updatedAt'] ?? 0,
        speed: (j['speed'] as num?)?.toDouble(),
        skipIntroSec: j['skipIntroSec'] ?? 0,
        skipEndingSec: j['skipEndingSec'] ?? 0,
        tags: List<String>.from(j['tags'] ?? []),
        extra: Map<String, dynamic>.from(j['extra'] ?? {}),
        username: j['username'] ?? '',
        password: j['password'] ?? '',
      );
}

class Chapter {
  final int startMs;
  final String title;
  final String link;
  final String imageUrl;
  const Chapter(this.startMs, this.title, {this.link = '', this.imageUrl = ''});

  Map<String, dynamic> toJson() => {'start': startMs, 'title': title, 'link': link, 'image': imageUrl};

  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(j['start'] ?? 0, j['title'] ?? '', link: j['link'] ?? '', imageUrl: j['image'] ?? '');
}

class Episode {
  final String feedUrl;
  final String guid;
  final String title;
  final String description;
  final String audioUrl;
  final int published; // ms since epoch
  final int durationMs;
  final String imageUrl;
  final String link;
  final int fileSize;
  final String mimeType;
  final List<Chapter> chapters;

  Episode({
    required this.feedUrl,
    required this.guid,
    required this.title,
    required this.audioUrl,
    this.description = '',
    this.published = 0,
    this.durationMs = 0,
    this.imageUrl = '',
    this.link = '',
    this.fileSize = 0,
    this.mimeType = '',
    this.chapters = const [],
  });

  /// Stable id shared across devices.
  String get id => '$feedUrl|$guid';

  Map<String, dynamic> toJson() => {
        'feedUrl': feedUrl,
        'guid': guid,
        'title': title,
        'description': description,
        'audioUrl': audioUrl,
        'published': published,
        'durationMs': durationMs,
        'imageUrl': imageUrl,
        'link': link,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        feedUrl: j['feedUrl'],
        guid: j['guid'],
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        audioUrl: j['audioUrl'] ?? '',
        published: j['published'] ?? 0,
        durationMs: j['durationMs'] ?? 0,
        imageUrl: j['imageUrl'] ?? '',
        link: j['link'] ?? '',
        fileSize: j['fileSize'] ?? 0,
        mimeType: j['mimeType'] ?? '',
        chapters: [for (final c in (j['chapters'] as List? ?? [])) Chapter.fromJson(Map<String, dynamic>.from(c))],
      );

  /// A refreshed copy of this episode from the feed, keeping data the feed
  /// does not carry (chapters read from a backup, a longer-lived description).
  Episode mergedWith(Episode fresh) => Episode(
        feedUrl: feedUrl,
        guid: guid,
        title: fresh.title.isNotEmpty ? fresh.title : title,
        audioUrl: fresh.audioUrl.isNotEmpty ? fresh.audioUrl : audioUrl,
        description: fresh.description.isNotEmpty ? fresh.description : description,
        published: fresh.published > 0 ? fresh.published : published,
        durationMs: fresh.durationMs > 0 ? fresh.durationMs : durationMs,
        imageUrl: fresh.imageUrl.isNotEmpty ? fresh.imageUrl : imageUrl,
        link: fresh.link.isNotEmpty ? fresh.link : link,
        fileSize: fresh.fileSize > 0 ? fresh.fileSize : fileSize,
        mimeType: fresh.mimeType.isNotEmpty ? fresh.mimeType : mimeType,
        chapters: fresh.chapters.isNotEmpty ? fresh.chapters : chapters,
      );
}

class Progress {
  int positionMs;
  int durationMs;
  bool played;
  bool isNew; // AntennaPod's "New" inbox state
  int lastPlayedAt; // ms since epoch, 0 if never
  int updatedAt;

  Progress({
    this.positionMs = 0,
    this.durationMs = 0,
    this.played = false,
    this.isNew = false,
    this.lastPlayedAt = 0,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'pos': positionMs,
        'dur': durationMs,
        'played': played,
        'new': isNew,
        'lastPlayed': lastPlayedAt,
        'updatedAt': updatedAt,
      };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        positionMs: j['pos'] ?? 0,
        durationMs: j['dur'] ?? 0,
        played: j['played'] ?? false,
        isNew: j['new'] ?? false,
        lastPlayedAt: j['lastPlayed'] ?? 0,
        updatedAt: j['updatedAt'] ?? 0,
      );
}

/// A last-write-wins on/off flag (used for favorites).
class Flag {
  bool on;
  int at;
  Flag(this.on, this.at);
}

/// A result from the iTunes directory search.
class SearchResult {
  final String feedUrl;
  final String title;
  final String author;
  final String imageUrl;
  SearchResult(this.feedUrl, this.title, this.author, this.imageUrl);
}
