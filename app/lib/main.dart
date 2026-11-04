import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'core/directory.dart';
import 'core/downloads.dart';
import 'core/library.dart';
import 'core/player.dart';
import 'ui/desktop.dart';
import 'ui/mobile.dart';
import 'ui/store_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'dev.podsync.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
    );
  } else {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  }

  final library = Library();
  await library.load();
  final downloads = DownloadManager(library);
  await downloads.start();
  final player = PlayerController(library, downloads: downloads);
  final store = StoreController(StoreDirectory(), library);
  library.startBackground();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: player),
      ],
      child: const PodSyncApp(),
    ),
  );
}

class PodSyncApp extends StatelessWidget {
  const PodSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app only when something that affects the theme changes.
    context.select<Library, String>(
      (l) => '${l.settings.appearanceKey}|${l.einkMode}',
    );
    final lib = context.read<Library>();
    final s = lib.settings;
    final eink = lib.einkMode;
    return MaterialApp(
      title: 'PodSync',
      debugShowCheckedModeBanner: false,
      theme: eink
          ? _einkTheme()
          : _theme(Color(s.accent), Brightness.light, s.compact),
      darkTheme: eink
          ? null
          : _theme(Color(s.accent), Brightness.dark, s.compact),
      themeMode: eink
          ? ThemeMode.light
          : switch (s.themeMode) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(s.textScale)),
        child: child!,
      ),
      home: Platform.isAndroid ? const MobileShell() : const DesktopShell(),
    );
  }
}

ThemeData _theme(Color seed, Brightness brightness, bool compact) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
);

/// Pure black on white, no animation, no ripple: refreshes are slow and
/// ghosty on e-ink, so nothing should move.
ThemeData _einkTheme() {
  const scheme = ColorScheme.light(
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    surface: Colors.white,
    onSurface: Colors.black,
    outline: Colors.black,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.windows: _NoTransitionBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      shape: Border(bottom: BorderSide(width: 2)),
    ),
    dividerTheme: const DividerThemeData(color: Colors.black, thickness: 1),
    textTheme: Typography.blackMountainView.apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        minimumSize: const Size(64, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: const BorderSide(width: 2),
        minimumSize: const Size(64, 48),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colors.black,
        minimumSize: const Size(48, 48),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Colors.black,
      inactiveTrackColor: Colors.black38,
      thumbColor: Colors.black,
      trackHeight: 4,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Colors.black,
      linearTrackColor: Colors.black12,
    ),
  );
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
