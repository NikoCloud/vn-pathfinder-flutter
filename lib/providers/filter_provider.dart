import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/user_data.dart';
import 'library_provider.dart';
import 'update_provider.dart';
import '../services/update_check_service.dart';

enum SortMode { alpha, developer, rating, recentlyPlayed, playTime, dateAdded }
enum SearchMode { title, creator }
enum TagMatchMode { any, all } // OR / AND

const allStatusIds = {
  'unplayed', 'playing', 'updated', 'on-hold', 'completed', 'skimmed', 'abandoned',
};

class FilterState {
  final String query;
  final SearchMode searchMode;
  final List<String> includeTags;
  final List<String> excludeTags;
  final TagMatchMode tagMatchMode;
  final Set<String> engines;      // 'renpy','rpgm','unity','html','unreal','other'
  final Set<String> statuses;     // GameStatus ids
  final SortMode sort;
  final bool updatesOnly;         // only games with a newer version on a forum
  final bool unfetchedOnly;       // only games with no .vnpf folder
  final double minRating;         // 0 = any
  final int releasedWithinDays;   // 0 = any
  final bool showHidden;          // include games hidden from the library

  const FilterState({
    this.query = '',
    this.searchMode = SearchMode.title,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.tagMatchMode = TagMatchMode.any,
    this.engines = const {'renpy', 'rpgm', 'unity', 'html', 'unreal', 'other'},
    this.statuses = allStatusIds,
    this.sort = SortMode.alpha,
    this.updatesOnly = false,
    this.unfetchedOnly = false,
    this.minRating = 0,
    this.releasedWithinDays = 0,
    this.showHidden = false,
  });

  FilterState copyWith({
    String? query,
    SearchMode? searchMode,
    List<String>? includeTags,
    List<String>? excludeTags,
    TagMatchMode? tagMatchMode,
    Set<String>? engines,
    Set<String>? statuses,
    SortMode? sort,
    bool? updatesOnly,
    bool? unfetchedOnly,
    double? minRating,
    int? releasedWithinDays,
    bool? showHidden,
  }) => FilterState(
    query: query ?? this.query,
    searchMode: searchMode ?? this.searchMode,
    includeTags: includeTags ?? this.includeTags,
    excludeTags: excludeTags ?? this.excludeTags,
    tagMatchMode: tagMatchMode ?? this.tagMatchMode,
    engines: engines ?? this.engines,
    statuses: statuses ?? this.statuses,
    sort: sort ?? this.sort,
    updatesOnly: updatesOnly ?? this.updatesOnly,
    unfetchedOnly: unfetchedOnly ?? this.unfetchedOnly,
    minRating: minRating ?? this.minRating,
    releasedWithinDays: releasedWithinDays ?? this.releasedWithinDays,
    showHidden: showHidden ?? this.showHidden,
  );

  bool get isActive =>
      query.isNotEmpty ||
      includeTags.isNotEmpty ||
      excludeTags.isNotEmpty;

  /// Filters applied beyond search and the quick views, for the Filters button.
  int get activeFilters =>
      includeTags.length +
      excludeTags.length +
      (engines.length < 6 ? 1 : 0) +
      (unfetchedOnly ? 1 : 0) +
      (minRating > 0 ? 1 : 0) +
      (releasedWithinDays > 0 ? 1 : 0) +
      (showHidden ? 1 : 0);

  /// What a saved view keeps. The search box stays out of it.
  Map<String, dynamic> toJson() => {
        'include_tags': includeTags,
        'exclude_tags': excludeTags,
        'tag_match': tagMatchMode.name,
        'engines': engines.toList(),
        'statuses': statuses.toList(),
        'sort': sort.name,
        'updates_only': updatesOnly,
        'unfetched_only': unfetchedOnly,
        'min_rating': minRating,
        'released_within_days': releasedWithinDays,
        'show_hidden': showHidden,
      };

