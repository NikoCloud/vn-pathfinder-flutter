import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/feed_images_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shell_provider.dart';
import '../../theme.dart';

/// Every piece of game art in the app goes through this, so Discreet blurs all
/// of it and nothing decodes at more than the size it's shown at.
class GameArt extends ConsumerWidget {
  /// A file on disk, or a web address that the Feed image cache looks after.
  final String? source;
  final BoxFit fit;
  final Alignment alignment;

  /// Decode width in logical pixels. The screen's scale is applied here.
  final int decodeWidth;

  /// Changes when the file behind [source] changes. See imageEpochProvider.
  final int epoch;

  const GameArt({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.decodeWidth = 480,
    this.epoch = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discreet = ref.watch(settingsProvider.select((s) => s.discreet));
    var path = source;
    if (path != null && path.startsWith('http')) {
      path = ref.watch<String?>(feedImageProvider(path));
    }
    final Widget art = path == null || path.isEmpty
        ? const ArtPlaceholder()
        : Image.file(
            File(path),
            key: ValueKey('$path@$epoch'),
            fit: fit,
            alignment: alignment,
            cacheWidth: (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round(),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const ArtPlaceholder(),
          );
    if (!discreet) return art;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.decal),
        child: art,
      ),
    );
  }
}

class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgHover, AppColors.bgCard],
        ),
      ),
      child: Center(child: Icon(Icons.image_outlined, size: 26, color: AppColors.textMuted)),
    );
  }
}

/// The page taking on the colour of the art you're pointing at: the art,
/// heavily blurred, behind everything, fading into the background.
class AmbientLayer extends ConsumerWidget {
  const AmbientLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(ambientArtProvider);
    final discreet = ref.watch(settingsProvider.select((s) => s.discreet));
    var path = source;
    if (path != null && path.startsWith('http')) path = ref.watch<String?>(feedImageProvider(path));
    final show = path != null && path.isNotEmpty && !discreet;
    final strength = AppColors.isDark ? 0.34 : 0.16;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.of(context, const Duration(milliseconds: 800)),
            child: !show
                ? const SizedBox.expand(key: ValueKey('none'))
                : Opacity(
                    key: ValueKey(path),
                    opacity: strength,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix(_saturate),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          cacheWidth: 96,
                          errorBuilder: (context, error, stack) => const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.92],
                colors: [AppColors.bgPrimary.withValues(alpha: 0), AppColors.bgPrimary],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Saturation 1.7 at 82% brightness.
  static const _saturate = <double>[
    1.15, -0.47, -0.05, 0, 0, //
    -0.14, 1.04, -0.05, 0, 0, //
    -0.14, -0.47, 1.43, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
