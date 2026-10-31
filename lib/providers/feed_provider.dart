import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/feed_item.dart';
import '../providers/settings_provider.dart';
import '../services/feed_history.dart';
import '../services/feed_service.dart';
import '../services/scraping_service.dart';

export '../models/feed_item.dart' show extractFeedVersion;

// ── State ─────────────────────────────────────────────────────────────────────

class FeedState {
  final List<RawFeedItem> items;
  final bool isLoading;
  final DateTime? lastRefreshed;
  final String? error;

  /// Sites that didn't answer properly on the last refresh. See [FeedFetch].
  final Map<String, String> problems;

  const FeedState({
    this.items = const [],
    this.isLoading = false,
    this.lastRefreshed,
    this.error,
    this.problems = const {},
  });

  FeedState copyWith({
    List<RawFeedItem>? items,
    bool? isLoading,
    DateTime? lastRefreshed,
    String? error,
    Map<String, String>? problems,
  }) => FeedState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    error: error,  // always overwrite (null clears the error)
    problems: problems ?? this.problems,
  );
}

// ── Cache helpers ─────────────────────────────────────────────────────────────

/// What a saved row was read with. Bumped when reading a site changes, so rows
/// saved by an older build don't sit in the Feed until they age out.
const _cacheFormat = 3;

/// The saved Feed: the list, plus what it takes to tell a release from a
/// re-dated row and to catch up after a gap.
class SavedFeed {
  final List<RawFeedItem> items;
  final DateTime? lastRefreshed;
  final bool outdated;
  final ReleaseRecord releases;
  final Map<String, SiteCatchUp> sites;

  SavedFeed({
    this.items = const [],
    this.lastRefreshed,
    this.outdated = false,
    ReleaseRecord? releases,
    this.sites = const {},
  }) : releases = releases ?? ReleaseRecord();

  /// Rows from an older format are dropped where they can't be trusted: before
  /// format 2 LewdCorner had no covers and Azkosel's Corner no post, image or
  /// proper name, and before format 3 Azkosel's dates were its latest replies.
  /// The rest give the release record a start.
  factory SavedFeed.read(Map<String, dynamic> raw) {
    final format = raw['format'] as int? ?? 1;
    final redone = {if (format < 2) 'lewdcorner', if (format < 3) 'azc'};
    final items = withoutPublicRows((raw['items'] as List? ?? [])
        .map((e) => RawFeedItem.fromJson(e as Map<String, dynamic>))
        .where((i) => !redone.contains(i.source))
        .toList());
    final sites = raw['sites'];
    return SavedFeed(
      items: items,
      lastRefreshed: DateTime.tryParse('${raw['last_refreshed']}'),
      outdated: format < _cacheFormat,
      releases: format < 3 ? ReleaseRecord.seeded(items) : ReleaseRecord.fromJson(raw['releases']),
      sites: {
        if (sites is Map)
          for (final e in sites.entries) '${e.key}': SiteCatchUp.fromJson(e.value),
      },
    );
  }
}

File _cacheFile() {
  final appdata = Platform.environment['APPDATA'] ?? '';
  return File(p.join(appdata, 'VN Pathfinder', 'feed_cache.json'));
}

