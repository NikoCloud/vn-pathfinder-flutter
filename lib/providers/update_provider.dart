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

  final DateTime? checkedAt;
  final bool checking;
  final String? error;

  const UpdateCheckState({
    this.f95Versions = const {},
    this.titleLinks = const {},
    this.titleMisses = const {},
    this.checkedAt,
    this.checking = false,
    this.error,
  });

  UpdateCheckState copyWith({
    Map<int, String>? f95Versions,
    Map<String, int>? titleLinks,
    Map<String, DateTime>? titleMisses,
    DateTime? checkedAt,
    bool? checking,
    String? error,
  }) =>
      UpdateCheckState(
        f95Versions: f95Versions ?? this.f95Versions,
        titleLinks: titleLinks ?? this.titleLinks,
        titleMisses: titleMisses ?? this.titleMisses,
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
  }

  final Ref _ref;
  static const _maxAge = Duration(hours: 6);
  static const _retryMisses = Duration(days: 7);

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
      if (state.titleLinks.containsKey(g.baseKey)) return false;
      final missed = state.titleMisses[g.baseKey];
      return missed == null || now.difference(missed) > _retryMisses;
    }).toList();
    var done = 0;
    for (final g in pending) {
      if (!mounted || !_allowed) return;
      final thread = await UpdateCheckService.findF95Thread(g.effectiveTitle);
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

/// Library games with a newer version on a forum, by baseKey.
final availableUpdatesProvider = Provider<Map<String, AvailableUpdate>>((ref) {
  final check = ref.watch(updateCheckProvider);
  return UpdateCheckService.availableUpdates(
    ref.watch(libraryProvider).groups,
    check.f95Versions,
    check.titleLinks,
    ref.watch(feedProvider).items,
    extractFeedVersion,
  );
});
