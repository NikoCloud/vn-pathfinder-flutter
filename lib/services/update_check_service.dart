import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/feed_item.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/game_version.dart';

/// One game from F95Zone's title search. [rating] is out of 5; 0 means none.
typedef F95Row = ({int id, String title, String version, double rating});

/// A newer version of a library game spotted on a forum.
class AvailableUpdate {
  final String version;
  final String source; // 'f95zone' | 'lewdcorner' | 'azc'
  final String url; // the game's thread, for downloading
  const AvailableUpdate({required this.version, required this.source, required this.url});

  String get sourceLabel => switch (source) {
        'f95zone' => 'F95Zone',
        'lewdcorner' => 'LewdCorner',
        'azc' => "Azkosel's Corner",
        _ => source,
      };
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

  /// Library games with a newer version than the newest one installed:
  /// first from F95Zone's checker ([f95Versions], by thread ID), then from
  /// feed items whose thread matches a game's saved link for that forum.
  /// Only clearly newer versions count (see [isClearlyNewer]).
  static Map<String, AvailableUpdate> availableUpdates(
    Iterable<GameGroup> groups,
    Map<int, String> f95Versions,
    Map<String, int> titleLinks,
    Iterable<RawFeedItem> feedItems,
    String? Function(RawFeedItem) feedVersion,
  ) {
    // Newest feed version per (source, thread): items arrive newest-first.
    final fromFeed = <(String, int), (String, String)>{};
    for (final item in feedItems) {
      final id = threadId(item.url);
      final version = feedVersion(item);
      if (id == null || version == null || version.isEmpty) continue;
      fromFeed.putIfAbsent((item.source, id), () => (version, item.url));
    }

    final updates = <String, AvailableUpdate>{};
    for (final g in groups) {
      final installed = g.latestVersion?.versionStr ?? '';
      if (installed.isEmpty) continue;
      final links = {
        'f95zone': g.newestMeta((v) => v.metaF95Url),
        'lewdcorner': g.newestMeta((v) => v.metaLcUrl),
        'azc': g.newestMeta((v) => v.metaAzcUrl),
      };

      final f95Id = threadId(links['f95zone']!) ?? titleLinks[g.baseKey];
      final f95 = f95Id == null ? null : f95Versions[f95Id];
      if (f95 != null && isClearlyNewer(f95, installed)) {
        final url = links['f95zone']!.isNotEmpty ? links['f95zone']! : 'https://f95zone.to/threads/$f95Id/';
        updates[g.baseKey] = AvailableUpdate(version: f95, source: 'f95zone', url: url);
        continue;
      }
      for (final MapEntry(key: source, value: link) in links.entries) {
        final id = threadId(link);
        final hit = id == null ? null : fromFeed[(source, id)];
        if (hit != null && isClearlyNewer(hit.$1, installed)) {
          updates[g.baseKey] = AvailableUpdate(version: hit.$1, source: source, url: hit.$2);
          break;
        }
      }
    }
    return updates;
  }
}
