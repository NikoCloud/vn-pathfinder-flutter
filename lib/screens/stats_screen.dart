import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/game_status.dart';
import '../models/library_stats.dart';
import '../models/user_data.dart';
import '../providers/library_provider.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/common/kit.dart';
import '../widgets/common/status_menu.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ud = ref.watch(userDataProvider);
    final stats = LibraryStats.from(ref.watch(libraryGroupsProvider), ud);
    if (stats.games == 0) {
      return Center(child: Text('No games in the library yet.', style: AppText.body(color: AppColors.textMuted)));
    }

    final status = [for (final s in GameStatus.values) if ((stats.byStatus[s] ?? 0) > 0) s];
    final peak = status.map((s) => stats.byStatus[s]!).reduce((a, b) => a > b ? a : b);
    final engines = stats.byEngine.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final byStatus = _Panel(
      title: 'By status',
      note: '${stats.games} games',
      child: Column(
        children: [
          for (final s in status)
            _Meter(
              leading: Icon(statusIcon(s), size: 15, color: statusColor(s)),
              label: s.label,
              value: stats.byStatus[s]!,
              peak: peak,
            ),
        ],
      ),
    );
    final byEngine = _Panel(
      title: 'By engine',
      note: '${engines.length} engine${engines.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          for (final e in engines) _Meter(label: e.key, value: e.value, peak: engines.first.value),
        ],
      ),
    );
    final played = _Panel(
      title: 'Most played',
      note: 'All time',
      empty: stats.mostPlayed.isEmpty ? 'Play a game from the app to see it here.' : null,
      child: Column(
        children: [for (final g in stats.mostPlayed.take(5)) _Line(left: g.title, right: fmtTime(g.seconds))],
      ),
    );
    final developers = _Panel(
      title: 'Top developers',
      note: 'By time played',
      empty: stats.topDevelopers.isEmpty ? 'Fetch metadata to see developers here.' : null,
      child: Column(
        children: [
          for (final d in stats.topDevelopers.take(5))
            _Line(
              left: d.developer,
              right: '${d.games} game${d.games == 1 ? '' : 's'}${d.seconds > 0 ? ' · ${fmtTime(d.seconds)}' : ''}',
            ),
        ],
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 860;
      Widget pair(Widget a, Widget b) => columns
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
              ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);

      return ListView(
        padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 18, AppLayout.gutter, 90),
        children: [
          Text('Stats', style: AppText.display(fontSize: 32, height: 1.1, color: AppColors.textBright)),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (i, tile) in [
                ('${stats.games}', 'Games'),
                ('${stats.versions}', 'Versions installed'),
                ('${stats.gamesPlayed}', 'Games played'),
                (stats.totalSeconds > 0 ? fmtTime(stats.totalSeconds) : '0m', 'Time played'),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _Tile(value: tile.$1, label: tile.$2)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _WeeklyChart(sessions: ud.sessions),
          const SizedBox(height: 16),
          pair(byStatus, played),
          const SizedBox(height: 16),
          pair(developers, byEngine),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  final String value;
  final String label;
  const _Tile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return VpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.display(fontSize: 34, height: 40 / 34, color: AppColors.textBright)),
          Text(label, style: AppText.body(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String note;
  final Widget child;
  final String? empty;
  const _Panel({required this.title, required this.note, required this.child, this.empty});

  @override
  Widget build(BuildContext context) {
    return VpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.heading()),
          Text(note, style: AppText.meta(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (empty != null) Text(empty!, style: AppText.body(color: AppColors.textMuted)) else child,
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final Widget? leading;
  final String label;
  final int value;
  final int peak;
  const _Meter({this.leading, required this.label, required this.value, required this.peak});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(color: AppColors.textSecondary))),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (value / peak).clamp(0.01, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(color: AppColors.chart, borderRadius: AppRadius.borderXs),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text('$value', textAlign: TextAlign.right, style: AppText.data(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String left;
  final String right;
  const _Line({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body())),
          const SizedBox(width: 12),
          Text(right, style: AppText.data(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List<PlaySession> sessions;
  const _WeeklyChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final weeks = weeklyPlay(sessions, DateTime.now());
    final hours = [for (final w in weeks) w.seconds / 3600];
    final top = hours.fold<double>(0, (a, b) => a > b ? a : b);
    final ceiling = top <= 0 ? 1.0 : (top / 4).ceil() * 4.0;
    final format = DateFormat('MMM d');

    return _Panel(
      title: 'Play time by week',
      note: 'The last 12 weeks',
      empty: top <= 0 ? 'Sessions you play from the app show up here, starting now. Earlier play time was only kept as totals.' : null,
      child: Semantics(
        label: 'Play time per week over twelve weeks, up to ${top.toStringAsFixed(1)} hours',
        child: SizedBox(
          height: 170,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 32,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${ceiling.round()}h', style: AppText.caption()),
                      Text('${(ceiling / 2).round()}h', style: AppText.caption()),
                      Text('0h', style: AppText.caption()),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < weeks.length; i++)
                      Expanded(
                        child: Tooltip(
                          message: 'Week of ${format.format(weeks[i].start)}: ${weeks[i].seconds == 0 ? 'nothing' : fmtTime(weeks[i].seconds)}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: (hours[i] / ceiling).clamp(0.0, 1.0),
                                    widthFactor: 0.56,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.chart,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(height: 1, color: AppColors.border),
                              SizedBox(
                                height: 19,
                                child: i % 3 == 0
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(format.format(weeks[i].start),
                                            maxLines: 1,
                                            overflow: TextOverflow.visible,
                                            softWrap: false,
                                            style: AppText.caption()),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
