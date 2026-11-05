import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/settings.dart';
import 'package:podsync/ui/desktop.dart';
import 'package:podsync/ui/desktop_toolbar.dart';
import 'package:podsync/ui/mobile.dart';
import 'package:podsync/ui/settings.dart';

import 'downloads_ui_test.dart' as f;

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = true,
  bool alt = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  group('desktop toolbar and menu bar', () {
    testWidgets('everything is shown by default', (tester) async {
      await f.pump(tester, const DesktopShell());
      expect(find.text('File'), findsOneWidget);
      for (final tip in ['Go back', 'Go forward', 'Sleep timer', 'Up Next']) {
        expect(find.byTooltip(tip), findsWidgets, reason: tip);
      }
      expect(find.byType(TextField), findsOneWidget); // search
      expect(find.text('1.0×'), findsOneWidget); // speed
    });

    testWidgets('each switch hides its item and nothing else', (tester) async {
      final rig = await f.pump(tester, const DesktopShell());
      rig.lib.setSetting('uiSleepTimer', false);
      await tester.pump();
      expect(find.byTooltip('Sleep timer'), findsNothing);
      expect(find.text('File'), findsOneWidget);

      rig.lib.setSetting('uiMenuBar', false);
      await tester.pump();
      expect(find.text('File'), findsNothing);
      expect(find.text('Controls'), findsNothing);

      rig.lib.setSetting('uiSpeed', false);
      rig.lib.setSetting('uiSearch', false);
      rig.lib.setSetting('uiBackForward', false);
      rig.lib.setSetting('uiVolume', false);
      rig.lib.setSetting('uiSkipButtons', false);
      rig.lib.setSetting('uiUpNextButton', false);
      await tester.pump();
      expect(find.text('1.0×'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Go back'), findsNothing);
      expect(find.byTooltip('Next in Up Next'), findsNothing);
      expect(find.byTooltip('Up Next'), findsNothing);
      expect(
        find.byTooltip('Play'),
        findsWidgets,
      ); // play/pause and the LCD always stay
      expect(tester.takeException(), isNull);

      rig.lib.resetInterface();
      await tester.pump();
      expect(find.text('File'), findsOneWidget);
      expect(find.byTooltip('Sleep timer'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'keyboard shortcuts work with the menu bar shown, closed, or hidden',
      (tester) async {
        final rig = await f.pump(tester, const DesktopShell());

        // Shown (and closed).
        await press(tester, LogicalKeyboardKey.digit3);
        expect(find.textContaining('ends about'), findsOneWidget);
        rig.lib.setSetting('volume', 0.5);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(rig.lib.settings.volume, closeTo(0.6, 0.001));

        // Hidden.
        rig.lib.setSetting('uiMenuBar', false);
        await tester.pump();
        await press(tester, LogicalKeyboardKey.digit2);
        expect(find.textContaining('ends about'), findsNothing);
        expect(
          find.textContaining('Unplayed ('),
          findsOneWidget,
        ); // Episodes view with its filter chips
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(rig.lib.settings.volume, closeTo(0.5, 0.001));
        await press(tester, LogicalKeyboardKey.comma);
        expect(find.text('Appearance'), findsWidgets); // Settings
        await press(tester, LogicalKeyboardKey.digit6);
        expect(find.textContaining('Nothing downloaded yet'), findsOneWidget);
      },
    );

    testWidgets(
      'right-click the toolbar toggles items, and Customize opens the Interface settings',
      (tester) async {
        final rig = await f.pump(tester, const DesktopShell());
        // Empty toolbar space just left of the LCD (which is centred in a wider slot). Looked up
        // each time, because hiding the menu bar moves the toolbar up.
        Offset toolbarGap() =>
            tester.getTopLeft(find.byType(Lcd)) + const Offset(-24, 24);

        await tester.tapAt(toolbarGap(), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        expect(find.text('Menu Bar'), findsOneWidget);
        expect(find.text('Sleep Timer'), findsOneWidget);
        await tester.tap(find.text('Menu Bar'));
        await tester.pumpAndSettle();
        expect(rig.lib.settings.uiMenuBar, isFalse);
        expect(find.text('File'), findsNothing);

        // Bring it back the same way.
        await tester.tapAt(toolbarGap(), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Menu Bar'));
        await tester.pumpAndSettle();
        expect(find.text('File'), findsOneWidget);

        await tester.tapAt(toolbarGap(), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customize Interface…'));
        await tester.pumpAndSettle();
        expect(find.text('Menu bar and toolbar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('desktop sidebar', () {
    testWidgets('sections and counts can be hidden; Settings never can', (
      tester,
    ) async {
      final rig = await f.pump(tester, const DesktopShell());
      final sidebar = find.byType(ListView).first;
      Finder inSidebar(String text) =>
          find.descendant(of: sidebar, matching: find.text(text));
      expect(inSidebar('Downloads'), findsOneWidget);
      expect(inSidebar('2'), findsOneWidget); // Up Next count

      rig.lib.setSetting('uiSidebarCounts', false);
      await tester.pump();
      expect(inSidebar('2'), findsNothing);

      rig.lib.setSetting('uiNavDownloads', false);
      rig.lib.setSetting('uiNavStats', false);
      rig.lib.setSetting('uiNavStore', false);
      rig.lib.setSetting('uiNavSubscriptions', false);
      await tester.pump();
      expect(inSidebar('Downloads'), findsNothing);
      expect(inSidebar('Statistics'), findsNothing);
      expect(inSidebar('Find Podcasts'), findsNothing);
      expect(inSidebar('My Tech'), findsNothing);
      expect(inSidebar('Up Next'), findsOneWidget);

      for (final k in AppSettings.interfaceKeys.where(
        (k) => k.startsWith('uiNav'),
      )) {
        rig.lib.setSetting(k, false);
      }
      await tester.pump();
      expect(inSidebar('Settings and Sync'), findsOneWidget); // always there
      expect(inSidebar('Library'), findsNothing); // no empty heading
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('right-click the sidebar to choose its sections', (
      tester,
    ) async {
      final rig = await f.pump(tester, const DesktopShell());
      final sidebar = find.byType(ListView).first;
      await tester.tapAt(
        tester.getBottomLeft(sidebar) + const Offset(40, -10),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Subscriptions List'), findsOneWidget);
      await tester.tap(
        find.text('Statistics').last,
      ); // the menu entry, drawn above the sidebar's
      await tester.pumpAndSettle();
      expect(rig.lib.settings.uiNavStats, isFalse);
    });

    testWidgets('the episode filter bar can be hidden', (tester) async {
      final rig = await f.pump(tester, const DesktopShell());
      expect(find.textContaining('Unplayed ('), findsOneWidget);
      rig.lib.setSetting('uiFilterBar', false);
      await tester.pump();
      expect(find.textContaining('Unplayed ('), findsNothing);
    });
  });

  group('settings page', () {
    testWidgets(
      'Interface group lists the switches, flips them, and resets them',
      (tester) async {
        final rig = await f.pump(
          tester,
          const Scaffold(body: SettingsPane(initial: 'Interface')),
          size: const Size(1300, 2600),
        );
        for (final t in [
          'Menu bar',
          'Sleep timer',
          'Volume',
          'Search field',
          'Episode filters',
          'Show everything again',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(
          find.text('Menu bar and toolbar'),
          findsOneWidget,
        ); // section captions
        await tester.tap(find.text('Sleep timer'));
        await tester.pump();
        expect(rig.lib.settings.uiSleepTimer, isFalse);
        await tester.tap(find.text('Menu bar'));
        await tester.pump();
        expect(rig.lib.settings.uiMenuBar, isFalse);

        await tester.ensureVisible(find.text('Show everything again'));
        await tester.pump();
        await tester.tap(find.text('Show everything again'));
        await tester.pump();
        expect(rig.lib.settings.uiSleepTimer, isTrue);
        expect(rig.lib.settings.uiMenuBar, isTrue);
        // Other settings are left alone.
        expect(rig.lib.settings.volume, 1.0);
      },
    );

    test('every switch is a plain true/false that defaults to shown', () {
      expect(AppSettings.interfaceKeys, isNotEmpty);
      for (final k in AppSettings.interfaceKeys) {
        expect(AppSettings.defaults[k], isTrue, reason: k);
        expect(
          AppSettings.synced.contains(k),
          isFalse,
          reason: '$k is a per-device choice',
        );
      }
      expect(
        AppSettings.interfaceKeys,
        containsAll(['uiMenuBar', 'uiSleepTimer', 'uiMiniPlayer']),
      );
      expect(
        AppSettings.interfaceKeys,
        isNot(contains('uiSettings')),
      ); // Settings itself cannot be hidden
    });
  });

  group('phone', () {
    const size = Size(1080, 2200);

    testWidgets('drawer entries, mini player and row icons can be hidden', (
      tester,
    ) async {
      final rig = await f.pump(
        tester,
        const MobileShell(),
        size: size,
        ratio: 3,
      );
      rig.player.current = rig.lib.episodes[f.two];
      // A real player notification, so the mini player picks up the new episode.
      rig.player.startSleepTimer(const Duration(minutes: 1));
      await tester.pump();
      expect(
        find.text('Ep Two'),
        findsNWidgets(2),
      ); // the queue row and the mini player

      expect(find.byTooltip('Download'), findsWidgets);

      rig.lib.setSetting('uiMiniPlayer', false);
      await tester.pump();
      expect(find.text('Ep Two'), findsOneWidget);

      rig.lib.setSetting('uiRowDownloadIcon', false);
      await tester.pump();
      expect(find.byTooltip('Download'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsOneWidget);
      await tester.tapAt(const Offset(20, 100)); // dismiss the sheet
      await tester.pumpAndSettle();
      rig.lib.setSetting('uiPhoneDownloads', false);
      rig.lib.setSetting('uiPhoneStats', false);
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsNothing);
      expect(find.text('Statistics'), findsNothing);
      expect(find.text('Settings'), findsOneWidget); // can never be hidden
      rig.player.cancelSleepTimer();
      await tester.pump();
    });

    testWidgets('episode filters can be hidden', (tester) async {
      final rig = await f.pump(
        tester,
        const MobileShell(),
        size: size,
        ratio: 3,
      );
      await tester.tap(find.text('Episodes'));
      await tester.pumpAndSettle();
      expect(find.text('Unplayed'), findsOneWidget);
      rig.lib.setSetting('uiPhoneFilters', false);
      await tester.pump();
      expect(find.text('Unplayed'), findsNothing);
    });

    testWidgets(
      'player screen: sleep timer, volume and speed can each be hidden',
      (tester) async {
        final rig = await f.pump(
          tester,
          const PlayerScreen(),
          size: size,
          ratio: 3,
        );
        rig.player.current = rig.lib.episodes[f.two];
        rig.lib.setSetting(
          'uiPlayerSleep',
          true,
        ); // triggers a rebuild that sees the playing episode
        await tester.pump();
        expect(find.byTooltip('Sleep timer'), findsOneWidget);
        expect(find.byTooltip('Mute'), findsOneWidget);
        expect(find.byTooltip('Playback speed'), findsOneWidget);

        rig.lib.setSetting('uiPlayerSleep', false);
        rig.lib.setSetting('uiPlayerVolume', false);
        rig.lib.setSetting('uiPlayerSpeed', false);
        await tester.pump();
        expect(find.byTooltip('Sleep timer'), findsNothing);
        expect(find.byTooltip('Mute'), findsNothing);
        expect(find.byTooltip('Playback speed'), findsNothing);
        expect(
          find.byIcon(Icons.play_arrow),
          findsWidgets,
        ); // the transport itself stays
      },
    );
  });
}
