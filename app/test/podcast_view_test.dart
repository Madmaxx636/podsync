import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/antennapod_import.dart';
import 'package:podsync/core/episode_view.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/ui/podcast_settings.dart';
import 'package:provider/provider.dart';

import 'fixtures.dart';

const feed = 'http://a.test/feed.xml';
const one = '$feed|guid-1', two = '$feed|guid-2';

Library loaded() {
  final lib = Library();
  importAntennaPodBackup(lib, makeAntennaPodBackup());
  return lib;
}

void main() {
  test('a podcast filter keeps only the episodes that match every choice', () {
    final lib = loaded(); // Ep One is played, Ep Two is half-listened
    List<String> ids({bool Function(String)? dl}) => EpisodeView.of(
      lib,
      feed,
      downloaded: dl ?? (_) => false,
    ).map((e) => e.id).toList();

    expect(ids().toSet(), containsAll([one, two]));
    lib.updatePodcastSettings(
      feed,
      extra: {
        'epFilter': {'played': false},
      },
    );
    expect(ids(), [two]);
    lib.updatePodcastSettings(
      feed,
      extra: {
        'epFilter': {'played': true},
      },
    );
    expect(ids(), [one]);
    lib.updatePodcastSettings(
      feed,
      extra: {
        'epFilter': {'paused': true},
      },
    );
    expect(ids(), [two]);
    lib.updatePodcastSettings(
      feed,
      extra: {
        'epFilter': {'downloaded': true},
      },
    );
    expect(ids(), isEmpty);
    expect(ids(dl: (id) => id == one), [one]);
    expect(EpisodeView.filterSummary(lib.podcasts[feed]!), 'Downloaded');
  });

  test('a podcast keeps its own sort order', () {
    final lib = loaded();
    List<String> ids() => EpisodeView.of(
      lib,
      feed,
      downloaded: (_) => false,
    ).map((e) => e.id).where((i) => i == one || i == two).toList();
    lib.updatePodcastSettings(feed, extra: {'epSort': 'dateAsc'});
    expect(ids(), [one, two]);
    lib.updatePodcastSettings(feed, extra: {'epSort': 'dateDesc'});
    expect(ids(), [two, one]);
    lib.updatePodcastSettings(feed, extra: {'epSort': 'titleDesc'});
    expect(ids(), [two, one]);
    lib.updatePodcastSettings(feed, extra: {'epSort': 'durationAsc'});
    expect(ids(), [one, two]); // 10 min before 20 min
  });

  test('a podcast can opt out of refreshing everything', () {
    final lib = loaded();
    lib.updatePodcastSettings(feed, extra: {'keepUpdated': false});
    expect(lib.podcasts[feed]!.extra['keepUpdated'], isFalse);
  });

  testWidgets('the filter sheet applies on Confirm and clears on Reset', (
    tester,
  ) async {
    final lib = loaded();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: testProviders(lib),
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showEpisodeFilter(c, feed),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not played'));
    await tester.pump();
    expect(lib.podcasts[feed]!.extra['epFilter'], isNull, reason: 'not yet');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(EpisodeView.filterOf(lib.podcasts[feed]!), {'played': false});

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(EpisodeView.filterOf(lib.podcasts[feed]!), isEmpty);
  });
}
