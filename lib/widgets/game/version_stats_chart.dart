import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/version_stats.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';

/// What the chart shows (#44).
enum StatsMetric {
  renders('Renders'),
  animations('Animations'),
  words('Words'),
  audio('Audio'),
  size('Size');

  final String label;
  const StatsMetric(this.label);

  /// The value for [s], or null when it isn't known (words from scripts that
  /// couldn't be read).
  int? of(VersionStats s) => switch (this) {
        renders => s.renders,
        animations => s.animations,
        words => s.words,
        audio => s.audio,
        size => s.bytes > 0 ? s.bytes : null,
      };

  String format(int v) => this == size ? fmtBytes(v.abs()) : fmtCount(v.abs());
}

/// 12,345.
String fmtCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// One point: a version and its value, with the change from the one before.
class _Point {
  final String version;
  final int value;
  final int? change;
  final DateTime? builtAt;
  const _Point(this.version, this.value, this.change, this.builtAt);
}

/// The counts across versions: a line of totals, or bars of what each update
/// added or took away. Hover a version for its figures.
class VersionStatsChart extends StatefulWidget {
  final List<(String, VersionStats)> history;
  final StatsMetric metric;
  final bool perUpdate;

  const VersionStatsChart({super.key, required this.history, required this.metric, required this.perUpdate});

  @override
  State<VersionStatsChart> createState() => _VersionStatsChartState();
}

class _VersionStatsChartState extends State<VersionStatsChart> {
  int? _hover;

  List<_Point> get _points {
    final out = <_Point>[];
    int? before;
    for (final (version, s) in widget.history) {
      final v = widget.metric.of(s);
      if (v == null) {
        before = null;
        continue;
      }
      out.add(_Point(version, v, before == null ? null : v - before, s.builtAt));
      before = v;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final all = _points;
    final points = widget.perUpdate ? all.where((p) => p.change != null).toList() : all;
    if (points.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(child: Text('Not counted for these versions.', style: AppText.body(color: AppColors.textMuted))),
      );
    }
    return SizedBox(
      height: 240,
      child: LayoutBuilder(builder: (context, c) {
        final layout = _Layout(Size(c.maxWidth, 240), points, widget.perUpdate);
        return MouseRegion(
          onHover: (e) => setState(() => _hover = layout.nearest(e.localPosition.dx)),
          onExit: (_) => setState(() => _hover = null),
          child: CustomPaint(
            size: Size(c.maxWidth, 240),
            painter: _ChartPainter(
              layout: layout,
              metric: widget.metric,
              perUpdate: widget.perUpdate,
              hover: _hover != null && _hover! < points.length ? _hover : null,
              text: AppText.ui(fontSize: 11.5, color: AppColors.textMuted),
              tipText: AppText.ui(fontSize: 12.5, color: AppColors.textPrimary),
              tipMuted: AppText.ui(fontSize: 11.5, color: AppColors.textSecondary),
              mono: AppText.mono(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        );
      }),
    );
  }
}

/// Where everything goes, shared by painting and hit-testing.
class _Layout {
  final Size size;
  final List<_Point> points;
  final bool perUpdate;
  static const left = 64.0, right = 16.0, top = 14.0, bottom = 30.0;

  late final double lo, hi, step;

  _Layout(this.size, this.points, this.perUpdate) {
    final values = [for (final p in points) perUpdate ? p.change! : p.value];
    var minV = math.min(0, values.reduce(math.min)).toDouble();
    var maxV = math.max(0, values.reduce(math.max)).toDouble();
    if (maxV == minV) maxV = minV + 1;
    step = _niceStep((maxV - minV) / 4);
    lo = (minV / step).floor() * step;
    hi = (maxV / step).ceil() * step;
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10;
    return math.max(1, nice * mag);
  }

  Rect get plot => Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

  /// Versions sit evenly across: a version is the unit that matters here.
  double x(int i) {
    final r = plot;
    if (points.length == 1) return r.center.dx;
    final inset = perUpdate ? r.width / points.length / 2 : 10.0;
    return r.left + inset + (r.width - inset * 2) * i / (points.length - 1);
  }

  double y(num v) {
    final r = plot;
    return r.bottom - (v - lo) / (hi - lo) * r.height;
  }

  int nearest(double dx) {
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if ((x(i) - dx).abs() < (x(best) - dx).abs()) best = i;
    }
    return best;
  }
}

class _ChartPainter extends CustomPainter {
  final _Layout layout;
  final StatsMetric metric;
  final bool perUpdate;
  final int? hover;
  final TextStyle text, tipText, tipMuted, mono;

  _ChartPainter({
    required this.layout,
    required this.metric,
    required this.perUpdate,
    required this.hover,
    required this.text,
    required this.tipText,
    required this.tipMuted,
    required this.mono,
  });

  TextPainter _label(String s, TextStyle style, {double maxWidth = 200}) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')
        ..layout(maxWidth: maxWidth);

  String _axis(double v) {
    if (metric == StatsMetric.size) return fmtBytes(v.round().abs());
    final a = v.abs();
    final s = a >= 1e6 ? '${(a / 1e6).toStringAsFixed(a % 1e6 == 0 ? 0 : 1)}M' : a >= 1e4 ? '${(a / 1e3).round()}k' : fmtCount(a.round());
    return v < 0 ? '-$s' : s;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final r = l.plot;
    final points = l.points;
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    // Grid and the value axis: quiet, so the data reads first.
    for (var v = l.lo; v <= l.hi + l.step / 2; v += l.step) {
      final y = l.y(v);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      final t = _label(_axis(v), text, maxWidth: _Layout.left - 10);
      t.paint(canvas, Offset(r.left - 10 - t.width, y - t.height / 2));
    }
    if (l.lo < 0) {
      canvas.drawLine(Offset(r.left, l.y(0)), Offset(r.right, l.y(0)), Paint()
        ..color = AppColors.textMuted
        ..strokeWidth = 1);
    }

    // Version labels, thinned out so they never run together.
    var lastRight = -double.infinity;
    for (var i = 0; i < points.length; i++) {
      final t = _label(fmtVersion(points[i].version), mono, maxWidth: 110);
      final left = l.x(i) - t.width / 2;
      if (left < lastRight + 10 && i != hover) continue;
      t.paint(canvas, Offset(left.clamp(0, size.width - t.width), r.bottom + 9));
      lastRight = left + t.width;
    }

    final color = AppColors.chart;
    if (perUpdate) {
      final slot = r.width / points.length;
      final w = math.min(28.0, slot * 0.55);
      for (var i = 0; i < points.length; i++) {
        final v = points[i].change!;
        if (v == 0) continue;
        final top = l.y(math.max(v, 0)), bottom = l.y(math.min(v, 0));
        final rect = Rect.fromLTRB(l.x(i) - w / 2, top, l.x(i) + w / 2, bottom);
        const round = Radius.circular(4);
        final rr = v > 0
            ? RRect.fromRectAndCorners(rect, topLeft: round, topRight: round)
            : RRect.fromRectAndCorners(rect, bottomLeft: round, bottomRight: round);
        // Removals in a neutral grey: they're worth noticing, not alarming.
        canvas.drawRRect(rr, Paint()..color = v > 0 ? color : AppColors.textMuted.withValues(alpha: 0.75));
      }
    } else {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final o = Offset(l.x(i), l.y(points[i].value));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      final area = Path.from(path)
        ..lineTo(l.x(points.length - 1), l.y(math.max(l.lo, 0)))
        ..lineTo(l.x(0), l.y(math.max(l.lo, 0)))
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
          ).createShader(r),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < points.length; i++) {
        final o = Offset(l.x(i), l.y(points[i].value));
        canvas.drawCircle(o, i == hover ? 6 : 4.5, Paint()..color = AppColors.bgPrimary);
        canvas.drawCircle(o, i == hover ? 4.5 : 3, Paint()..color = color);
      }
    }

    final h = hover;
    if (h != null) _tip(canvas, size, h);
  }

