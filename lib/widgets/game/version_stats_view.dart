import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_group.dart';
import '../../models/version_stats.dart';
import '../../providers/library_provider.dart';
import '../../providers/version_stats_provider.dart';
import '../../services/game_detect.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/kit.dart';
import 'version_stats_chart.dart';

/// Whether [g] has anything this section can show: a Ren'Py version
/// installed, or counts kept from one.
bool showsVersionStats(GameGroup g, Map<String, VersionStats>? kept) =>
    (kept?.isNotEmpty ?? false) || g.versions.any((v) => v.engine == GameEngine.renpy);

/// The game page's "What's in it" (#44): renders, animations, words, audio
/// and size for each version counted, with what changed from the version
/// before. Counting runs in the background the first time a version is shown.
class VersionStatsView extends ConsumerStatefulWidget {
  final GameGroup group;
  const VersionStatsView({super.key, required this.group});

  @override
  ConsumerState<VersionStatsView> createState() => _VersionStatsViewState();
}

class _VersionStatsViewState extends ConsumerState<VersionStatsView> {
  var _metric = StatsMetric.renders;
  var _perUpdate = false;

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void didUpdateWidget(VersionStatsView old) {
    super.didUpdateWidget(old);
    if (old.group != widget.group) _count();
  }

  void _count() {
    final ud = ref.read(userDataProvider.notifier);
    final g = widget.group;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) countVersions(ud, g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final history = statsHistory(ref.watch(userDataProvider.select((u) => u.versionStats[g.baseKey])));
    if (history.isEmpty) {
      return Text('Counting what this version holds…', style: AppText.body(color: AppColors.textMuted));
    }
    final installed = {for (final v in g.versions) v.versionStr};
    final unreadable = history.any((h) => h.$2.unreadableArchives > 0);
    final allEmpty = history.every((h) => h.$2.empty);

    if (allEmpty) {
      return Text(
        "This game keeps its files in a format the app can't open, so there's nothing to count.",
        style: AppText.body(color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A chart once there are two versions to compare; one is just the table.
        if (history.length >= 2) ...[
          Wrap(
            spacing: 2,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final m in StatsMetric.values)
                VpShelf(label: m.label, selected: m == _metric, onTap: () => setState(() => _metric = m)),
              const SizedBox(width: 12),
              VpSegmented<bool>(
                value: _perUpdate,
                options: const [
                  (false, Icons.show_chart, 'Total in each version'),
                  (true, Icons.bar_chart, 'What each update added or removed'),
                ],
                onChanged: (v) => setState(() => _perUpdate = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final chart = VersionStatsChart(history: history, metric: _metric, perUpdate: _perUpdate);
            final insights = _Insights(history: history, metric: _metric);
            if (c.maxWidth < 640) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [chart, const SizedBox(height: 14), insights]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: chart), const SizedBox(width: 20), SizedBox(width: 220, child: insights)],
            );
          }),
          const SizedBox(height: 18),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                for (final h in const ['Version', 'Renders', 'Animations', 'Words', 'Audio', 'Size']) _Head(h),
              ]),
              for (final (i, (version, s)) in history.indexed)
                _row(version, s, i == 0 ? null : history[i - 1].$2, removed: !installed.contains(version)),
            ],
          ),
        ),
        if (unreadable) ...[
          const SizedBox(height: 8),
          Text(
            "Some of the game's archives are in the developer's own format, so what's in them isn't counted.",
            style: AppText.ui(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  TableRow _row(String version, VersionStats s, VersionStats? before, {required bool removed}) {
    return TableRow(children: [
      _Cell(
        version.isEmpty ? '—' : fmtVersion(version),
        note: removed ? 'removed' : null,
        mono: true,
      ),
      _Cell(_n(s.renders), change: before == null ? null : s.renders - before.renders),
      _Cell(_n(s.animations), change: before == null ? null : s.animations - before.animations),
      _Cell(
        s.words == null ? '—' : _n(s.words!),
        change: before == null || s.words == null || before.words == null ? null : s.words! - before.words!,
      ),
      _Cell(
        s.music > 0 ? '${_n(s.audio)} (${_n(s.music)} music)' : _n(s.audio),
        change: before == null ? null : s.audio - before.audio,
      ),
      _Cell(s.bytes > 0 ? fmtBytes(s.bytes) : '—'),
    ]);
  }
}

/// 12,345.
String _n(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 22, bottom: 6),
        child: Text(text, style: AppText.ui(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      );
}

class _Cell extends StatelessWidget {
  final String text;
  final int? change;
  final String? note;
  final bool mono;
  const _Cell(this.text, {this.change, this.note, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final c = change;
    return Padding(
      padding: const EdgeInsets.only(right: 22, top: 4, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text, style: (mono ? AppText.mono(fontSize: 13) : AppText.ui(fontSize: 13.5)).copyWith(color: AppColors.textPrimary)),
          if (c != null && c != 0) ...[
            const SizedBox(width: 6),
            Text(c > 0 ? '+${_n(c)}' : _n(c), style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
          ],
          if (note != null) ...[
            const SizedBox(width: 6),
            Text(note!, style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// A few figures worked out from the counts, for the metric shown.
class _Insights extends StatelessWidget {
  final List<(String, VersionStats)> history;
  final StatsMetric metric;
  const _Insights({required this.history, required this.metric});

  @override
  Widget build(BuildContext context) {
    final known = [for (final (v, s) in history) if (metric.of(s) != null) (v, metric.of(s)!, s.builtAt)];
    final built = [for (final (_, s) in history) ?s.builtAt]..sort();
    final changes = [for (var i = 1; i < known.length; i++) (known[i].$1, known[i].$2 - known[i - 1].$2)];
    final biggest = changes.isEmpty ? null : changes.reduce((a, b) => b.$2 > a.$2 ? b : a);
    final drops = changes.where((c) => c.$2 < 0).length;
    String signed(int v) => '${v >= 0 ? '+' : '-'}${metric.format(v)}';

    final rows = <(String, String)>[
      ('Versions counted', '${history.length}'),
      if (built.length >= 2) ('Time between first and last', spanText(built.last.difference(built.first))),
      if (changes.isNotEmpty)
        ('Average per update', signed(((known.last.$2 - known.first.$2) / changes.length).round())),
      if (biggest != null && biggest.$2 > 0) ('Biggest update', '${fmtVersion(biggest.$1)}, ${signed(biggest.$2)}'),
      if (drops > 0) ('Updates that removed some', '$drops'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.8),
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${metric.label} at a glance', style: AppText.ui(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.ui(fontSize: 11.5, color: AppColors.textMuted)),
                  const SizedBox(height: 1),
                  Text(value, style: AppText.ui(fontSize: 13.5, color: AppColors.textPrimary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
