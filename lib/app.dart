import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/settings_provider.dart';
import 'widgets/app_shell.dart';

class VNPathfinderApp extends ConsumerStatefulWidget {
  const VNPathfinderApp({super.key});

  @override
  ConsumerState<VNPathfinderApp> createState() => _VNPathfinderAppState();
}

class _VNPathfinderAppState extends ConsumerState<VNPathfinderApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The "System" theme follows Windows while the app is open.
  @override
  void didChangePlatformBrightness() => ref.invalidate(appThemeDataProvider);

  /// Widgets read AppColors when they build, and many are const or keep their
  /// old build, so a theme change has to rebuild the whole tree. Doing it this
  /// way keeps its state: an open Settings window stays open.
  void _rebuildEverything() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      if (mounted) (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appThemeDataProvider, (_, _) => _rebuildEverything());
    final themeData = ref.watch(appThemeDataProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final fontSize = ref.watch(settingsProvider.select((s) => s.fontSize));

    return MaterialApp(
      title: 'VN Pathfinder',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      darkTheme: themeData,
      themeMode: themeMode,
      // Sizes are written for the default 13; the setting scales all text.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fontSize / 13)),
        child: child!,
      ),
      home: const AppShell(),
    );
  }
}