  factory FilterState.fromJson(Map<String, dynamic> j) => FilterState(
        includeTags: List<String>.from(j['include_tags'] as List? ?? []),
        excludeTags: List<String>.from(j['exclude_tags'] as List? ?? []),
        tagMatchMode: TagMatchMode.values.asNameMap()[j['tag_match']] ?? TagMatchMode.any,
        engines: Set<String>.from(j['engines'] as List? ?? const FilterState().engines),
        statuses: Set<String>.from(j['statuses'] as List? ?? allStatusIds),
        sort: SortMode.values.asNameMap()[j['sort']] ?? SortMode.alpha,
        updatesOnly: j['updates_only'] as bool? ?? false,
        unfetchedOnly: j['unfetched_only'] as bool? ?? false,
        minRating: (j['min_rating'] as num?)?.toDouble() ?? 0,
        releasedWithinDays: j['released_within_days'] as int? ?? 0,
        showHidden: j['show_hidden'] as bool? ?? false,
      );
}

class FilterNotifier extends StateNotifier<FilterState> {
  FilterNotifier() : super(const FilterState());

  void setQuery(String q) => state = state.copyWith(query: q);
  void setSearchMode(SearchMode m) => state = state.copyWith(searchMode: m);
  void setSort(SortMode s) => state = state.copyWith(sort: s);
  void setTagMatchMode(TagMatchMode m) => state = state.copyWith(tagMatchMode: m);

  void addIncludeTag(String tag) {
    if (state.includeTags.contains(tag) || state.includeTags.length >= 10) return;
    state = state.copyWith(includeTags: [...state.includeTags, tag]);
  }

  void removeIncludeTag(String tag) =>
      state = state.copyWith(
          includeTags: state.includeTags.where((t) => t != tag).toList());

  void addExcludeTag(String tag) {
    if (state.excludeTags.contains(tag) || state.excludeTags.length >= 10) return;
    state = state.copyWith(excludeTags: [...state.excludeTags, tag]);
  }

  void removeExcludeTag(String tag) =>
      state = state.copyWith(
          excludeTags: state.excludeTags.where((t) => t != tag).toList());

  void toggleEngine(String engine, bool enabled) {
    final s = Set<String>.from(state.engines);
    enabled ? s.add(engine) : s.remove(engine);
    state = state.copyWith(engines: s);
  }

  void setUpdatesOnly(bool v) => state = state.copyWith(updatesOnly: v);
  void setUnfetchedOnly(bool v) => state = state.copyWith(unfetchedOnly: v);
  void setMinRating(double v) => state = state.copyWith(minRating: v);
  void setReleasedWithinDays(int v) => state = state.copyWith(releasedWithinDays: v);
  void setShowHidden(bool v) => state = state.copyWith(showHidden: v);

  void toggleStatus(String status, bool enabled) {
    final s = Set<String>.from(state.statuses);
    enabled ? s.add(status) : s.remove(status);
    state = state.copyWith(statuses: s);
  }

  void reset() => state = const FilterState();

  /// One quick view: a status, or every status with [updatesOnly].
  void setView({Set<String> statuses = allStatusIds, bool updatesOnly = false}) =>
      state = state.copyWith(statuses: statuses, updatesOnly: updatesOnly);

  /// A saved view. The search box is left as it is.
  void load(FilterState saved) => state = saved.copyWith(query: state.query);

  void clearFilters() => state = const FilterState().copyWith(
        query: state.query,
        sort: state.sort,
        statuses: state.statuses,
        updatesOnly: state.updatesOnly,
      );
}

final filterProvider =
    StateNotifierProvider<FilterNotifier, FilterState>(
  (ref) => FilterNotifier(),
);

// ── Filtered + sorted game list ───────────────────────────────────────────────

