import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../models/game_group.dart';
import '../../models/game_status.dart';
import '../../models/user_data.dart';
import '../../providers/library_provider.dart';
import '../../providers/update_provider.dart';
import '../common/status_menu.dart';
import '../../services/scanner_service.dart';

class GameEntry extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset)? onRightClick;

  const GameEntry({
    super.key,
    required this.group,
    required this.userData,
    required this.selected,
    required this.onTap,
    this.onRightClick,
  });

  @override
  ConsumerState<GameEntry> createState() => _GameEntryState();
}

class _GameEntryState extends ConsumerState<GameEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Same test the status filter uses (manual mark, playtime or saves).
    final played = isGamePlayed(widget.group, widget.userData);

    final bg = widget.selected
        ? AppColors.bgActive
        : _hovered
            ? AppColors.bgHover
            : Colors.transparent;

    final borderColor = widget.selected
        ? AppColors.accent
        : _hovered
            ? AppColors.accentDim
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) => widget.onRightClick?.call(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(color: borderColor, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(9, 4, 12, 4),
          child: Row(
            children: [
              _CoverThumb(
                group: widget.group,
                userData: widget.userData,
                imageEpoch: ref.watch(imageEpochProvider),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.group.effectiveTitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                        color: widget.selected
                            ? AppColors.textBright
                            : _hovered ? AppColors.textBright : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(),
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (ref.watch(availableUpdatesProvider)[widget.group.baseKey]
                  case final update?) ...[
                Tooltip(
                  message: 'Update available: ${fmtVersion(update.version)} on ${update.sourceLabel}',
                  child: const Icon(Icons.arrow_circle_up_rounded,
                      size: 14, color: updateAvailableColor),
                ),
                const SizedBox(width: 6),
              ],
              // Played status dot
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: played ? AppColors.accent : AppColors.textMuted,
                  boxShadow: played
                      ? [
                          BoxShadow(
                              color: AppColors.accentGlow,
                              blurRadius: 6,
                              spreadRadius: 1)
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine() {
    final g = widget.group;
    final dev = g.effectiveDeveloper;
    final versions = g.versions;
    if (versions.isEmpty) return dev.isNotEmpty ? dev : '—';
    final raw = versions.last.versionStr;
    final ver = raw.isEmpty ? '' : fmtVersion(raw);
    if (dev.isNotEmpty && ver.isNotEmpty) return '$dev · $ver';
    if (dev.isNotEmpty) return dev;
    if (ver.isNotEmpty) return ver;
    return '—';
  }
}

class _CoverThumb extends StatelessWidget {
  final GameGroup group;
  final UserData userData;
  final int imageEpoch; // see imageEpochProvider

  const _CoverThumb({
    required this.group,
    required this.userData,
    required this.imageEpoch,
  });

  @override
  Widget build(BuildContext context) {
    final customArt = userData.customArt[group.baseKey];
    final paths = groupCarouselPaths(group, customArt);
    final cover = paths.isEmpty ? null : paths.first;

    return Container(
      width: 40,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.bgHover,
        borderRadius: AppRadius.borderXs,
      ),
      clipBehavior: Clip.hardEdge,
      child: cover != null
          ? Image.file(
              cover,
              key: ValueKey(imageEpoch),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const _NoArtPlaceholder(),
            )
          : const _NoArtPlaceholder(),
    );
  }
}

class _NoArtPlaceholder extends StatelessWidget {
  const _NoArtPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgHover, AppColors.bgActive],
        ),
      ),
    );
  }
}
