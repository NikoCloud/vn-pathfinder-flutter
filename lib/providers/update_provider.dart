import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../services/update_check_service.dart';
import 'feed_provider.dart';
import 'release_history_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';
import '../utils/app_paths.dart';

/// What the game update check knows.
class UpdateCheckState {
  /// Current version of each F95Zone thread (thread ID → version).
  final Map<int, String> f95Versions;

  /// Threads found by title for games without a saved F95Zone link
  /// (baseKey → thread ID).
  final Map<String, int> titleLinks;

  /// The creator F95Zone lists for each thread found by title (baseKey →
  /// creator), for checking it's the same game before its page is used.
  final Map<String, String> titleCreators;

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
    this.titleCreators = const {},
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
    Map<String, String>? titleCreators,
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
        titleCreators: titleCreators ?? this.titleCreators,
        titleMisses: titleMisses ?? this.titleMisses,
        f95Ratings: f95Ratings ?? this.f95Ratings,
        ratingLookups: ratingLookups ?? this.ratingLookups,
        checkedAt: checkedAt ?? this.checkedAt,
        checking: checking ?? this.checking,
        error: error,
      );
}

/// Keeps fetched games' F95Zone versions current — after a library scan, at
/// most once a day ([_maxAge]):
///   1. fetched games without a saved F95Zone link get one looked up by their
///      fetched title (once; no unique match is retried after
///      [_retryMisses]), one request a second in the background;
///   2. F95Zone's checker is asked for the version of every linked thread,
///      50 to a request.
/// Games that were never fetched aren't asked about: their folder name makes
/// a poor title and a likely wrong match. Everything else comes from the Feed
/// and its release history, which reads all three sites anyway.
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

  static const _maxAge = Duration(days: 1);
  static const _feedWait = Duration(minutes: 10);
  static const _retryMisses = Duration(days: 7);

  static File get _cacheFile => File(appDataPath('update_check.json'));

  static UpdateCheckState _loadCache() {
    try {
      final json = jsonDecode(_cacheFile.readAsStringSync()) as Map<String, dynamic>;
      return UpdateCheckState(
        f95Versions: (json['f95'] as Map? ?? {}).map((k, v) => MapEntry(int.parse('$k'), '$v')),
        titleLinks: (json['title_links'] as Map? ?? {}).map((k, v) => MapEntry('$k', v as int)),
        titleCreators: (json['title_creators'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')),
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
        'title_creators': state.titleCreators,
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
    // Only games that have been fetched (Local counts): see the class comment.
    final groups = _ref.read(libraryProvider).groups.where((g) => g.versions.isNotEmpty && !g.isUnfetched).toList();
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
    } catch (e) {
      debugPrint('Game update check failed: $e');
      if (mounted) state = state.copyWith(checking: false, error: '$e');
    }
  }

  /// Looks up F95Zone threads by title for games without a saved link.
  Future<void> _linkByTitle(List<GameGroup> groups) async {
    final now = DateTime.now();
    final pending = groups.where((g) {
      if (UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) != null) return false;
      // Threads found before creators were kept are looked up once more,
      // to learn the creator (see matchedTitleLink).
      if (state.titleLinks.containsKey(g.baseKey) && state.titleCreators.containsKey(g.baseKey)) return false;
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
          titleCreators: {...state.titleCreators, g.baseKey: thread.creator},
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

/// The F95Zone thread found by [group]'s title, when it can stand in for a
/// saved link on the game page and the Get sheet: the thread's creator has to
/// match the game's known developer ("Some Studio" and "Some Studio
/// Productions" count). The title already matched exactly. Otherwise the
/// guess only drives the update badge: a wrong one would supply another
/// game's description, links and downloads.
int? matchedTitleLink(UpdateCheckState check, GameGroup group) {
  final id = check.titleLinks[group.baseKey];
  if (id == null) return null;
  String loose(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final creator = loose(check.titleCreators[group.baseKey] ?? '');
  final developer = loose(group.effectiveDeveloper);
  if (creator.isEmpty || developer.isEmpty) return null;
  return creator.startsWith(developer) || developer.startsWith(creator) ? id : null;
}

final updateCheckProvider = StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
  (ref) => UpdateCheckNotifier(ref),
);

/// Each game's rating out of 5, by baseKey: from the newest release of it the
/// Feed has seen with a rating (F95Zone and LewdCorner list one), otherwise
/// the one Fetch Metadata saved, otherwise the last one looked up before the
/// app stopped searching for ratings. Unrated games aren't listed.
final gameRatingsProvider = Provider<Map<String, double>>((ref) {
  final check = ref.watch(updateCheckProvider);
  final history = ref.watch(releaseHistoryProvider).history;
  final out = <String, double>{};
  for (final g in ref.watch(libraryGroupsProvider)) {
    double fromFeed = 0;
    DateTime? newest;
    final threads = [
      ('f95zone', UpdateCheckService.threadId(g.newestMeta((v) => v.metaF95Url)) ?? matchedTitleLink(check, g)),
      ('lewdcorner', UpdateCheckService.threadId(g.newestMeta((v) => v.metaLcUrl))),
    ];
    for (final (site, id) in threads) {
      if (id == null) continue;
      for (final e in history.forThread(site, id)) {
        if (e.rating > 0 && (newest == null || e.releasedAt.isAfter(newest))) {
          fromFeed = e.rating;
          newest = e.releasedAt;
        }
      }
    }
    final f95Id = threads.first.$2;
    final rating = fromFeed > 0
        ? fromFeed
        : g.storedRating > 0
            ? g.storedRating
            : (f95Id == null ? 0.0 : check.f95Ratings[f95Id] ?? 0.0);
    if (rating > 0) out[g.baseKey] = rating;
  }
  return out;
});

final _updateFindingsProvider = Provider((ref) {
  final check = ref.watch(updateCheckProvider);
  return UpdateCheckService.findUpdates(
    groups: ref.watch(libraryGroupsProvider),
    f95Versions: check.f95Versions,
    titleLinks: check.titleLinks,
    confirmedTitleLink: (g) => matchedTitleLink(check, g),
    history: ref.watch(releaseHistoryProvider).history,
  );
});

/// Library games with a newer version out, by baseKey: matched by a saved
/// thread link or a confirmed title match. One per game, newest version,
/// pointing to the site that posted it first.
final availableUpdatesProvider = Provider<Map<String, AvailableUpdate>>((ref) => ref.watch(_updateFindingsProvider).confirmed);

/// Newer versions found for games matched by title alone: shown on the game
/// page as something to check, never counted as updates.
final possibleUpdatesProvider = Provider<Map<String, AvailableUpdate>>((ref) => ref.watch(_updateFindingsProvider).possible);
