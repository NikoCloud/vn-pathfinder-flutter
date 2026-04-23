import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/feed_item.dart';
import '../providers/settings_provider.dart';
import '../services/feed_service.dart';
import '../services/scraping_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class FeedState {
  final List<RawFeedItem> items;
  final bool isLoading;
  final DateTime? lastRefreshed;
  final String? error;

  const FeedState({
    this.items = const [],
    this.isLoading = false,
    this.lastRefreshed,
    this.error,
  });

  FeedState copyWith({
    List<RawFeedItem>? items,
    bool? isLoading,
    DateTime? lastRefreshed,
    String? error,
  }) => FeedState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    error: error,  // always overwrite (null clears the error)
  );
}

// ── Cache helpers ─────────────────────────────────────────────────────────────

File _cacheFile() {
  final appdata = Platform.environment['APPDATA'] ?? '';
  return File(p.join(appdata, 'VN Pathfinder', 'feed_cache.json'));
}

Future<({List<RawFeedItem> items, DateTime? lastRefreshed})> _loadCache() async {
  try {
    final f = _cacheFile();
    if (!f.existsSync()) return (items: <RawFeedItem>[], lastRefreshed: null);
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final items = (raw['items'] as List? ?? [])
        .map((e) => RawFeedItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final ts = raw['last_refreshed'] as String?;
    final lastRefreshed = ts != null ? DateTime.tryParse(ts) : null;
    return (items: items, lastRefreshed: lastRefreshed);
  } catch (e) {
    debugPrint('FeedProvider: cache load failed: $e');
    return (items: <RawFeedItem>[], lastRefreshed: null);
  }
}

Future<void> _saveCache(List<RawFeedItem> items, DateTime lastRefreshed) async {
  try {
    final f = _cacheFile();
    await f.parent.create(recursive: true);
    f.writeAsStringSync(jsonEncode({
      'last_refreshed': lastRefreshed.toIso8601String(),
      'items': items.map((i) => i.toJson()).toList(),
    }));
  } catch (e) {
    debugPrint('FeedProvider: cache save failed: $e');
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class FeedNotifier extends StateNotifier<FeedState> {
  final Ref _ref;
  Timer? _timer;

  FeedNotifier(this._ref) : super(const FeedState()) {
    _init();
  }

  Future<void> _init() async {
    // 1. Hydrate from disk immediately so the feed isn't empty on launch.
    final cache = await _loadCache();
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
    final isStale = lastRefreshed == null ||
        DateTime.now().difference(lastRefreshed) >= staleThreshold;
    if (isStale) {
      refresh();
    }
  }

  /// Manually trigger a feed refresh.
  ///
  /// New items are **merged** into the existing cache rather than replacing it.
  /// This means if one source (e.g. F95Zone) fails or returns nothing, the
  /// previously cached items from that source are preserved for up to 10 days.
  /// Items older than 10 days are pruned on each successful refresh.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    // Acquire a scraping session so WebView2 initialises for authenticated
    // sources (F95Zone JSON API, LewdCorner/AzC if plain HTTP is blocked).
    _ref.read(scrapingSessionProvider.notifier).update((s) => s + 1);
    try {
      final scraping = _ref.read(scrapingServiceProvider);
      final settings = _ref.read(settingsProvider);
      final freshItems = await FeedService.fetchAll(scraping, settings);
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 10));

      // Build a map from existing cached items so we can merge by ID.
      final merged = <String, RawFeedItem>{
        for (final i in state.items) i.id: i,
      };

      // Overwrite/add fresh items (new data always wins over cached).
      for (final item in freshItems) {
        merged[item.id] = item;
      }

      // Prune items older than 10 days. Items with no date are kept.
      final pruned = merged.values.where((i) {
        final t = i.publishedAt;
        return t == null || t.isAfter(cutoff);
      }).toList();

      // Sort newest-first.
      pruned.sort((a, b) {
        final ta = a.publishedAt;
        final tb = b.publishedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      state = state.copyWith(
        items: pruned,
        isLoading: false,
        lastRefreshed: now,
      );
      // Persist merged result to disk.
      await _saveCache(pruned, now);
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

String? _extractFeedVersion(RawFeedItem item) {
  // F95Zone / LewdCorner SAM API puts version on its own line as "Version: …"
  final m = RegExp(r'^Version:\s*(.+)$', multiLine: true).firstMatch(item.rawBody);
  if (m != null) return m.group(1)?.trim();
  return null;
}

final feedVersionMapProvider = Provider<Map<String, FeedVersionHint>>((ref) {
  final items = ref.watch(feedProvider).items; // already sorted newest-first
  final map = <String, FeedVersionHint>{};
  for (final item in items) {
    final version = _extractFeedVersion(item);
    if (version == null || version.isEmpty) continue;
    final key = _normaliseTitle(item.title);
    if (key.isEmpty) continue;
    map.putIfAbsent(key, () => FeedVersionHint(version: version, source: item.source));
  }
  return map;
});
