import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/version_path.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/kit.dart';

/// A game's versions as a route: solid up to what you have, dashed from there
/// to the latest. Press a stop to read what changed in that version.
class VersionPathView extends StatelessWidget {
  final List<PathNode> nodes;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool newer;

  const VersionPathView({
    super.key,
    required this.nodes,
    required this.selected,
    required this.onSelect,
    required this.newer,
  });

  static const _trackHeight = 132.0;

  double _xFraction(int i) {
    final n = nodes.length;
    if (n == 1) return 0.5;
    final pad = n < 3 ? 0.22 : 0.09;
    return pad + i * (1 - pad * 2) / (n - 1);
  }

  double _y(int i) => 32 + math.sin(i * 1.5 + 0.6) * 18;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _trackHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final points = [for (var i = 0; i < nodes.length; i++) Offset(_xFraction(i) * width, _y(i))];
        var lastHave = -1;
        for (var i = 0; i < nodes.length; i++) {
          if (nodes[i].installed) lastHave = i;
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RoutePainter(
                  points: points,
                  lastHave: lastHave,
                  solid: AppColors.accent,
                  // Amber is too pale to read as a thin line on Paperback.
                  dashed: !newer
                      ? AppColors.textMuted
                      : AppColors.isDark
                          ? AppColors.newVersion
                          : AppColors.statusOnHold,
                ),
              ),
            ),
            for (var i = 0; i < nodes.length; i++)
              Positioned(
                left: points[i].dx - 50,
                top: points[i].dy - 8,
                width: 100,
                child: _Stop(
                  node: nodes[i],
                  selected: sameVersion(nodes[i].version, selected),
                  newer: newer,
                  onTap: () => onSelect(nodes[i].version),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _Stop extends StatelessWidget {
  final PathNode node;
  final bool selected;
  final bool newer;
  final VoidCallback onTap;
  const _Stop({required this.node, required this.selected, required this.newer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final latestMissing = node.latest && !node.installed && newer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Pressable(
              onTap: onTap,
              label: fmtVersion(node.version),
              selected: selected,
              radius: const BorderRadius.all(Radius.circular(9)),
              builder: (context, states) => AnimatedScale(
                duration: AppMotion.of(context, AppMotion.hover),
                scale: states.contains(WidgetState.hovered) ? 1.2 : 1,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: node.installed ? AppColors.accent : AppColors.bgPrimary,
                    border: Border.all(
                      width: 2.5,
                      color: node.installed
                          ? AppColors.accent
                          : latestMissing
                              ? AppColors.newVersion
                              : AppColors.textMuted,
                    ),
                    boxShadow: [
                      if (latestMissing)
                        BoxShadow(color: AppColors.newVersion.withValues(alpha: 0.22), spreadRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
            if (node.here)
              Positioned(
                bottom: 21,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.borderXs),
                  child: Text('You are here',
                      maxLines: 1,
                      style: AppText.ui(fontSize: 11, height: 1, fontWeight: FontWeight.w600, color: AppColors.onAccent)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          fmtVersion(node.version),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.mono(
            fontSize: 13,
            height: 1,
            fontWeight: FontWeight.w500,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ).copyWith(
            decoration: selected ? TextDecoration.underline : null,
            decorationColor: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Offset> points;
  final int lastHave;
  final Color solid;
  final Color dashed;

  _RoutePainter({required this.points, required this.lastHave, required this.solid, required this.dashed});

  Path _segment(int from, int to) {
    final path = Path()..moveTo(points[from].dx, points[from].dy);
    for (var i = from; i < to; i++) {
      final a = points[i], b = points[i + 1];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (lastHave > 0) canvas.drawPath(_segment(0, lastHave), paint..color = solid);
    final start = math.max(0, lastHave);
    if (start < points.length - 1) {
      paint.color = dashed;
      final path = _segment(start, points.length - 1);
      for (final ui.PathMetric metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 14) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 7, metric.length)), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.points != points || old.lastHave != lastHave || old.solid != solid || old.dashed != dashed;
}
