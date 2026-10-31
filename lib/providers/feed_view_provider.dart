import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed_item.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../services/feed_service.dart';
import '../services/update_check_service.dart';
import 'feed_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';
import 'update_provider.dart';

enum FeedShelf {
  all('All releases'),
  newGames('New games'),
  updates('Updates'),
  complete('Complete'),
  myGames('My games'),
  watching('Watching');

  const FeedShelf(this.label);
  final String label;
}

/// Tri-state tag filtering: a tag is ignored, wanted or unwanted.
class FeedFilter {
  final FeedShelf shelf;
  final String query;

  /// Sites left out. Empty means every enabled site.
  final Set<String> hiddenSites;
  final Set<String> wanted;
  final Set<String> unwanted;
  final bool list;

  const FeedFilter({
    this.shelf = FeedShelf.all,
    this.query = '',
    this.hiddenSites = const {},
    this.wanted = const {},
    this.unwanted = const {},
    this.list = false,
  });

  int get active => hiddenSites.length + wanted.length + unwanted.length;

  FeedFilter copyWith({
    FeedShelf? shelf,
    String? query,
    Set<String>? hiddenSites,
    Set<String>? wanted,
    Set<String>? unwanted,
    bool? list,
  }) =>
      FeedFilter(
        shelf: shelf ?? this.shelf,
        query: query ?? this.query,
        hiddenSites: hiddenSites ?? this.hiddenSites,
        wanted: wanted ?? this.wanted,
        unwanted: unwanted ?? this.unwanted,
        list: list ?? this.list,
      );
}

final feedFilterProvider = StateProvider<FeedFilter>((ref) => const FeedFilter());

/// A Feed item and what it means for this library.
class FeedRow {
  final RawFeedItem item;
  final String version;
  final GameGroup? game;

  /// [game] was found through a thread link, so version comparisons are safe.
  /// A match on the title alone only says "In library".
  final bool linked;

  /// This release is newer than the newest version installed.
  final bool newer;
  final bool watching;
  final bool fresh;

  const FeedRow({
    required this.item,
    required this.version,
    this.game,
    this.linked = false,
    this.newer = false,
    this.watching = false,
    this.fresh = false,
  });

  bool get inLibrary => game != null;

  String get installed => game?.latestVersion?.versionStr ?? '';
}

/// Finds library games for Feed items: by thread ID, then by title.
class FeedMatcher {
  final _byThread = <(String, int), GameGroup>{};
  final _byTitle = <String, GameGroup>{};

  FeedMatcher(Iterable<GameGroup> groups, Map<String, int> titleLinks) {
    void link(String source, String url, GameGroup g) {
      final id = UpdateCheckService.threadId(url);
      if (id != null) _byThread[(source, id)] = g;
    }

    for (final g in groups) {
      if (g.versions.isEmpty) continue;
      link('f95zone', g.newestMeta((v) => v.metaF95Url), g);
      link('lewdcorner', g.newestMeta((v) => v.metaLcUrl), g);
      link('azc', g.newestMeta((v) => v.metaAzcUrl), g);
      final found = titleLinks[g.baseKey];
      if (found != null) _byThread.putIfAbsent(('f95zone', found), () => g);
      final key = feedTitleKey(g.effectiveTitle);
      if (key.isNotEmpty) _byTitle.putIfAbsent(key, () => g);
    }
  }

  (GameGroup?, bool linked) match(RawFeedItem item) {
    final id = UpdateCheckService.threadId(item.url);
    final linked = id == null ? null : _byThread[(item.source, id)];
    if (linked != null) return (linked, true);
    return (_byTitle[feedTitleKey(item.title)], false);
  }
}

