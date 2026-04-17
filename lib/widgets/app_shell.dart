import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers/library_provider.dart';
import '../screens/library_screen.dart';
import '../screens/archive_screen.dart';
import 'modals/settings_modal.dart';
import 'navbar.dart';
import 'status_bar.dart';

// Tracks which top-level tab is active (0=Library, 1=Archive)
final activeTabProvider = StateProvider<int>((ref) => 0);

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryScanProvider); // activates auto-scan listener
    final tab = ref.watch(activeTabProvider);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma):
            const _OpenSettingsIntent(),
      },
      child: Actions(
        actions: {
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) => showSettingsModal(context),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.bgPrimary,
            body: Column(
              children: [
                AppNavbar(
                  selectedTab: tab,
                  onTabChanged: (i) =>
                      ref.read(activeTabProvider.notifier).state = i,
                ),
                Expanded(
                  child: IndexedStack(
                    index: tab,
                    children: const [
                      LibraryScreen(),
                      ArchiveScreen(),
                    ],
                  ),
                ),
                AppStatusBar(
                  onAddGame: () {
                    // TODO: Phase 9 add-game flow
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
