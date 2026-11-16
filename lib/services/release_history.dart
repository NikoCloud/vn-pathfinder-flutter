import 'dart:convert';
import 'dart:io';

import '../models/feed_item.dart';
import '../utils/app_paths.dart';
import 'feed_service.dart';
import 'update_check_service.dart';

/// Where one site posted a release, and when.
class ReleaseSite {
  final String url;
  final DateTime? postedAt;
  const ReleaseSite(this.url, this.postedAt);

  Map<String, dynamic> toJson() => {'url': url, if (postedAt != null) 'at': postedAt!.toIso8601String()};
  factory ReleaseSite.fromJson(Map json) => ReleaseSite('${json['url'] ?? ''}', DateTime.tryParse('${json['at']}'));
}

/// One release: a game at one version, with every site that posted it.
class ReleaseEntry {
  final String title;
  final String version;
  final String developer;
  final FeedKind kind;
  final DateTime firstSeen;
  final Map<String, ReleaseSite> sites;

  /// The site's rating out of 5 when this release was seen; 0 when none.
  final double rating;

  const ReleaseEntry({
    required this.title,
    required this.version,
    required this.developer,
    required this.kind,
    required this.firstSeen,
    required this.sites,
    this.rating = 0,
  });

  /// The site that posted it first, a fair race between the sites: the one
  /// with the earliest date, else any. Null if no site is known.
  MapEntry<String, ReleaseSite>? get earliest {
    MapEntry<String, ReleaseSite>? best;
    for (final e in sites.entries) {
      final t = e.value.postedAt;
      final b = best?.value.postedAt;
      if (best == null || (t != null && (b == null || t.isBefore(b)))) best = e;
    }
    return best;
  }

  /// When it came out: the earliest date any site gives, else when first seen.
  DateTime get releasedAt => earliest?.value.postedAt ?? firstSeen;

  Map<String, dynamic> toJson() => {
        'title': title,
        'version': version,
        if (developer.isNotEmpty) 'developer': developer,
        'kind': kind.name,
        'first_seen': firstSeen.toIso8601String(),
        if (rating > 0) 'rating': rating,
        'sites': {for (final e in sites.entries) e.key: e.value.toJson()},
      };

  factory ReleaseEntry.fromJson(Map json) => ReleaseEntry(
        title: '${json['title'] ?? ''}',
        version: '${json['version'] ?? ''}',
        developer: '${json['developer'] ?? ''}',
        kind: FeedKind.values.where((k) => k.name == json['kind']).firstOrNull ?? FeedKind.update,
        firstSeen: DateTime.tryParse('${json['first_seen']}') ?? DateTime(0),
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        sites: {
          for (final e in (json['sites'] as Map? ?? {}).entries)
            if (e.value is Map) '${e.key}': ReleaseSite.fromJson(e.value as Map),
        },
      );
}

/// Every release the Feed has seen, kept as plain text for good. The Feed's
/// own list keeps about ten days of full items with their art; this keeps the
/// facts of every release since the app was installed: title, version,
/// developer, kind, rating, and each site's link and date. Update alerts and
/// "which sites have it" read from here, and a calendar can later.
///
/// A release is a game's title plus its version, as the Feed de-duplicates
/// them; each site that posts it is added to the same entry.
class ReleaseHistory {
  final Map<String, ReleaseEntry> _entries;

  /// Releases by forum thread: (site, thread ID) → release keys.
  final Map<(String, int), Set<String>> _byThread = {};

  /// Releases by game title key → release keys.
  final Map<String, Set<String>> _byTitle = {};

  ReleaseHistory([Map<String, ReleaseEntry>? entries]) : _entries = entries ?? {} {
    _entries.forEach(_index);
  }

  int get length => _entries.length;
  Iterable<ReleaseEntry> get entries => _entries.values;

  void _index(String key, ReleaseEntry e) {
    for (final s in e.sites.entries) {
      final id = UpdateCheckService.threadId(s.value.url);
      if (id != null) _byThread.putIfAbsent((s.key, id), () => {}).add(key);
    }
    _byTitle.putIfAbsent(feedTitleKey(e.title), () => {}).add(key);
  }

  /// Adds [items] (Feed rows): a new release, or another site for a known
  /// one. A site's first link and date are kept; a date appearing later
  /// (once a thread has been read) fills in a missing one. Returns whether
  /// anything changed.
  bool record(Iterable<RawFeedItem> items, {DateTime? now}) {
    var changed = false;
    for (final item in items) {
      final key = FeedService.releaseKey(item);
      if (key.isEmpty) continue;
      final at = now ?? DateTime.now();
      final old = _entries[key];
      final site = old?.sites[item.source];
      if (site != null && (site.postedAt != null || item.publishedAt == null)) {
        // Known: a rating seen later still updates it.
        if (item.rating > 0 && item.rating != old!.rating) {
          _entries[key] = ReleaseEntry(
            title: old.title,
            version: old.version,
            developer: old.developer,
            kind: old.kind,
            firstSeen: old.firstSeen,
            sites: old.sites,
            rating: item.rating,
          );
          changed = true;
        }
        continue;
      }
      final entry = ReleaseEntry(
        title: old?.title ?? item.title,
        version: old?.version ?? (extractFeedVersion(item) ?? ''),
        developer: (old?.developer.isNotEmpty ?? false) ? old!.developer : item.author,
        kind: old?.kind ?? item.kind,
        firstSeen: old?.firstSeen ?? at,
        rating: item.rating > 0 ? item.rating : (old?.rating ?? 0),
        sites: {...?old?.sites, item.source: ReleaseSite(item.url, item.publishedAt)},
      );
      _entries[key] = entry;
      _index(key, entry);
      changed = true;
    }
    return changed;
  }

  /// Releases posted in [site]'s thread [threadId].
  List<ReleaseEntry> forThread(String site, int threadId) =>
      [for (final k in _byThread[(site, threadId)] ?? const <String>{}) ?_entries[k]];

  /// Releases of a game by its title, on any site.
  List<ReleaseEntry> forTitle(String title) =>
      [for (final k in _byTitle[feedTitleKey(title)] ?? const <String>{}) ?_entries[k]];

  /// The release of [title] at [version], if seen.
  ReleaseEntry? release(String title, String version) {
    for (final e in forTitle(title)) {
      if (_versionKey(e.version) == _versionKey(version)) return e;
    }
    return null;
  }

  static String _versionKey(String v) => v.toLowerCase().replaceFirst(RegExp(r'^v\.?'), '').trim();

  // ── Saving ─────────────────────────────────────────────────────────────────

  static File get file => File(appDataPath('release_history.json'));

  static ReleaseHistory load() {
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      final releases = json['releases'] as Map? ?? {};
      return ReleaseHistory({
        for (final e in releases.entries)
          if (e.value is Map) '${e.key}': ReleaseEntry.fromJson(e.value as Map),
      });
    } catch (_) {
      return ReleaseHistory();
    }
  }

  void save() {
    try {
      final f = file;
      f.parent.createSync(recursive: true);
      // Written beside and renamed into place, so a crash mid-write never
      // loses the history.
      final tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(jsonEncode({
        'version': 1,
        'releases': {for (final e in _entries.entries) e.key: e.value.toJson()},
      }));
      tmp.renameSync(f.path);
    } catch (_) {}
  }
}
