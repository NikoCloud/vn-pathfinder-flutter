import 'game_group.dart';
import 'game_status.dart';
import 'user_data.dart';

/// One week of play: Monday's date and the seconds played.
typedef PlayWeek = ({DateTime start, int seconds});

/// The last [weeks] weeks, oldest first, including weeks with no play.
List<PlayWeek> weeklyPlay(Iterable<PlaySession> sessions, DateTime now, {int weeks = 12}) {
  final today = DateTime(now.year, now.month, now.day);
  final thisWeek = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  DateTime weekAt(int back) => DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * back);
  final totals = List.filled(weeks, 0);
  for (final s in sessions) {
    final at = s.at.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    if (day.isBefore(weekAt(weeks - 1))) continue;
    final back = (thisWeek.difference(DateTime(day.year, day.month, day.day - (day.weekday - 1))).inHours / (24 * 7)).round();
    if (back >= 0 && back < weeks) totals[weeks - 1 - back] += s.seconds;
  }
  return [for (var i = 0; i < weeks; i++) (start: weekAt(weeks - 1 - i), seconds: totals[i])];
}

/// Totals for the Stats tab.
class LibraryStats {
  final int games;
  final int versions;
  final int gamesPlayed;
  final int totalSeconds;
  final Map<GameStatus, int> byStatus;
  final Map<String, int> byEngine;
  final List<({String title, int seconds})> mostPlayed;
  final List<({String developer, int games, int seconds})> topDevelopers;

  const LibraryStats({
    required this.games,
    required this.versions,
    required this.gamesPlayed,
    required this.totalSeconds,
    required this.byStatus,
    required this.byEngine,
    required this.mostPlayed,
    required this.topDevelopers,
  });

  /// Counts [groups], skipping archive-only entries and hidden games.
  factory LibraryStats.from(Iterable<GameGroup> groups, UserData ud, {int top = 10}) {
    final installed =
        groups.where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey)).toList();
    final byStatus = <GameStatus, int>{};
    final byEngine = <String, int>{};
    final devGames = <String, int>{};
    final devSeconds = <String, int>{};
    final played = <({String title, int seconds})>[];
    var total = 0;
    var versions = 0;
    var gamesPlayed = 0;

    for (final g in installed) {
      versions += g.versions.length;
      final status = effectiveGameStatus(g, ud);
      byStatus[status] = (byStatus[status] ?? 0) + 1;
      if (isGamePlayed(g, ud)) gamesPlayed++;

      final engine = _engineName(g);
      byEngine[engine] = (byEngine[engine] ?? 0) + 1;

      final seconds = ud.playtime[g.baseKey] ?? 0;
      total += seconds;
      if (seconds > 0) played.add((title: g.effectiveTitle, seconds: seconds));

      final developer = g.effectiveDeveloper;
      if (developer.isNotEmpty) {
        devGames[developer] = (devGames[developer] ?? 0) + 1;
        devSeconds[developer] = (devSeconds[developer] ?? 0) + seconds;
      }
    }

    played.sort((a, b) => b.seconds.compareTo(a.seconds));
    final developers = [
      for (final d in devGames.keys) (developer: d, games: devGames[d]!, seconds: devSeconds[d]!),
    ]..sort((a, b) {
        final byGames = b.games.compareTo(a.games);
        return byGames != 0 ? byGames : b.seconds.compareTo(a.seconds);
      });

    return LibraryStats(
      games: installed.length,
      versions: versions,
      gamesPlayed: gamesPlayed,
      totalSeconds: total,
      byStatus: byStatus,
      byEngine: byEngine,
      mostPlayed: played.take(top).toList(),
      topDevelopers: developers.take(top).toList(),
    );
  }

  static String _engineName(GameGroup g) {
    final name = g.latestVersion?.engineName ?? '';
    return const {"Ren'Py", 'RPGM', 'Unity', 'HTML', 'Unreal'}.contains(name) ? name : 'Other';
  }
}