/// Every Feed item for the enabled sites, minus the sites filtered out and the
/// games muted, with one row per release across what's left.
List<FeedRow> buildFeedRows({
  required List<RawFeedItem> items,
  required FeedMatcher matcher,
  required Set<String> hiddenSites,
  required Set<String> watching,
  required Set<String> muted,
  required DateTime? seenAt,
}) {
  final visible = items.where((i) => !hiddenSites.contains(i.source) && !muted.contains(feedTitleKey(i.title)));
  return [
    for (final item in FeedService.deduplicate(visible.toList()))
      () {
        final (game, linked) = matcher.match(item);
        final version = extractFeedVersion(item) ?? '';
        final installed = game?.latestVersion?.versionStr ?? '';
        final at = item.publishedAt;
        return FeedRow(
          item: item,
          version: version,
          game: game,
          linked: linked,
          newer: linked && installed.isNotEmpty && isClearlyNewer(version, installed),
          watching: watching.contains(feedTitleKey(item.title)),
          fresh: at != null && (seenAt == null || at.isAfter(seenAt)),
        );
      }(),
  ];
}

/// [rows] narrowed to one shelf.
List<FeedRow> shelfRows(List<FeedRow> rows, FeedShelf shelf) => switch (shelf) {
      FeedShelf.all => rows,
      FeedShelf.newGames => rows.where((r) => r.item.isNewGame).toList(),
      FeedShelf.updates => rows.where((r) => r.item.kind == FeedKind.update).toList(),
      FeedShelf.complete => rows.where((r) => r.item.isComplete).toList(),
      FeedShelf.myGames => rows.where((r) => r.inLibrary).toList(),
      FeedShelf.watching => rows.where((r) => r.watching).toList(),
    };

/// Search and tags. Items with no tags stay visible when a tag is wanted,
/// because some sites' lists don't carry any.
bool matchesFeedFilter(FeedRow row, FeedFilter filter) {
  final query = filter.query.trim().toLowerCase();
  final item = row.item;
  if (query.isNotEmpty &&
      !item.title.toLowerCase().contains(query) &&
      !item.developer.toLowerCase().contains(query)) {
    return false;
  }
  final tags = item.tags.map((t) => t.toLowerCase()).toSet();
  if (filter.unwanted.any(tags.contains)) return false;
  if (filter.wanted.isNotEmpty && tags.isNotEmpty && !filter.wanted.every(tags.contains)) return false;
  return true;
}

final feedAllRowsProvider = Provider<List<FeedRow>>((ref) {
  final check = ref.watch(updateCheckProvider);
  final groups = ref.watch(libraryGroupsProvider);
  final ud = ref.watch(userDataProvider);
  final seen = ref.watch(settingsProvider.select((s) => s.feedSeenAt));
  final hidden = ref.watch(feedFilterProvider.select((f) => f.hiddenSites));
  return buildFeedRows(
    items: ref.watch(feedProvider).items,
    matcher: FeedMatcher(groups, check.titleLinks),
    hiddenSites: hidden,
    watching: ud.watching,
    muted: ud.muted,
    seenAt: DateTime.tryParse(seen ?? ''),
  );
});

/// What the Feed tab shows.
final feedRowsProvider = Provider<List<FeedRow>>((ref) {
  final filter = ref.watch(feedFilterProvider);
  return shelfRows(ref.watch(feedAllRowsProvider), filter.shelf)
      .where((r) => matchesFeedFilter(r, filter))
      .toList();
});

/// The Spotlight: updates for your games first, then new games.
List<FeedRow> pickSpotlight(List<FeedRow> rows) {
  final picks = <FeedRow>[];
  final titles = <String>{};
  void take(Iterable<FeedRow> from) {
    for (final row in from) {
      if (picks.length == 4) return;
      if (row.item.coverUrl.isEmpty) continue;
      if (titles.add(feedTitleKey(row.item.title))) picks.add(row);
    }
  }

  take(rows.where((r) => r.newer));
  take(rows.where((r) => r.item.isNewGame));
  take(rows);
  return picks;
}

/// The Feed items for a title, newest first, across every site.
final feedForGameProvider = Provider.family<List<RawFeedItem>, String>((ref, titleKey) {
  return ref.watch(feedProvider).items.where((i) => feedTitleKey(i.title) == titleKey).toList();
});
