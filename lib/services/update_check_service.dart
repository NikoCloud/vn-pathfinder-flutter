import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/game_version.dart';
import 'release_history.dart';

/// One game from F95Zone's title search. [rating] is out of 5; 0 means none.
typedef F95Row = ({int id, String title, String version, double rating, String creator});

/// A newer version of a library game spotted on a forum.
class AvailableUpdate {
  final String version;
  final String source; // 'f95zone' | 'lewdcorner' | 'azc': the site that posted it first
  final String url; // the game's thread there, for downloading
  final DateTime? postedAt;

  /// Every site known to have this version, site → thread link.
  final Map<String, String> sites;

  /// False when the game was matched by title alone, without its developer
  /// confirming it: shown as a possible update to check, never counted.
  final bool confirmed;

  const AvailableUpdate({
    required this.version,
    required this.source,
    required this.url,
    this.postedAt,
    this.sites = const {},
    this.confirmed = true,
  });

  String get sourceLabel => switch (source) {
        'f95zone' => 'F95Zone',
        'lewdcorner' => 'LewdCorner',
        'azc' => "Azkosel's Corner",
        _ => source,
      };
}

/// The site key ('f95zone', 'lewdcorner', 'azc') a forum link belongs to.
String? forumSite(String url) {
  final u = url.toLowerCase();
  if (u.contains('f95zone.')) return 'f95zone';
  if (u.contains('lewdcorner.')) return 'lewdcorner';
  if (u.contains('azkoselscorner.')) return 'azc';
  return null;
}

/// "site:threadId" for a forum thread link, or null for anything else.
String? threadVersionKey(String url) {
  final site = forumSite(url), id = UpdateCheckService.threadId(url);
  return site == null || id == null ? null : '$site:$id';
}

/// Finds forum updates for library games, matched by forum thread ID rather
/// than title — titles collide across games (two "Guilty Pleasure"s) and
/// differ in punctuation, thread IDs don't.
class UpdateCheckService {
  static const _ua = 'VN-Pathfinder/2.0 (https://github.com/NikoCloud/vn-pathfinder-flutter)';

