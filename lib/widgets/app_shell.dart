import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'common/shell_focus.dart';
import 'common/toast_overlay.dart';
import 'common/scraping_webview.dart';
import '../theme.dart';
import '../providers/feed_images_provider.dart';
import '../providers/filter_provider.dart';
import '../providers/library_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/play_tracker_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/archive_screen.dart';
import '../screens/feed_screen.dart';
import '../screens/stats_screen.dart';
import '../services/app_update_service.dart';
import '../services/tray_service.dart';
import 'modals/help_modal.dart';
import 'modals/settings_modal.dart';
import 'common/art.dart';
import 'common/finder.dart';
import 'game/game_page.dart';
import 'get/download_dock.dart';
import 'title_bar.dart';

/// Looks once per run for a newer VN Pathfinder (Settings → Update Checks).
final _appUpdateCheckProvider = Provider<void>((ref) {
  final settings = ref.read(settingsProvider);
  if (settings.lockdown || !settings.checkUpdates) return;
  AppUpdateService.newerRelease().then((tag) {
    if (tag != null) {
      ref.read(notificationProvider.notifier).info('VN Pathfinder $tag is available on GitHub.');
    }
  });
});

final _pruneFeedImagesProvider = FutureProvider<void>((ref) => FeedImageCache.prune());

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  /// Up and down arrows move through the game list.
  void _moveSelection(WidgetRef ref, int step) {
    if (ref.read(activeTabProvider) != AppTab.library || !ref.read(libraryDetailsProvider)) return;
    final groups = ref.read(filteredGroupsProvider);
    if (groups.isEmpty) return;
    final current = groups.indexWhere((g) => g.baseKey == ref.read(libraryProvider).selectedBaseKey);
    final next = current < 0 ? 0 : (current + step).clamp(0, groups.length - 1);
    ref.read(libraryProvider.notifier).select(groups[next].baseKey);
  }

  void _playSelected(WidgetRef ref) {
    if (ref.read(activeTabProvider) != AppTab.library) return;
    final group = ref.read(libraryProvider).selectedGroup;
    final version = group?.latestVersion;
    if (group != null && version != null) {
      ref.read(playTrackerProvider.notifier).launch(version, group.baseKey);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryScanProvider); // activates auto-scan listener
    ref.watch(_appUpdateCheckProvider);
    ref.watch(_pruneFeedImagesProvider);
    TrayService.instance.setEnabled(ref.watch(settingsProvider.select((s) => s.minimizeToTray)));
    final tab = ref.watch(activeTabProvider);
    final page = ref.watch(gamePageProvider);

    void toggleDiscreet() {
      final notifier = ref.read(settingsProvider.notifier);
      notifier.setDiscreet(!ref.read(settingsProvider).discreet);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => showHelpModal(context),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveSelection(ref, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveSelection(ref, -1),
        const SingleActivator(LogicalKeyboardKey.enter): () => _playSelected(ref),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => showSettingsModal(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            ref.read(finderOpenProvider.notifier).state = true,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true): toggleDiscreet,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (ref.read(gamePageProvider) != null) ref.read(gamePageProvider.notifier).state = null;
        },
      },
      child: Focus(
        focusNode: shellFocus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: Stack(
            children: [
              const Positioned.fill(child: AmbientLayer()),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppTitleBar(),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Offstage while a game page is open, so a tab keeps
                        // its filters and scroll position behind it.
                        Offstage(
                          offstage: page != null,
                          child: IndexedStack(
                            index: tab.index,
                            sizing: StackFit.expand,
                            children: const [
                              HomeScreen(),
                              LibraryScreen(),
                              ArchiveScreen(),
                              FeedScreen(),
                              StatsScreen(),
                            ],
                          ),
                        ),
                        if (page != null) Positioned.fill(child: GamePage(target: page)),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 18,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [DownloadDock(), ToastOverlay()],
                ),
              ),
              const Finder(),
              const ScrapingWebView(),
            ],
          ),
        ),
      ),
    );
  }
}
