import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';
import '../services/update_check_service.dart';
import 'feed_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

/// What the game update check knows.
class UpdateCheckState {
  /// Current version of each F95Zone thread (thread ID → version).
  final Map<int, String> f95Versions;

  /// Threads found by title for games without a saved F95Zone link
  /// (baseKey → thread ID).
  final Map<String, int> titleLinks;

  /// Games whose title search found no unique thread, and when — retried
  /// after [UpdateCheckNotifier._retryMisses].
  final Map<String, DateTime> titleMisses;

  /// F95Zone ratings out of 5 (thread ID → rating).
  final Map<int, double> f95Ratings;

  /// When each thread's rating was last looked up (thread ID → time).
  final Map<int, DateTime> ratingLookups;

  final DateTime? checkedAt;
  final bool checking;
  final String? error;

  const UpdateCheckState({
    this.f95Versions = const {},
    this.titleLinks = const {},
    this.titleMisses = const {},
    this.f95Ratings = const {},
    this.ratingLookups = const {},
    this.checkedAt,
    this.checking = false,
    this.error,
  });

  UpdateCheckState copyWith({
    Map<int, String>? f95Versions,
    Map<String, int>? titleLinks,
    Map<String, DateTime>? titleMisses,
    Map<int, double>? f95Ratings,
    Map<int, DateTime>? ratingLookups,
    DateTime? checkedAt,
    bool? checking,
    String? error,
  }) =>
      UpdateCheckState(
        f95Versions: f95Versions ?? this.f95Versions,
        titleLinks: titleLinks ?? this.titleLinks,
        titleMisses: titleMisses ?? this.titleMisses,
        f95Ratings: f95Ratings ?? this.f95Ratings,
        ratingLookups: ratingLookups ?? this.ratingLookups,
        checkedAt: checkedAt ?? this.checkedAt,
        checking: checking ?? this.checking,
        error: error,
      );
}

/// Keeps library games' F95Zone versions current — after each library scan,
/// at most every [_maxAge]:
///   1. games without a saved F95Zone link get one looked up by title (once;
///      no unique match is retried after [_retryMisses]), one request a
///      second in the background;
///   2. F95Zone's checker is asked for the version of every linked thread.
/// Cached at %APPDATA%\VN Pathfinder\update_check.json so badges survive
/// restarts. Nothing is sent in lockdown or with Game Update Checks off.
class UpdateCheckNotifier extends StateNotifier<UpdateCheckState> {
  UpdateCheckNotifier(this._ref) : super(_loadCache()) {
    _ref.listen<LibraryState>(libraryProvider, (prev, next) {
      if (!next.loading && next.groups.isNotEmpty) Future.microtask(check);
    }, fireImmediately: true);
    // check() does nothing until _maxAge has passed, so this just keeps an
    // app that's left open up to date.
    _timer = Timer.periodic(const Duration(hours: 1), (_) => check());
  }

  /// Starts empty, without touching the disk or the network.
  @visibleForTesting
  UpdateCheckNotifier.seeded(this._ref) : super(const UpdateCheckState());

  final Ref _ref;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _maxAge = Duration(hours: 6);
  static const _feedWait = Duration(minutes: 10);
  static const _retryMisses = Duration(days: 7);
  static const _ratingMaxAge = Duration(days: 7);
  static const _ratingsPerCheck = 20;
  static const _ratingGap = Duration(seconds: 3);

  static File get _cacheFile => File(p.join(
      Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'update_check.json'));