  /// The thread ID in a XenForo thread link: ".../threads/guilty-pleasure-v0-65-quonix.69735/",
  /// ".../threads/320474/", ".../index.php?threads/club-detention.7333/".
  static int? threadId(String url) {
    final m = RegExp(r'threads/(?:[^/?#]*\.)?(\d+)/?').firstMatch(url);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Current version of each F95Zone thread, from F95Zone's public checker
  /// endpoint (the one community update checkers use). Asks in batches.
  static Future<Map<int, String>> f95Versions(Iterable<int> threadIds) async {
    final ids = threadIds.toSet().toList()..sort();
    final versions = <int, String>{};
    for (var i = 0; i < ids.length; i += 50) {
      final batch = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      final resp = await http
          .get(Uri.parse('https://f95zone.to/sam/checker.php?threads=${batch.join(',')}'),
              headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('F95Zone version check failed (HTTP ${resp.statusCode})');
      }
      final json = jsonDecode(resp.body);
      final msg = json is Map && json['status'] == 'ok' ? json['msg'] : null;
      if (msg is! Map) throw Exception('F95Zone version check: unexpected reply');
      msg.forEach((k, v) {
        final id = int.tryParse('$k');
        if (id != null && v is String && v.trim().isNotEmpty) versions[id] = v.trim();
      });
    }
    return versions;
  }

  /// F95Zone thread IDs of library games: links saved by Fetch Metadata, plus
  /// threads found by title ([titleLinks], by baseKey) for games without one.
  static Set<int> f95ThreadIds(Iterable<GameGroup> groups, Map<String, int> titleLinks) => {
        for (final g in groups)
          ?(threadId(g.newestMeta((v) => v.metaF95Url)) ?? titleLinks[g.baseKey]),
      };

  // ── Finding a game's F95Zone thread by title ─────────────────────────────

  /// Queries for F95Zone's title search, best first. It matches whole words,
  /// returns nothing when the query contains a short word ("to"), and treats
  /// "grandmas" and "grandma's" as different words — so: the title's longer
  /// words, then the same with a plural/possessive "s" dropped.
  static List<String> searchQueries(String title) {
    final words = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .take(4)
        .toList();
    if (words.isEmpty) return const [];
    final singular = words
        .map((w) => w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w);
    return {words.join(' '), singular.join(' ')}.toList();
  }

  /// A title with case, spaces and punctuation removed: "Grandma's House" and
  /// "Grandmas House" both become "grandmashouse".
  static String looseTitle(String title) => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Whether two library entries look like one game: they link to the same
  /// forum thread, or have the same title.
  static bool looksLikeSameGame(GameGroup a, GameGroup b) {
    for (final link in <String Function(GameVersion)>[
      (v) => v.metaF95Url,
      (v) => v.metaLcUrl,
      (v) => v.metaAzcUrl,
    ]) {
      final id = threadId(a.newestMeta(link));
      if (id != null && id == threadId(b.newestMeta(link))) return true;
    }
    return looseTitle(a.effectiveTitle) == looseTitle(b.effectiveTitle);
  }

  /// Threads due a rating lookup: not looked up within [maxAge], longest wait
  /// first.
  static List<int> ratingsDue(
      Iterable<int> threads, Map<int, DateTime> lookups, DateTime now, Duration maxAge) {
    final never = DateTime.fromMillisecondsSinceEpoch(0);
    final due = threads.where((id) {
      final last = lookups[id];
      return last == null || now.difference(last) >= maxAge;
    }).toList();
    return due..sort((a, b) => (lookups[a] ?? never).compareTo(lookups[b] ?? never));
  }

  /// F95Zone's Latest Updates search — the endpoint the feed uses.
  static Future<List<F95Row>> searchF95(String query) async {
    final resp = await http
        .get(
            Uri.parse('https://f95zone.to/sam/latest_alpha/latest_data.php'
                '?cmd=list&cat=games&page=1&sort=date&rows=30&search=${Uri.encodeQueryComponent(query)}'),
            headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw Exception('F95Zone search failed (HTTP ${resp.statusCode})');
    final json = jsonDecode(resp.body);
    final msg = json is Map ? json['msg'] : null;
    final rows = msg is Map ? msg['data'] : null;
    if (rows is! List) return const [];
    return [
      for (final r in rows.whereType<Map>())
        if (r['thread_id'] is int)
          (
            id: r['thread_id'] as int,
            title: '${r['title'] ?? ''}',
            version: '${r['version'] ?? ''}',
            rating: (r['rating'] as num?)?.toDouble() ?? 0,
            creator: '${r['creator'] ?? ''}',
          ),
    ];
  }

  /// The one F95Zone thread whose title is [title] (ignoring case and
  /// punctuation). Null when none — or several — match: a wrong link is worse
  /// than none (two different games are both called "Guilty Pleasure").
  static Future<F95Row?> findF95Thread(String title) async {
    final wanted = looseTitle(title);
    if (wanted.length < 3) return null;
    final queries = searchQueries(title);
    for (var i = 0; i < queries.length; i++) {
      if (i > 0) await Future.delayed(const Duration(seconds: 1));
      final exact = (await searchF95(queries[i])).where((r) => looseTitle(r.title) == wanted).toList();
      if (exact.length == 1) return exact.single;
      if (exact.length > 1) return null;
    }
    return null;
  }

  /// Library games with a newer version than the newest one installed, one
  /// alert per game. Versions come from F95Zone's checker ([f95Versions], by
  /// thread) and from the release history the Feed keeps for all three
  /// sites ([history]). The newest version wins; when sites have the same
  /// version, the alert points to the one that posted it first, the same
  /// fair race the Feed uses. Only clearly newer versions count (see
  /// [isClearlyNewer]).
  ///
  /// A game counts when it's matched by a saved thread link, or by a title
  /// search whose thread [confirmedTitleLink] accepts (its creator is the
  /// game's developer). Matches by title alone go to `possible` instead.
  static ({Map<String, AvailableUpdate> confirmed, Map<String, AvailableUpdate> possible}) findUpdates({
    required Iterable<GameGroup> groups,
    required Map<int, String> f95Versions,
    required Map<String, int> titleLinks,
    required int? Function(GameGroup) confirmedTitleLink,
    required ReleaseHistory history,
    Map<String, String> threadVersions = const {},
  }) {
    final confirmed = <String, AvailableUpdate>{};
    final possible = <String, AvailableUpdate>{};
    for (final g in groups) {
      final installed = g.latestVersion?.versionStr ?? '';
      if (installed.isEmpty) continue;
      final sure = <AvailableUpdate>[], unsure = <AvailableUpdate>[];

      void fromEntry(ReleaseEntry e, List<AvailableUpdate> into, bool ok) {
        final first = e.earliest;
        if (first == null || e.version.isEmpty) return;
        into.add(AvailableUpdate(
          version: e.version,
          source: first.key,
          url: first.value.url,
          postedAt: first.value.postedAt,
          sites: {for (final s in e.sites.entries) s.key: s.value.url},
          confirmed: ok,
        ));
      }

      void fromChecker(int id, List<AvailableUpdate> into, bool ok, String link) {
        final v = f95Versions[id];
        if (v == null) return;
        final url = link.isNotEmpty ? link : 'https://f95zone.to/threads/$id/';
        into.add(AvailableUpdate(version: v, source: 'f95zone', url: url, sites: {'f95zone': url}, confirmed: ok));
      }

      final seen = <ReleaseEntry>{};
      for (final (site, link) in [
        ('f95zone', g.newestMeta((v) => v.metaF95Url)),
        ('lewdcorner', g.newestMeta((v) => v.metaLcUrl)),
        ('azc', g.newestMeta((v) => v.metaAzcUrl)),
      ]) {
        final id = threadId(link);
        if (id == null) continue;
        if (site == 'f95zone') fromChecker(id, sure, true, link);
        // What the thread showed when the app last read it.
        final read = threadVersions['$site:$id'];
        if (read != null) sure.add(AvailableUpdate(version: read, source: site, url: link, sites: {site: link}));
        for (final e in history.forThread(site, id)) {
          if (seen.add(e)) fromEntry(e, sure, true);
        }
      }
      final titleId = threadId(g.newestMeta((v) => v.metaF95Url)) == null ? titleLinks[g.baseKey] : null;
      if (titleId != null) {
        final ok = confirmedTitleLink(g) == titleId;
        fromChecker(titleId, ok ? sure : unsure, ok, '');
        for (final e in history.forThread('f95zone', titleId)) {
          if (seen.add(e)) fromEntry(e, ok ? sure : unsure, ok);
        }
      }
      for (final e in history.forTitle(g.effectiveTitle)) {
        if (seen.add(e)) fromEntry(e, unsure, false);
      }

      final best = _newest(sure, installed, history, g.effectiveTitle);
      if (best != null) {
        confirmed[g.baseKey] = best;
      } else {
        final maybe = _newest(unsure, installed, history, g.effectiveTitle);
        if (maybe != null) possible[g.baseKey] = maybe;
      }
    }
    return (confirmed: confirmed, possible: possible);
  }

  /// The newest of [candidates] that's clearly newer than [installed]; for
  /// the same version, the earliest post. A version only F95Zone's checker
  /// reported takes the history's sites and date for it when the Feed saw it.
  static AvailableUpdate? _newest(List<AvailableUpdate> candidates, String installed, ReleaseHistory history, String title) {
    AvailableUpdate? best;
    for (final c in candidates) {
      if (!isClearlyNewer(c.version, installed)) continue;
      if (best == null || isClearlyNewer(c.version, best.version)) {
        best = c;
        continue;
      }
      if (isClearlyNewer(best.version, c.version)) continue;
      // The same version: the earlier post wins, a dated one over an undated.
      final a = c.postedAt, b = best.postedAt;
      if (a != null && (b == null || a.isBefore(b))) best = c;
    }
    if (best == null || best.postedAt != null) return best;
    final known = history.release(title, best.version);
    final first = known?.earliest;
    if (known == null || first == null) return best;
    return AvailableUpdate(
      version: best.version,
      source: first.key,
      url: first.value.url,
      postedAt: first.value.postedAt,
      sites: {...best.sites, for (final s in known.sites.entries) s.key: s.value.url},
      confirmed: best.confirmed,
    );
  }
}
