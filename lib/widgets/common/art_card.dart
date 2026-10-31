import 'package:flutter/material.dart';
import '../../theme.dart';
import 'art.dart';
import 'kit.dart';

/// A 16:9 game card: the art carries it, with chips on the corners, and hover
/// lifts it and reveals [peekText] and [actions]. Feed, Home and Library all
/// use this, so a game looks the same wherever it shows up.
class ArtCard extends StatefulWidget {
  final String? art;
  final int epoch;
  final String title;
  final String subtitle;

  /// Shown at the end of the subtitle line, and never cut off by it.
  final String? time;
  final String? timeTooltip;
  final bool dot;
  final Widget? topLeft;
  final Widget? topRight;
  final String? version;
  final String peekText;
  final List<Widget> actions;
  final VoidCallback onOpen;
  final ValueChanged<bool>? onHover;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool picked;

  /// Selecting several games: the tick replaces the hover details.
  final bool picking;
  final String? semanticLabel;

  const ArtCard({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onOpen,
    this.epoch = 0,
    this.time,
    this.timeTooltip,
    this.dot = false,
    this.topLeft,
    this.topRight,
    this.version,
    this.peekText = '',
    this.actions = const [],
    this.onHover,
    this.onSecondaryTapDown,
    this.picked = false,
    this.picking = false,
    this.semanticLabel,
  });

  /// The height of a card [width] wide.
  static double heightFor(double width) => width * 9 / 16 + 54;

  @override
  State<ArtCard> createState() => _ArtCardState();
}

class _ArtCardState extends State<ArtCard> {
  bool _hovered = false;

