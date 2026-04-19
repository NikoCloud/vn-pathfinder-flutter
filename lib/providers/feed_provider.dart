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
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final scraping = _ref.read(scrapingServiceProvider);
      final settings = _ref.read(settingsProvider);
      final items = await FeedService.fetchAll(scraping, settings);
      final now = DateTime.now();
      state = state.copyWith(
        items: items,
        isLoading: false,
        lastRefreshed: now,
      );
      // Persist to disk so the next launch shows data immediately.
      await _saveCache(items, now);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
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
