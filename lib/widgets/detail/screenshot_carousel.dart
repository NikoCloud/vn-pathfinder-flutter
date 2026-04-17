import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme.dart';

class ScreenshotCarousel extends StatefulWidget {
  final List<File> images;
  final double intervalSeconds;
  final ValueChanged<File>? onImageTap; // opens lightbox

  const ScreenshotCarousel({
    super.key,
    required this.images,
    this.intervalSeconds = 5.0,
    this.onImageTap,
  });

  @override
  State<ScreenshotCarousel> createState() => _ScreenshotCarouselState();
}

class _ScreenshotCarouselState extends State<ScreenshotCarousel> {
  int _current = 0;
  Timer? _timer;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(ScreenshotCarousel old) {
    super.didUpdateWidget(old);
    if (old.images != widget.images) {
      _current = 0;
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (widget.images.length <= 1) return;
    _timer = Timer.periodic(
      Duration(milliseconds: (widget.intervalSeconds * 1000).round()),
      (_) {
        if (!_hovering && mounted) {
          setState(() => _current = (_current + 1) % widget.images.length);
        }
      },
    );
  }

  void _restartTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _prev() {
    setState(() {
      _current =
          (_current - 1 + widget.images.length) % widget.images.length;
    });
    _restartTimer();
  }

  void _next() {
    setState(() => _current = (_current + 1) % widget.images.length);
    _restartTimer();
  }

  void _goTo(int i) {
    setState(() => _current = i);
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Slides
          _CarouselSlides(
            images: widget.images,
            current: _current,
            onTap: widget.onImageTap != null
                ? () => widget.onImageTap!(widget.images[_current])
                : null,
          ),

          // Prev arrow
          if (widget.images.length > 1)
            Positioned(
              left: -16,
              child: AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _NavArrow(
                    icon: Icons.chevron_left, onTap: _prev),
              ),
            ),

          // Next arrow
          if (widget.images.length > 1)
            Positioned(
              right: -16,
              child: AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _NavArrow(
                    icon: Icons.chevron_right, onTap: _next),
              ),
            ),

          // Dots
          if (widget.images.length > 1)
            Positioned(
              bottom: -20,
              child: _Dots(
                count: widget.images.length,
                current: _current,
                onTap: _goTo,
              ),
            ),
        ],
      ),
    );
  }
}

class _CarouselSlides extends StatelessWidget {
  final List<File> images;
  final int current;
  final VoidCallback? onTap;

  const _CarouselSlides({
    required this.images,
    required this.current,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(images.length, (i) {
          final isPrev = i == (current - 1 + images.length) % images.length;
          final isNext = i == (current + 1) % images.length;
          final isActive = i == current;

          double scale;
          double translateX;
          double opacity;

          if (isActive) {
            scale = 1.0;
            translateX = 0;
            opacity = 1.0;
          } else if (isPrev) {
            scale = 0.78;
            translateX = -0.75;
            opacity = 0.4;
          } else if (isNext) {
            scale = 0.78;
            translateX = 0.75;
            opacity = 0.4;
          } else {
            scale = 0.85;
            translateX = 0;
            opacity = 0.0;
          }

          return AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: opacity,
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: FractionalTranslation(
                  translation: Offset(translateX, 0),
                  child: GestureDetector(
                    onTap: isActive ? onTap : null,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.borderMd,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 40,
                                    spreadRadius: 8)
                              ]
                            : null,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Image.file(
                        images[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stack) => Container(
                          color: AppColors.bgCard,
                          child: const Icon(Icons.broken_image_outlined,
                              color: AppColors.textMuted, size: 32),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  State<_NavArrow> createState() => _NavArrowState();
}

class _NavArrowState extends State<_NavArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accent : const Color(0xE014171C),
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(widget.icon,
              size: 18,
              color: _hovered ? Colors.white : AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  final ValueChanged<int> onTap;

  const _Dots({required this.count, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == current;
        return GestureDetector(
          onTap: () => onTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 8 : 6,
            height: active ? 8 : 6,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        );
      }),
    );
  }
}
