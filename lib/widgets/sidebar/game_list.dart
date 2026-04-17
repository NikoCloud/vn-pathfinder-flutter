import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/filter_provider.dart';
import '../../providers/settings_provider.dart';
import 'game_entry.dart';

class GameList extends ConsumerWidget {
  const GameList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(filteredGroupsProvider);
    final ud = ref.watch(userDataProvider);
    final selectedKey = ref.watch(libraryProvider).selectedBaseKey;
    final libState = ref.watch(libraryProvider);

    if (libState.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }

    if (libState.error != null && groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          libState.error!,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      );
    }

    if (groups.isEmpty) {
      final libraryDir = ref.watch(libraryDirProvider);
      if (libraryDir.isEmpty) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No games match the current filters.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      itemCount: groups.length,
      itemExtent: 62, // fixed height for perf (40px thumb + 11px padding each side)
      itemBuilder: (context, i) {
        final g = groups[i];
        return GameEntry(
          key: ValueKey(g.baseKey),
          group: g,
          userData: ud,
          selected: g.baseKey == selectedKey,
          onTap: () {
            ref.read(libraryProvider.notifier).select(g.baseKey);
          },
        );
      },
    );
  }
}
