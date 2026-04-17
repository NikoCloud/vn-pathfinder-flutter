import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../services/scanner_service.dart';

class GameEntry extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRightClick;

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
    final played = _isPlayed();

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
        onSecondaryTap: widget.onRightClick,
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
              _CoverThumb(group: widget.group, userData: widget.userData),
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
                        fontWeight: FontWeight.w500,
                        color: widget.selected
                            ? AppColors.accentLight
                            : AppColors.textPrimary,
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

  bool _isPlayed() {
    final g = widget.group;
    final ud = widget.userData;
    for (final v in g.versions) {
      final fn = v.folderName;
      if (ud.manualUnplayed.contains(fn)) return false;
      if (ud.manualPlayed.contains(fn)) return true;
      if (v.localSaveDir.existsSync()) {
        try {
          if (v.localSaveDir.listSync().isNotEmpty) { return true; }
        } catch (_) {}
      }
      if (v.appdataSaveDir != null && v.appdataSaveDir!.existsSync()) {
        try {
          if (v.appdataSaveDir!.listSync().whereType<File>().any(
                (f) => f.path.endsWith('.save') ||
                    f.uri.pathSegments.last == 'persistent',
              )) {
            return true;
          }
        } catch (_) {}
      }
    }
    return false;
  }

  String _metaLine() {
    final g = widget.group;
    final dev = g.effectiveDeveloper;
    final versions = g.versions;
    if (versions.isEmpty) return dev.isNotEmpty ? dev : '—';
    final ver = versions.last.versionStr;
    if (dev.isNotEmpty && ver.isNotEmpty) return '$dev · $ver';
    if (dev.isNotEmpty) return dev;
    if (ver.isNotEmpty) return ver;
    return '—';
  }
}

class _CoverThumb extends StatelessWidget {
  final GameGroup group;
  final UserData userData;

  const _CoverThumb({required this.group, required this.userData});

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
