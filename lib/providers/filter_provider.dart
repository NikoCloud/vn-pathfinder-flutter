import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../models/user_data.dart';
import 'library_provider.dart';

enum SortMode { alpha, recentlyPlayed, dateAdded }
enum SearchMode { title, creator }
enum TagMatchMode { any, all } // OR / AND

class FilterState {
  final String query;
  final SearchMode searchMode;
  final List<String> includeTags;
  final List<String> excludeTags;
  final TagMatchMode tagMatchMode;
  final Set<String> engines;      // 'renpy','rpgm','unity','html','unreal','other'
  final Set<String> statuses;     // 'playing','completed','on-hold','unplayed','abandoned'
  final SortMode sort;

  const FilterState({
    this.query = '',
    this.searchMode = SearchMode.title,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.tagMatchMode = TagMatchMode.any,
    this.engines = const {'renpy', 'rpgm', 'unity', 'html', 'unreal', 'other'},
    this.statuses = const {'playing', 'completed', 'on-hold', 'unplayed', 'abandoned'},
    this.sort = SortMode.alpha,
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
  }) => FilterState(
    query: query ?? this.query,
    searchMode: searchMode ?? this.searchMode,
    includeTags: includeTags ?? this.includeTags,
    excludeTags: excludeTags ?? this.excludeTags,
    tagMatchMode: tagMatchMode ?? this.tagMatchMode,
    engines: engines ?? this.engines,
    statuses: statuses ?? this.statuses,
    sort: sort ?? this.sort,
  );

  bool get isActive =>
      query.isNotEmpty ||
      includeTags.isNotEmpty ||
      excludeTags.isNotEmpty;
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

  void toggleStatus(String status, bool enabled) {
    final s = Set<String>.from(state.statuses);
    enabled ? s.add(status) : s.remove(status);
    state = state.copyWith(statuses: s);
  }

  void reset() => state = const FilterState();
}

final filterProvider =
    StateNotifierProvider<FilterNotifier, FilterState>(
  (ref) => FilterNotifier(),
);

// ── Filtered + sorted game list ───────────────────────────────────────────────

final filteredGroupsProvider = Provider<List<GameGroup>>((ref) {
  final groups = ref.watch(libraryProvider).groups;
  final filter = ref.watch(filterProvider);
  final ud = ref.watch(userDataProvider);

  // Exclude archive-only groups (no installed game versions) from the library.
  var result = groups
      .where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey))
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

  // Status filter (only when not all statuses selected)
  const allStatuses = {'playing', 'completed', 'on-hold', 'unplayed', 'abandoned'};
  if (!filter.statuses.containsAll(allStatuses)) {
    result = result.where((g) {
      final explicit = ud.status[g.baseKey];
      final String gameStatus;
      if (explicit != null && explicit.isNotEmpty) {
        gameStatus = explicit;
      } else {
        // Derive: any playtime → playing, otherwise → unplayed
        final hasPlay = g.versions.any((v) =>
            (ud.playtime[v.folderName] ?? 0) > 0 ||
            ud.manualPlayed.contains(v.folderName));
        gameStatus = hasPlay ? 'playing' : 'unplayed';
      }
      return filter.statuses.contains(gameStatus);
    }).toList();
  }

  // Sort
  switch (filter.sort) {
    case SortMode.alpha:
      result.sort((a, b) =>
          a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase()));
    case SortMode.recentlyPlayed:
      result.sort((a, b) {
        final la = _latestPlay(a, ud);
        final lb = _latestPlay(b, ud);
        if (la == null && lb == null) return 0;
        if (la == null) return 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
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

DateTime? _latestPlay(GameGroup g, UserData ud) {
  DateTime? latest;
  for (final v in g.versions) {
    final iso = ud.lastPlayed[v.folderName];
    if (iso == null) continue;
    try {
      final dt = DateTime.parse(iso);
      if (latest == null || dt.isAfter(latest)) latest = dt;
    } catch (_) {}
  }
  return latest;
}

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