final filteredGroupsProvider = Provider<List<GameGroup>>((ref) {
  final groups = ref.watch(libraryGroupsProvider);
  final filter = ref.watch(filterProvider);
  final ud = ref.watch(userDataProvider);

  // Exclude archive-only groups (no installed game versions) from the library.
  var result = groups
      .where((g) => g.versions.isNotEmpty && (filter.showHidden || !ud.hidden.contains(g.baseKey)))
      .toList();

  // Text search
  if (filter.query.isNotEmpty) {
    final q = filter.query.toLowerCase();
    result = result.where((g) {
      if (filter.searchMode == SearchMode.title) {
        return g.effectiveTitle.toLowerCase().contains(q);
      } else {
        return g.effectiveDeveloper.toLowerCase().contains(q);
      }
    }).toList();
  }

  // Tag include filter
  if (filter.includeTags.isNotEmpty) {
    result = result.where((g) {
      final gameTags = _allTagsForGroup(g, ud);
      if (filter.tagMatchMode == TagMatchMode.any) {
        return filter.includeTags.any((t) => gameTags.contains(t));
      } else {
        return filter.includeTags.every((t) => gameTags.contains(t));
      }
    }).toList();
  }

  // Tag exclude filter
  if (filter.excludeTags.isNotEmpty) {
    result = result.where((g) {
      final gameTags = _allTagsForGroup(g, ud);
      return !filter.excludeTags.any((t) => gameTags.contains(t));
    }).toList();
  }

  // Engine filter (only when not all engines selected)
  const allEngines = {'renpy', 'rpgm', 'unity', 'html', 'unreal', 'other'};
  if (!filter.engines.containsAll(allEngines)) {
    result = result.where((g) {
      final v = g.latestVersion;
      if (v == null) return filter.engines.contains('other');
      final meta = v.metaEngine.toLowerCase();
      if (v.isRenpy || meta == 'renpy') return filter.engines.contains('renpy');
      if (meta == 'rpgm' || meta == 'rpg maker') return filter.engines.contains('rpgm');
      if (meta == 'unity') return filter.engines.contains('unity');
      if (meta == 'html' || meta == 'web') return filter.engines.contains('html');
      if (meta == 'unreal') return filter.engines.contains('unreal');
      return filter.engines.contains('other');
    }).toList();
  }

  if (filter.updatesOnly) {
    final updates = ref.watch(availableUpdatesProvider);
    result = result.where((g) => updates.containsKey(g.baseKey)).toList();
  }

  if (filter.unfetchedOnly) {
    result = result.where((g) => g.isUnfetched).toList();
  }

  if (filter.minRating > 0) {
    final ratings = ref.watch(gameRatingsProvider);
    result = result.where((g) => (ratings[g.baseKey] ?? 0) >= filter.minRating).toList();
  }

  if (filter.releasedWithinDays > 0) {
    final since = DateTime.now().subtract(Duration(days: filter.releasedWithinDays));
    result = result.where((g) {
      final released = DateTime.tryParse(g.newestMeta((v) => v.metaReleaseDate));
      return released != null && released.isAfter(since);
    }).toList();
  }

  // Status filter (only when not all statuses selected) — the same status the
  // library shows: picked by the user, or detected (see effectiveGameStatus).
  if (!filter.statuses.containsAll(allStatusIds)) {
    result = result
        .where((g) => filter.statuses.contains(effectiveGameStatus(g, ud).id))
        .toList();
  }

  // Sort
  switch (filter.sort) {
    case SortMode.alpha:
      result.sort((a, b) =>
          a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase()));
    case SortMode.developer:
      // Games with no known developer go last.
      result.sort((a, b) {
        final da = a.effectiveDeveloper.toLowerCase();
        final db = b.effectiveDeveloper.toLowerCase();
        if (da.isEmpty != db.isEmpty) return da.isEmpty ? 1 : -1;
        final byDev = da.compareTo(db);
        return byDev != 0
            ? byDev
            : a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase());
      });
    case SortMode.rating:
      // Highest first; unrated games go last.
      final ratings = ref.watch(gameRatingsProvider);
      result.sort((a, b) {
        final byRating = (ratings[b.baseKey] ?? 0).compareTo(ratings[a.baseKey] ?? 0);
        return byRating != 0
            ? byRating
            : a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase());
      });
    case SortMode.recentlyPlayed:
      result.sort((a, b) {
        final la = _latestPlay(a, ud);
        final lb = _latestPlay(b, ud);
        if (la == null && lb == null) return 0;
        if (la == null) return 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
      });
    case SortMode.playTime:
      result.sort((a, b) {
        final byTime = (ud.playtime[b.baseKey] ?? 0).compareTo(ud.playtime[a.baseKey] ?? 0);
        return byTime != 0
            ? byTime
            : a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase());
      });
    case SortMode.dateAdded:
      // Filesystem mtime of latest version folder
      result.sort((a, b) {
        final ta = _folderMtime(a);
        final tb = _folderMtime(b);
        return tb.compareTo(ta);
      });
  }

  return result;
});

