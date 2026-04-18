import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../providers/settings_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../services/scanner_service.dart';
import 'screenshot_carousel.dart';
import 'screenshot_lightbox.dart';

class HeroBanner extends ConsumerWidget {
  final GameGroup group;
  final UserData userData;
  final VoidCallback? onPlay;
  final VoidCallback? onProperties;
  final ValueChanged<String>? onVersionChanged;

  const HeroBanner({
    super.key,
    required this.group,
    required this.userData,
    this.onPlay,
    this.onProperties,
    this.onVersionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customArt = userData.customArt[group.baseKey];
    final images = groupCarouselPaths(group, customArt);
    final cover = images.isEmpty ? null : images.first;
    final interval = ref.watch(settingsProvider).slideshowInterval;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dynamically scale the banner height on larger screens:
        // Allows the carousel bounding box (and images) to grow naturally
        // while preserving aspect ratio margins and avoiding text overlaps.
        final dynamicHeight = (constraints.maxWidth * 0.40).clamp(400.0, 750.0);

        return SizedBox(
          height: dynamicHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred background
              _BlurredBackground(image: cover),

              // Clickable background area
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (images.isNotEmpty) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          opaque: false,
                          barrierColor: Colors.transparent,
                          pageBuilder: (context, animation, secondaryAnimation) => ScreenshotLightbox(
                            paths: images.map((f) => f.path).toList(),
                            initialIndex: 0,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

              // Gradient overlay (bottom-heavy)
              const _GradientOverlay(),

              // Screenshot carousel — positioned securely above the bottom text
              Positioned(
                top: 12,
                bottom: 110, // give space so it never hits the HeroContent text
                left: 0,
                right: 0,
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      // innerConstraints.maxHeight is the real remaining vertical space.
                      // We need to reserve 24px for the dots at the bottom.
                      final safeH = innerConstraints.maxHeight - 24;
                      const ratio = 16.0 / 9.0;
                      // target width is 65% up to a maximum constrained by safe height
                      final maxW = (innerConstraints.maxWidth * 0.65).clamp(0.0, safeH * ratio);
                      
                      return SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: ScreenshotCarousel(
                          images: images,
                          intervalSeconds: interval,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Bottom content: title/dev (left) + version selector + play (right)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _HeroContent(
                  group: group,
                  userData: userData,
                  onPlay: onPlay,
                  onProperties: onProperties,
                  onVersionChanged: onVersionChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlurredBackground extends StatelessWidget {
  final File? image;
  const _BlurredBackground({this.image});

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return Container(color: AppColors.bgCard);
    }
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(image!),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.5),
              BlendMode.darken,
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
          ),
          child: BackdropFilter(
            filter: _blurFilter,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  static final _blurFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12);
}

class _GradientOverlay extends StatelessWidget {
  const _GradientOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.45, 0.7, 0.9, 1.0],
          colors: [
            Colors.transparent,
            Color(0x4C1E2128),
            Color(0xB31E2128),
            Color(0xF21E2128),
            AppColors.bgCard,
          ],
        ),
      ),
    );
  }
}

class _HeroContent extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  final VoidCallback? onPlay;
  final VoidCallback? onProperties;
  final ValueChanged<String>? onVersionChanged;

  const _HeroContent({
    required this.group,
    required this.userData,
    this.onPlay,
    this.onProperties,
    this.onVersionChanged,
  });

  @override
  ConsumerState<_HeroContent> createState() => _HeroContentState();
}

class _HeroContentState extends ConsumerState<_HeroContent> {
  late String _selectedVersion;

  @override
  void initState() {
    super.initState();
    _selectedVersion = widget.group.latestVersion?.versionStr ?? '';
  }

  @override
  void didUpdateWidget(_HeroContent old) {
    super.didUpdateWidget(old);
    if (old.group.baseKey != widget.group.baseKey) {
      _selectedVersion = widget.group.latestVersion?.versionStr ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final versions = g.versions;
    final tracker = ref.watch(playTrackerProvider);
    final isThisRunning = tracker.runningBaseKey == g.baseKey;
    final elapsed = isThisRunning ? tracker.elapsedSeconds : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0xFA1E2128),
            AppColors.bgCard,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Title + developer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.effectiveTitle,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    shadows: [
                      const Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 12,
                          color: Color(0xB3000000)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (g.effectiveDeveloper.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    g.effectiveDeveloper,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accentSilver,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),

          // Version selector + play controls
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Version selector (only shown if multiple versions)
              if (versions.length > 1)
                _VersionSelector(
                  versions: versions.map((v) => v.versionStr).toList(),
                  selected: _selectedVersion,
                  onChanged: (v) {
                    setState(() => _selectedVersion = v);
                    widget.onVersionChanged?.call(v);
                  },
                ),
              if (versions.length > 1) const SizedBox(height: 8),

              // Play + Properties
              Row(
                children: [
                  _PlayButton(
                    onTap: widget.onPlay,
                    isRunning: isThisRunning,
                    elapsedSeconds: elapsed,
                  ),
                  const SizedBox(width: 6),
                  _PropertiesButton(onTap: widget.onProperties),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionSelector extends StatelessWidget {
  final List<String> versions;
  final String selected;
  final ValueChanged<String> onChanged;

  const _VersionSelector({
    required this.versions,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: AppRadius.borderSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected.isEmpty ? null : selected,
          isDense: true,
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          dropdownColor: AppColors.bgCard,
          icon: const Icon(Icons.expand_more, size: 14, color: AppColors.textSecondary),
          items: versions.map((v) => DropdownMenuItem(
            value: v,
            child: Text(v.isEmpty ? 'Unknown' : 'v$v'),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isRunning;
  final int elapsedSeconds;

  const _PlayButton({
    this.onTap,
    this.isRunning = false,
    this.elapsedSeconds = 0,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hovered = false;

  String _fmtElapsed(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.isRunning;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: running ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: running ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            gradient: running
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _hovered
                        ? [AppColors.playGreenHover, AppColors.playGreen]
                        : [AppColors.playGreen, const Color(0xFF4C8C24)],
                  ),
            color: running ? AppColors.bgActive : null,
            borderRadius: AppRadius.borderMd,
            border: running
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
                : null,
            boxShadow: running
                ? null
                : [
                    BoxShadow(
                      color: AppColors.playGreen
                          .withValues(alpha: _hovered ? 0.5 : 0.35),
                      blurRadius: _hovered ? 28 : 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: running
                ? [
                    // Pulsing dot
                    _RunningDot(),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RUNNING',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.accentLight,
                          ),
                        ),
                        Text(
                          _fmtElapsed(widget.elapsedSeconds),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ]
                : [
                    const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      'PLAY',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _RunningDot extends StatefulWidget {
  @override
  State<_RunningDot> createState() => _RunningDotState();
}

class _RunningDotState extends State<_RunningDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.6),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertiesButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _PropertiesButton({this.onTap});

  @override
  State<_PropertiesButton> createState() => _PropertiesButtonState();
}

class _PropertiesButtonState extends State<_PropertiesButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Game Properties',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0x1A4A9E6E)
                  : AppColors.bgSecondary,
              border: Border.all(
                color: _hovered ? AppColors.accent : AppColors.borderLight,
              ),
              borderRadius: AppRadius.borderMd,
            ),
            child: Icon(
              Icons.settings_outlined,
              size: 18,
              color: _hovered ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
