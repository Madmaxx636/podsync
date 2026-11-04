import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

// Table definitions copied from AntennaPod's PodDBAdapter (database version 3110000).
const _schema = [
  '''CREATE TABLE Feeds (id INTEGER PRIMARY KEY AUTOINCREMENT ,title TEXT,custom_title TEXT,file_url TEXT,download_url TEXT,downloaded INTEGER,link TEXT,description TEXT,payment_link TEXT,last_update TEXT,language TEXT,author TEXT,image_url TEXT,type TEXT,feed_identifier TEXT,auto_download INTEGER DEFAULT 1,username TEXT,password TEXT,include_filter TEXT DEFAULT '',exclude_filter TEXT DEFAULT '',minimal_duration_filter INTEGER DEFAULT -1,keep_updated INTEGER DEFAULT 1,is_paged INTEGER DEFAULT 0,next_page_link TEXT,hide TEXT,sort_order TEXT,last_update_failed INTEGER DEFAULT 0,auto_delete_action INTEGER DEFAULT 0,feed_playback_speed REAL DEFAULT -1,feed_skip_silence INTEGER DEFAULT 1,feed_volume_adaption INTEGER DEFAULT 0,tags TEXT,feed_skip_intro INTEGER DEFAULT 0,feed_skip_ending INTEGER DEFAULT 0,episode_notification INTEGER DEFAULT 0,state INTEGER DEFAULT 0,new_episodes_action INTEGER DEFAULT 0)''',
  '''CREATE TABLE FeedItems (id INTEGER PRIMARY KEY AUTOINCREMENT ,title TEXT,pubDate INTEGER,read INTEGER,link TEXT,description TEXT,payment_link TEXT,media INTEGER,feed INTEGER,has_simple_chapters INTEGER,item_identifier TEXT,image_url TEXT,auto_download INTEGER,podcastindex_chapter_url TEXT,podcastindex_transcript_type TEXT,podcastindex_transcript_url TEXT,social_interact_url TEXT)''',
  '''CREATE TABLE FeedMedia (id INTEGER PRIMARY KEY AUTOINCREMENT ,duration INTEGER,file_url TEXT,download_url TEXT,downloaded INTEGER,position INTEGER,filesize INTEGER,mime_type TEXT,playback_completion_date INTEGER,feeditem INTEGER,played_duration INTEGER,has_embedded_picture INTEGER,last_played_time INTEGER)''',
  '''CREATE TABLE DownloadLog (id INTEGER PRIMARY KEY AUTOINCREMENT ,feedfile INTEGER,feedfile_type INTEGER,reason INTEGER,successful INTEGER,completion_date INTEGER,reason_detailed TEXT,title TEXT)''',
  '''CREATE TABLE Queue(id INTEGER PRIMARY KEY,feeditem INTEGER,feed INTEGER)''',
  '''CREATE TABLE SimpleChapters (id INTEGER PRIMARY KEY AUTOINCREMENT ,title TEXT,start INTEGER,feeditem INTEGER,link TEXT,image_url TEXT)''',
  '''CREATE TABLE Favorites(id INTEGER PRIMARY KEY,feeditem INTEGER,feed INTEGER)''',
];

String makeAntennaPodBackup() {
  final dir = Directory.systemTemp.createTempSync('antennapod_test');
  final path = '${dir.path}/AntennaPodBackup-2026-11-01.db';
  final db = sqlite3.open(path);
  for (final s in _schema) {
    db.execute(s);
  }
  db.execute('PRAGMA user_version = 3110000');
  // Feed 1: subscribed, customised. Feed 2: unsubscribed (kept for favorites). Feed 3: local folder.
  db.execute('''INSERT INTO Feeds (id,title,custom_title,download_url,author,image_url,tags,feed_playback_speed,feed_skip_intro,feed_skip_ending,username,password,state,auto_download)
    VALUES (1,'Tech Show','My Tech','http://a.test/feed.xml','Ann','http://a.test/i.jpg','Tech\u001eNews',1.5,15,5,'bob','secret',0,0)''');
  db.execute('''INSERT INTO Feeds (id,title,download_url,tags,state) VALUES (2,'Old Show','http://b.test/feed.xml','#root',1)''');
  db.execute('''INSERT INTO Feeds (id,title,download_url,state) VALUES (3,'Local','antennapod_local:/storage/x',0)''');
  // Items. 1: played. 2: half listened. 3: no audio. 4: in the unsubscribed feed.
  db.execute("INSERT INTO FeedItems (id,title,pubDate,read,feed,item_identifier,description) VALUES (1,'Ep One',1700000000000,1,1,'guid-1','<b>notes</b>')");
  db.execute("INSERT INTO FeedItems (id,title,pubDate,read,feed,item_identifier) VALUES (2,'Ep Two',1700100000000,0,1,'guid-2')");
  db.execute("INSERT INTO FeedItems (id,title,pubDate,read,feed,item_identifier) VALUES (3,'No audio',1700200000000,0,1,'guid-3')");
  db.execute("INSERT INTO FeedItems (id,title,pubDate,read,feed,item_identifier) VALUES (4,'Fav Ep',1600000000000,1,2,NULL)");
  db.execute("INSERT INTO FeedMedia (id,duration,download_url,position,filesize,mime_type,playback_completion_date,feeditem,last_played_time) VALUES (1,600000,'http://a.test/1.mp3',590000,1000,'audio/mpeg',1700500000000,1,1700500000000)");
  db.execute("INSERT INTO FeedMedia (id,duration,download_url,position,feeditem,last_played_time) VALUES (2,1200000,'http://a.test/2.mp3',300000,2,1700600000000)");
  db.execute("INSERT INTO FeedMedia (id,duration,download_url,position,feeditem) VALUES (4,300000,'http://b.test/4.mp3',0,4)");
  db.execute("INSERT INTO Queue (id,feeditem,feed) VALUES (1,2,1)");
  db.execute("INSERT INTO Queue (id,feeditem,feed) VALUES (2,1,1)");
  db.execute("INSERT INTO Favorites (id,feeditem,feed) VALUES (1,4,2)");
  db.execute("INSERT INTO SimpleChapters (title,start,feeditem,link) VALUES ('Intro',0,2,''),('Main',60000,2,'http://a.test/c')");
  db.execute("INSERT INTO DownloadLog (feedfile,feedfile_type,reason,successful,completion_date,title) VALUES (1,0,0,1,1700000000000,'x')");
  db.close();
  return path;
}