/// Games that look like the same game, by baseKey, leaving out pairs the user
/// has ruled out.
final duplicatesProvider = Provider<Map<String, List<GameGroup>>>((ref) {
  final ud = ref.watch(userDataProvider);
  final games = ref
      .watch(libraryProvider)
      .groups
      .where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey))
      .toList();
  final found = <String, List<GameGroup>>{};
  for (var i = 0; i < games.length; i++) {
    for (var j = i + 1; j < games.length; j++) {
      final a = games[i];
      final b = games[j];
      if (ud.notDuplicates.contains(UserData.pairKey(a.baseKey, b.baseKey))) continue;
      if (!UpdateCheckService.looksLikeSameGame(a, b)) continue;
      found.putIfAbsent(a.baseKey, () => []).add(b);
      found.putIfAbsent(b.baseKey, () => []).add(a);
    }
  }
  return found;
});

/// How many library games the Unfetched filter would show.
final unfetchedCountProvider = Provider<int>((ref) {
  final ud = ref.watch(userDataProvider);
  return ref
      .watch(libraryProvider)
      .groups
      .where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey) && g.isUnfetched)
      .length;
});

/// Returns the merged tag set for a group:
///   • user-assigned tags stored in UserData (from 1.0 or the Properties modal)
///   • tags from every version's .vnpf/metadata.json via GameVersion.metaTags
///     (covers both 'tags_fetched' from 2.0 Fetch Metadata AND 'tags' from 1.0)
Set<String> _allTagsForGroup(GameGroup g, UserData ud) {
  final tags = <String>{...?ud.tags[g.baseKey]};
  for (final v in g.versions) {
    tags.addAll(v.metaTags);
  }
  return tags;
}

// Play sessions are recorded per game (baseKey); saves count as play too.
DateTime? _latestPlay(GameGroup g, UserData ud) => gameLastPlayedAt(g, ud);

DateTime _folderMtime(GameGroup g) {
  try {
    return g.latestVersion?.folderPath.statSync().modified ?? DateTime(0);
  } catch (_) {
    return DateTime(0);
  }
}

/// All tags in use across the library (for the filter dropdowns).
/// Merges user-assigned tags (UserData.tags) with tags_fetched from
/// each installed game version's .vnpf/metadata.json.
final allTagsProvider = Provider<List<String>>((ref) {
  final ud = ref.watch(userDataProvider);
  final groups = ref.watch(libraryProvider).groups;
  final all = <String>{};
  // 1.0 user-assigned tags stored in UserData
  for (final tags in ud.tags.values) {
    all.addAll(tags);
  }
  // Tags from metadata.json (tags_fetched 2.0 + tags 1.0 legacy) via metaTags getter
  for (final g in groups) {
    for (final v in g.versions) {
      all.addAll(v.metaTags);
    }
  }
  return all.toList()..sort();
});