Future<SavedFeed> _loadCache() async {
  try {
    final f = _cacheFile();
    if (!f.existsSync()) return SavedFeed();
    return SavedFeed.read(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('FeedProvider: cache load failed: $e');
    return SavedFeed();
  }
}

Future<void> _saveCache(
  List<RawFeedItem> items,
  DateTime? lastRefreshed,
  ReleaseRecord releases,
  Map<String, SiteCatchUp> sites,
) async {
  try {
    final f = _cacheFile();
    await f.parent.create(recursive: true);
    f.writeAsStringSync(jsonEncode({
      'format': _cacheFormat,
      'last_refreshed': lastRefreshed?.toIso8601String(),
      'items': items.map((i) => i.toJson()).toList(),
      'releases': releases.toJson(),
      'sites': sites.map((site, read) => MapEntry(site, read.toJson())),
    }));
  } catch (e) {
    debugPrint('FeedProvider: cache save failed: $e');
  }
}

/// A site's public forum feed only stands in when there's nothing better. Its
/// rows have no art, and their dates are forum activity, so beside the site's
/// real list they'd sit on top of the Feed as releases that never happened.
List<RawFeedItem> withoutPublicRows(List<RawFeedItem> items) {
  final full = {
    for (final i in items)
      if (i.fromSiteList) i.source,
  };
  return items.where((i) => i.fromSiteList || !full.contains(i.source)).toList();
}

/// [cached] with [fresh] on top, newest first, one row per thread, without
/// anything older than the Feed's window. New data always wins over saved data
/// for the same thread, and if a site fails its saved rows stay.
List<RawFeedItem> mergeFeedItems(
  List<RawFeedItem> cached,
  List<RawFeedItem> fresh,
  DateTime now,
) {
  final cutoff = now.subtract(feedWindow);
  final merged = <String, RawFeedItem>{
    for (final i in cached) threadKey(i): i,
  };
  for (final item in fresh) {
    final key = threadKey(item);
    // A public feed only stands in. It never replaces what a site's list said.
    if (merged[key]?.fromSiteList == true && !item.fromSiteList) continue;
    merged[key] = item;
  }
  final kept = withoutPublicRows(merged.values.where((i) {
    final t = i.publishedAt;
    return t == null || t.isAfter(cutoff);
  }).toList());
  kept.sort((a, b) {
    final ta = a.publishedAt;
    final tb = b.publishedAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });
  return kept;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class FeedNotifier extends StateNotifier<FeedState> {
  /// A thread that won't open is passed over. This many in a row means the
  /// site itself has stopped answering.
  static const _threadMisses = 3;

  final Ref _ref;
  Timer? _timer;
  ReleaseRecord _releases = ReleaseRecord();
  Map<String, SiteCatchUp> _sites = const {};

  Future<void> _ready = Future.value();
  Future<void>? _running;

  FeedNotifier(this._ref) : super(const FeedState()) {
    _ready = _init();
  }

  /// Starts from [seed] without touching the disk or the network.
  @visibleForTesting
  FeedNotifier.seeded(this._ref, FeedState seed) : super(seed);

  /// Done once the launch refresh, and any refresh running now, have finished.
  Future<void> get idle async {
    await _ready;
    await _running;
  }

  Future<void> _init() async {
    // 1. Hydrate from disk immediately so the feed isn't empty on launch.
    final cache = await _loadCache();
    _releases = cache.releases;
    _sites = cache.sites;
    if (cache.items.isNotEmpty) {
      state = state.copyWith(
        items: cache.items,
        lastRefreshed: cache.lastRefreshed,
      );
    }

    final settings = _ref.read(settingsProvider);
    if (!settings.feedEnabled) return;

    // 2. Start the periodic timer.
    if (settings.feedRefreshHours > 0) {
      _startTimer(settings.feedRefreshHours);
    }

    // 3. Auto-refresh on launch if the cache is stale (older than the interval)
    //    or has never been fetched.
    final lastRefreshed = cache.lastRefreshed;
    final staleThreshold = Duration(hours: settings.feedRefreshHours);
    final isStale = cache.outdated ||
        lastRefreshed == null ||
        DateTime.now().difference(lastRefreshed) >= staleThreshold;
    if (isStale) {
      refresh();
    }
  }

  /// Manually trigger a feed refresh. Does nothing new if one is running.
  ///
  /// New items are **merged** into the existing cache rather than replacing it.
  /// This means if one source (e.g. F95Zone) fails or returns nothing, the
  /// previously cached items from that source are preserved for up to 10 days.
  /// Items older than 10 days are pruned as rows land.
  Future<void> refresh() => _running ??= _refresh().whenComplete(() => _running = null);

  Future<void> _refresh() async {
    // Lockdown keeps the saved list, and "updated" would be untrue.
    if (_ref.read(settingsProvider).lockdown) return;
    state = state.copyWith(isLoading: true, error: null);
    // Acquire a scraping session so WebView2 initialises for authenticated
    // sources (F95Zone JSON API, LewdCorner/AzC if plain HTTP is blocked).
    _ref.read(scrapingSessionProvider.notifier).update((s) => s + 1);
    try {
      final scraping = _ref.read(scrapingServiceProvider);
      final settings = _ref.read(settingsProvider);
      final undated = <RawFeedItem>[];
      final fetch = await FeedService.fetchAll(
        scraping,
        settings,
        sites: _sites,
        onRows: (rows) => _land(rows, undated),
      );
      _sites = {..._sites, ...fetch.sites};
      state = state.copyWith(lastRefreshed: DateTime.now(), problems: fetch.problems);
      // Persist merged result to disk.
      await _save();

      await _dateFromThreads(scraping, undated);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    } finally {
      // Release the session — WebView2 disposes when the count drops to zero.
      _ref.read(scrapingSessionProvider.notifier).update((s) => (s - 1).clamp(0, 999));
    }
  }

  /// Puts rows into the Feed as they arrive. Rows that can't be dated yet go
  /// to [undated] instead, and show up once their thread has been read.
  void _land(List<RawFeedItem> rows, List<RawFeedItem> undated) {
    final now = DateTime.now();
    final settled = <RawFeedItem>[];
    for (final row in rows) {
      if (_releases.needsThread(row)) {
        undated.add(row);
      } else {
        settled.add(_releases.settle(row, now));
      }
    }
    state = state.copyWith(items: mergeFeedItems(state.items, settled, now));
  }

  /// Opens threads one at a time, so a first run takes minutes rather than
  /// asking a small forum for 40 pages at once. Rows left unread have no
  /// record yet, so the next refresh tries them again.
  Future<void> _dateFromThreads(ScrapingService scraping, List<RawFeedItem> rows) async {
    var missed = 0;
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) await Future.delayed(FeedService.threadGap);
      if (!mounted || _ref.read(settingsProvider).lockdown) return;
      final row = rows[i];
      final thread = await FeedService.readThreadDates(scraping, row.url);
      if (!mounted) return;
      if (thread == null) {
        state = state.copyWith(problems: {...state.problems, row.source: 'threads'});
        if (++missed == _threadMisses) break;
        continue;
      }
      missed = 0;
      final now = DateTime.now();
      final item = _releases.settle(row, now, thread: thread);
      state = state.copyWith(items: mergeFeedItems(state.items, [item], now));
      if (i % 5 == 4) await _save();
    }
    await _save();
  }

  Future<void> _save() => _saveCache(state.items, state.lastRefreshed, _releases, _sites);

  /// Update the auto-refresh schedule. Call when the user changes feed settings.
  void updateSchedule(bool enabled, int refreshHours) {
    _timer?.cancel();
    _timer = null;
    if (enabled && refreshHours > 0) {
      _startTimer(refreshHours);
    }
  }

  void _startTimer(int hours) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(hours: hours), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) => FeedNotifier(ref),
);

