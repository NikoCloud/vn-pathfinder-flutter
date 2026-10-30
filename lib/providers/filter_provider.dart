import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/user_data.dart';
import 'library_provider.dart';
import 'update_provider.dart';

enum SortMode { alpha, recentlyPlayed, dateAdded }
enum SearchMode { title, creator }
enum TagMatchMode { any, all } // OR / AND

const _allStatusIds = {
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

  const FilterState({
    this.query = '',
    this.searchMode = SearchMode.title,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.tagMatchMode = TagMatchMode.any,
    this.engines = const {'renpy', 'rpgm', 'unity', 'html', 'unreal', 'other'},
    this.statuses = _allStatusIds,
    this.sort = SortMode.alpha,
    this.updatesOnly = false,
    this.unfetchedOnly = false,
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

  void setUpdatesOnly(bool v) => state = state.copyWith(updatesOnly: v);
  void setUnfetchedOnly(bool v) => state = state.copyWith(unfetchedOnly: v);

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

  if (filter.updatesOnly) {
    final updates = ref.watch(availableUpdatesProvider);
    result = result.where((g) => updates.containsKey(g.baseKey)).toList();
  }

  if (filter.unfetchedOnly) {
    result = result.where((g) => g.isUnfetched).toList();
  }

  // Status filter (only when not all statuses selected) — the same status the
  // library shows: picked by the user, or detected (see effectiveGameStatus).
  if (!filter.statuses.containsAll(_allStatusIds)) {
    result = result
        .where((g) => filter.statuses.contains(effectiveGameStatus(g, ud).id))
        .toList();
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