  static UpdateCheckState _loadCache() {
    try {
      final json = jsonDecode(_cacheFile.readAsStringSync()) as Map<String, dynamic>;
      return UpdateCheckState(
        f95Versions: (json['f95'] as Map? ?? {}).map((k, v) => MapEntry(int.parse('$k'), '$v')),
        titleLinks: (json['title_links'] as Map? ?? {}).map((k, v) => MapEntry('$k', v as int)),
        titleMisses: (json['title_misses'] as Map? ?? {})
            .map((k, v) => MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(0))),
        checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? ''),
        f95Ratings: (json['f95_ratings'] as Map? ?? {})
            .map((k, v) => MapEntry(int.parse('$k'), (v as num).toDouble())),
        ratingLookups: (json['rating_lookups'] as Map? ?? {})
            .map((k, v) => MapEntry(int.parse('$k'), DateTime.tryParse('$v') ?? DateTime(0))),
      );
    } catch (_) {
      return const UpdateCheckState();
    }
  }

  void _saveCache() {
    try {
      _cacheFile.parent.createSync(recursive: true);
      _cacheFile.writeAsStringSync(jsonEncode({
        'checked_at': state.checkedAt?.toIso8601String(),
        'rating_lookups':
            state.ratingLookups.map((k, v) => MapEntry('$k', v.toIso8601String())),
        'f95_ratings': state.f95Ratings.map((k, v) => MapEntry('$k', v)),
        'f95': state.f95Versions.map((k, v) => MapEntry('$k', v)),
        'title_links': state.titleLinks,
        'title_misses': state.titleMisses.map((k, v) => MapEntry(k, v.toIso8601String())),
      }));
    } catch (e) {
      debugPrint('Game update check: cache save failed: $e');
    }
  }

  bool get _allowed {
    final s = _ref.read(settingsProvider);
    return !s.lockdown && s.checkGameUpdates;
  }

  Future<void> check({bool force = false}) async {
    if (!mounted || state.checking || !_allowed) return;
    final last = state.checkedAt;
    if (!force && last != null && DateTime.now().difference(last) < _maxAge) return;
    final groups = _ref.read(libraryProvider).groups.where((g) => g.versions.isNotEmpty).toList();
    if (groups.isEmpty) return;

    state = state.copyWith(checking: true);
    try {
      // The Feed goes first, so the two don't reach F95Zone at once.
      await _ref.read(feedProvider.notifier).idle.timeout(_feedWait, onTimeout: () {});
      if (!mounted || !_allowed) {
        if (mounted) state = state.copyWith(checking: false);
        return;
      }
      await _linkByTitle(groups);
      if (!mounted || !_allowed) return;
      final ids = UpdateCheckService.f95ThreadIds(groups, state.titleLinks);
      final versions = ids.isEmpty ? <int, String>{} : await UpdateCheckService.f95Versions(ids);
      if (!mounted) return;
      state = state.copyWith(f95Versions: versions, checkedAt: DateTime.now(), checking: false);
      _saveCache();
      debugPrint('Game update check: ${versions.length} F95Zone threads '
          '(${state.titleLinks.length} found by title)');
      await _refreshRatings(groups);
    } catch (e) {
      debugPrint('Game update check failed: $e');
      if (mounted) state = state.copyWith(checking: false, error: '$e');
    }
  }

  /// Ratings only come from F95Zone's title search, one game at a time, and
  /// F95Zone refuses that search after a burst. So each check looks up a few
  /// games, the longest wait first, and stops at the first failure. The rest
  /// stay due for the next check.
  Future<void> _refreshRatings(List<GameGroup> groups) async {
    final byThread = <int, GameGroup>{};
    for (final g in groups) {
      final id = UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) ?? state.titleLinks[g.baseKey];
      if (id != null) byThread[id] = g;
    }
    final now = DateTime.now();
    final due = UpdateCheckService.ratingsDue(byThread.keys, state.ratingLookups, now, _ratingMaxAge);
    final ratings = Map<int, double>.from(state.f95Ratings);
    final lookups = Map<int, DateTime>.from(state.ratingLookups);
    var searches = 0;
    for (final id in due) {
      if (searches >= _ratingsPerCheck) break;
      if (!mounted || !_allowed) return;
      // One search returns many games, so an earlier one may have covered this.
      if (lookups[id] != state.ratingLookups[id]) continue;
      final queries = UpdateCheckService.searchQueries(byThread[id]!.effectiveTitle);
      if (queries.isEmpty) continue;
      try {
        for (final row in await UpdateCheckService.searchF95(queries.first)) {
          if (row.rating > 0) ratings[row.id] = row.rating;
          lookups[row.id] = now;
        }
        lookups[id] = now;
      } catch (e) {
        debugPrint('Game rating check stopped: $e');
        break;
      }
      searches++;
      await Future.delayed(_ratingGap);
    }
    if (!mounted || searches == 0) return;
    state = state.copyWith(f95Ratings: ratings, ratingLookups: lookups);
    _saveCache();
  }

  /// Looks up F95Zone threads by title for games without a saved link.
  Future<void> _linkByTitle(List<GameGroup> groups) async {
    final now = DateTime.now();
    final pending = groups.where((g) {
      if (UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) != null) return false;
      if (state.titleLinks.containsKey(g.baseKey)) return false;
      final missed = state.titleMisses[g.baseKey];
      return missed == null || now.difference(missed) > _retryMisses;
    }).toList();
    var done = 0;
    for (final g in pending) {
      if (!mounted || !_allowed) return;
      final F95Row? thread;
      try {
        thread = await UpdateCheckService.findF95Thread(g.effectiveTitle);
      } catch (e) {
        // The rest stay pending. Version checks don't need this search.
        debugPrint('Game update check: title lookups stopped: $e');
        break;
      }
      if (!mounted) return;
      if (thread != null) {
        state = state.copyWith(
          titleLinks: {...state.titleLinks, g.baseKey: thread.id},
          f95Versions: {...state.f95Versions, thread.id: thread.version},
          checking: true,
        );
        debugPrint('Game update check: "${g.effectiveTitle}" → F95Zone thread ${thread.id}');
      } else {
        state = state.copyWith(
          titleMisses: {...state.titleMisses, g.baseKey: DateTime.now()},
          checking: true,
        );
      }
      if (++done % 10 == 0) _saveCache();
      await Future.delayed(const Duration(seconds: 1));
    }
    if (pending.isNotEmpty) _saveCache();
  }
}

final updateCheckProvider = StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
  (ref) => UpdateCheckNotifier(ref),
);

/// Each game's rating out of 5, by baseKey: F95Zone's current rating when
/// known, otherwise the one Fetch Metadata saved. Unrated games aren't listed.
final gameRatingsProvider = Provider<Map<String, double>>((ref) {
  final check = ref.watch(updateCheckProvider);
  return {
    for (final g in ref.watch(libraryGroupsProvider))
      if ((check.f95Ratings[UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) ??
                  check.titleLinks[g.baseKey]] ??
              g.storedRating) >
          0)
        g.baseKey: check.f95Ratings[UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) ??
                check.titleLinks[g.baseKey]] ??
            g.storedRating,
  };
});

/// Library games with a newer version on a forum, by baseKey.
final availableUpdatesProvider = Provider<Map<String, AvailableUpdate>>((ref) {
  final check = ref.watch(updateCheckProvider);
  return UpdateCheckService.availableUpdates(
    ref.watch(libraryGroupsProvider),
    check.f95Versions,
    check.titleLinks,
    ref.watch(feedProvider).items,
    extractFeedVersion,
  );
});