  void _setHover(bool v) {
    if (v == _hovered) return;
    setState(() => _hovered = v);
    widget.onHover?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context, const Duration(milliseconds: 160));
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedSlide(
        duration: motion,
        curve: const Cubic(0.2, 0.7, 0.3, 1),
        offset: Offset(0, _hovered ? -0.016 : 0),
        child: AnimatedScale(
          duration: motion,
          curve: const Cubic(0.2, 0.7, 0.3, 1),
          scale: _hovered ? 1.025 : 1,
          child: Pressable(
            onTap: widget.onOpen,
            label: widget.semanticLabel ?? widget.title,
            radius: AppRadius.borderLg,
            selected: widget.picked,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            builder: (context, states) {
              final open = states.contains(WidgetState.focused) || _hovered;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: _face(open, motion)),
                  const SizedBox(height: 9),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(fontSize: 17, height: 1.2, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        if (widget.dot) ...[
                          Tooltip(
                            message: 'New since your last visit',
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(color: AppColors.textMuted),
                          ),
                        ),
                        if (widget.time != null) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: widget.timeTooltip ?? '',
                            child: Text(
                              widget.time!,
                              style: AppText.body(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _face(bool open, Duration motion) {
    return AnimatedContainer(
      duration: motion,
      decoration: BoxDecoration(
        color: AppColors.bgHover,
        borderRadius: AppRadius.borderLg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark ? (_hovered ? 0.6 : 0.35) : (_hovered ? 0.28 : 0.12)),
            blurRadius: _hovered ? 44 : 22,
            offset: Offset(0, _hovered ? 18 : 8),
          ),
          if (widget.picked) BoxShadow(color: AppColors.accent, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderLg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(
              duration: AppMotion.of(context, const Duration(milliseconds: 1400)),
              curve: const Cubic(0.2, 0.7, 0.3, 1),
              scale: _hovered ? 1.05 : 1,
              child: GameArt(source: widget.art, epoch: widget.epoch, decodeWidth: 400),
            ),
            if (widget.topLeft != null) Positioned(left: 8, top: 8, child: widget.topLeft!),
            if (widget.topRight != null)
              Positioned(
                right: 8,
                top: 8,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: widget.topRight!),
              ),
            if (widget.picking)
              Positioned(right: 8, bottom: 8, child: _Tick(on: widget.picked))
            else ...[
              if (widget.version != null && !open)
                Positioned(right: 8, bottom: 8, child: VpBadge(label: widget.version!, mono: true, color: AppColors.onArt)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !open,
                  child: AnimatedOpacity(
                    duration: motion,
                    opacity: open ? 1 : 0,
                    child: AnimatedSlide(
                      duration: motion,
                      offset: Offset(0, open ? 0 : 0.08),
                      child: _Peek(text: widget.peekText, actions: widget.actions),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final bool on;
  const _Tick({required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: on ? AppColors.accent : const Color(0xB3080A0F),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: on ? AppColors.accent : Colors.white, width: 1.5),
      ),
      child: on ? Icon(Icons.check, size: 16, color: AppColors.onAccent) : null,
    );
  }
}

class _Peek extends StatelessWidget {
  final String text;
  final List<Widget> actions;
  const _Peek({required this.text, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 52, 10, 9),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.42],
          colors: [Color(0x0005060A), Color(0xE605060A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text.isNotEmpty) ...[
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.ui(fontSize: 12.5, height: 1.35, color: AppColors.onArtSoft),
            ),
            const SizedBox(height: 7),
          ],
          Row(
            children: [
              if (actions.isNotEmpty) Flexible(child: actions.first),
              const Spacer(),
              for (final a in actions.skip(1)) ...[const SizedBox(width: 6), a],
            ],
          ),
        ],
      ),
    );
  }
}

/// Columns and card width for a card wall [width] wide with cards at least
/// [minWidth] across.
({int columns, double cardWidth}) wallColumns(double width, double minWidth, {double gap = 18}) {
  final columns = ((width + gap) / (minWidth + gap)).floor().clamp(1, 12);
  return (columns: columns, cardWidth: (width - gap * (columns - 1)) / columns);
}

/// The big band at the top of Feed and Home: art that fades into the page,
/// with its text on the left.
class Spotlight extends StatelessWidget {
  final String? art;
  final int epoch;
  final double height;
  final String eyebrow;
  final bool eyebrowNew;
  final String title;
  final String blurb;
  final Widget? versionLine;
  final List<Widget> actions;
  final Widget? trailing;

  const Spotlight({
    super.key,
    required this.art,
    required this.height,
    required this.eyebrow,
    required this.title,
    required this.actions,
    this.epoch = 0,
    this.eyebrowNew = false,
    this.blurb = '',
    this.versionLine,
    this.trailing,
  });

  /// clamp(300px, 44vh, 420px)
  static double heightFor(double viewport) => (viewport * 0.44).clamp(300.0, 420.0);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.05).clamp(38.0, 62.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ArtFade(
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, const Duration(milliseconds: 600)),
              child: SizedBox.expand(
                key: ValueKey(art),
                child: GameArt(source: art, epoch: epoch, decodeWidth: 1280, alignment: const Alignment(0, -0.6)),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: [0, 0.42, 0.72],
                colors: [Color(0xDB06080D), Color(0x7506080D), Color(0x0006080D)],
              ),
            ),
          ),
          Positioned(
            left: AppLayout.gutter,
            bottom: 34,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (width - 56).clamp(0, 620)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(eyebrow,
                      style: AppText.ui(
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: eyebrowNew ? AppColors.newVersion : AppColors.accent,
                      )),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(
                      fontSize: titleSize,
                      height: 1.02,
                      letterSpacing: titleSize * -0.015,
                      color: AppColors.onArt,
                      shadows: const [Shadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 2))],
                    ),
                  ),
                  if (blurb.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.reading(fontSize: 17, height: 1.45, color: AppColors.onArtSoft),
                    ),
                  ],
                  if (versionLine != null) ...[const SizedBox(height: 10), versionLine!],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
            ),
          ),
          if (trailing != null) Positioned(right: AppLayout.gutter, bottom: 26, child: trailing!),
        ],
      ),
    );
  }
}

/// Fades art out into whatever is behind it, so a hero has no hard bottom edge.
class ArtFade extends StatelessWidget {
  final Widget child;
  final double from;
  const ArtFade({super.key, required this.child, this.from = 0.66});

  @override
  Widget build(BuildContext context) {
    if (!AppColors.isDark) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [from, 1],
        colors: const [Color(0xFF000000), Color(0x00000000)],
      ).createShader(rect),
      child: child,
    );
  }
}
