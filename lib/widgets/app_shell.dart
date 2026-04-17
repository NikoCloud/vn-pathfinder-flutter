import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers/library_provider.dart';
import '../screens/library_screen.dart';
import '../screens/archive_screen.dart';
import 'navbar.dart';
import 'status_bar.dart';

// Tracks which top-level tab is active (0=Library, 1=Archive)
final activeTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryScanProvider); // activates auto-scan listener
    final tab = ref.watch(activeTabProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          AppNavbar(
            selectedTab: tab,
            onTabChanged: (i) => ref.read(activeTabProvider.notifier).state = i,
          ),
          Expanded(
            // IndexedStack preserves scroll/state between tabs
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
              // Add game flow wired in Phase 5
            },
          ),
        ],
      ),
    );
  }
}
