import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../providers/library_provider.dart';
import '../../providers/filter_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../services/scanner_service.dart';
import '../../widgets/library/game_context_menu.dart';
import 'sidebar.dart';

class GameGrid extends ConsumerWidget {
  const GameGrid({super.key});

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

    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No games match the current filters.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, // cards grow up to 200px wide, then a new column is added
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.65, // portrait cover art ratio (~2:3)
      ),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return GameGridCard(
          key: ValueKey(g.baseKey),
          group: g,
          userData: ud,
          selected: g.baseKey == selectedKey,
          onTap: () {
            ref.read(libraryProvider.notifier).select(g.baseKey);
            ref.read(gridViewProvider.notifier).state = false;
          },
        );
      },
    );
  }
}

class GameGridCard extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  final bool selected;
  final VoidCallback onTap;

  const GameGridCard({
    super.key,
    required this.group,
    required this.userData,
    required this.selected,
    required this.onTap,
  });

  @override
  ConsumerState<GameGridCard> createState() => _GameGridCardState();
}

class _GameGridCardState extends ConsumerState<GameGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final isRunning = ref.watch(isGameRunningProvider(g.baseKey));
    final customArt = widget.userData.customArt[g.baseKey];
    final images = groupCarouselPaths(g, customArt);
    final cover = images.isEmpty ? null : images.first;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) => showGameContextMenu(
          context: context,
          ref: ref,
          globalPosition: details.globalPosition,
          group: g,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderMd,
            border: Border.all(
              color: widget.selected
                  ? AppColors.accent
                  : _hovered
                      ? AppColors.borderLight
                      : AppColors.border,
              width: widget.selected ? 1.5 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      blurRadius: 12,
                    )
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.borderMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover image
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GridCover(cover: cover),
                      // Running badge
                      if (isRunning)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.9),
                              borderRadius: AppRadius.borderSm,
                            ),
                            child: Text(
                              '▶ RUNNING',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      // Hover overlay
                      if (_hovered && !widget.selected)
                        Container(
                          color: Colors.white.withValues(alpha: 0.03),
                        ),
                    ],
                  ),
                ),
                // Bottom label
                Container(
                  color: widget.selected
                      ? AppColors.bgActive
                      : AppColors.bgCard,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.effectiveTitle,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.selected
                              ? AppColors.accentLight
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (g.effectiveDeveloper.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          g.effectiveDeveloper,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridCover extends StatelessWidget {
  final File? cover;
  const _GridCover({this.cover});

  @override
  Widget build(BuildContext context) {
    if (cover == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E2128), Color(0xFF14171C)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              size: 28, color: AppColors.textMuted),
        ),
      );
    }
    return Image.file(
      cover!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => Container(
        color: AppColors.bgCard,
        child: const Icon(Icons.broken_image_outlined,
            color: AppColors.textMuted, size: 28),
      ),
    );
  }
}