// ── Feed version map ──────────────────────────────────────────────────────────
//
// Derived provider: maps a normalised game title to the version string seen
// in the most-recent feed item for that title. No version comparison is done —
// the UI shows whatever the feed reported and lets the user interpret it.
//
// Matching is purely by normalised title (bracket/paren content stripped,
// lowercased, whitespace-trimmed). Feed items are already sorted newest-first,
// so the first match for each title is the most recent.

/// One feed sighting: version string + which source posted it.
class FeedVersionHint {
  final String version;
  final String source; // 'f95zone' | 'lewdcorner' | …
  const FeedVersionHint({required this.version, required this.source});
}

String _normaliseTitle(String t) => t
    .replaceAll(RegExp(r'\[.*?\]'), '')   // strip [bracketed] content
    .replaceAll(RegExp(r'\(.*?\)'), '')   // strip (parenthesised) content
    .trim()
    .toLowerCase();

final feedVersionMapProvider = Provider<Map<String, FeedVersionHint>>((ref) {
  final items = ref.watch(feedProvider).items; // already sorted newest-first
  final map = <String, FeedVersionHint>{};
  for (final item in items) {
    final version = extractFeedVersion(item);
    if (version == null || version.isEmpty) continue;
    final key = _normaliseTitle(item.title);
    if (key.isEmpty) continue;
    map.putIfAbsent(key, () => FeedVersionHint(version: version, source: item.source));
  }
  return map;
});