  void _tip(Canvas canvas, Size size, int i) {
    final l = layout;
    final p = l.points[i];
    final x = l.x(i);
    canvas.drawLine(Offset(x, l.plot.top), Offset(x, l.plot.bottom), Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.4)
      ..strokeWidth = 1);

    final c = p.change;
    final lines = <(String, TextStyle)>[
      (fmtVersion(p.version), tipText.copyWith(fontWeight: FontWeight.w600)),
      ('${metric.label}: ${metric.format(p.value)}', tipText),
      if (c != null) ('${c >= 0 ? '+' : '-'}${metric.format(c)} from the version before', tipMuted),
      if (p.builtAt != null) ('Built ${releaseDate(p.builtAt!)}', tipMuted),
    ];
    final painters = [for (final (s, st) in lines) _label(s, st, maxWidth: 260)];
    final w = painters.map((t) => t.width).reduce(math.max) + 20;
    final hgt = painters.fold<double>(0, (a, t) => a + t.height + 3) + 14;
    var left = x + 12;
    if (left + w > size.width) left = x - 12 - w;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, l.plot.top, w, hgt), const Radius.circular(8));
    canvas.drawRRect(box, Paint()..color = AppColors.bgCard);
    canvas.drawRRect(box, Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke);
    var y = l.plot.top + 8;
    for (final t in painters) {
      t.paint(canvas, Offset(left + 10, y));
      y += t.height + 3;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.hover != hover || old.metric != metric || old.perUpdate != perUpdate || old.layout.points != layout.points;
}

/// "14 Mar 2026".
String releaseDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// "3 weeks", "5 months", "2.3 years".
String spanText(Duration d) {
  final days = d.inDays;
  if (days < 14) return '$days day${days == 1 ? '' : 's'}';
  if (days < 60) return '${(days / 7).round()} weeks';
  if (days < 730) return '${(days / 30.4).round()} months';
  return '${(days / 365.25).toStringAsFixed(1)} years';
}
