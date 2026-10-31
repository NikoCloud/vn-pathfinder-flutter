import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/library_stats.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/models/version_path.dart';
import 'package:vn_pathfinder/providers/feed_view_provider.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/screens/feed_screen.dart';
import 'package:vn_pathfinder/screens/library_screen.dart';
import 'package:vn_pathfinder/widgets/common/art_card.dart';
import 'package:vn_pathfinder/widgets/common/finder.dart';

GameGroup game(String title, {String version = '1.0', String f95 = '', String developer = ''}) => GameGroup(
      baseKey: title.toLowerCase(),
      displayName: title,
      versions: [
        GameVersion(
          folderName: title,
          folderPath: Directory(title),
          baseKey: title.toLowerCase(),
          versionStr: version,
          displayName: title,
          localSaveDir: Directory('saves'),
          metadata: {'f95_url': f95, 'developer': developer},
        ),
      ],
    );

RawFeedItem item(
  String title, {
  String version = '1.0',
  String source = 'f95zone',
  String url = '',
  String body = '',
  DateTime? at,
}) =>
    RawFeedItem(
      id: '$source::$title',
      source: source,
      sourceLabel: source,
      title: title,
      rawBody: 'Version: $version\n$body',
      url: url.isEmpty ? 'https://example.test/threads/${title.hashCode.abs()}/' : url,
      publishedAt: at ?? DateTime(2026, 10, 30, 12),
    );

List<FeedRow> rows(List<RawFeedItem> items, List<GameGroup> groups, {Set<String> watching = const {}, Set<String> muted = const {}, Set<String> hidden = const {}, DateTime? seen}) =>
    buildFeedRows(
      items: items,
      matcher: FeedMatcher(groups, const {}),
      hiddenSites: hidden,
      watching: watching,
      muted: muted,
      seenAt: seen,
    );

void main() {
  group('Feed rows', () {
    const thread = 'https://f95zone.to/threads/some-game.123/';

    test('a linked game with a newer release says so', () {
      final row = rows([item('Some Game', version: '0.9', url: thread)], [game('Some Game', version: '0.8', f95: thread)]).single;
      expect(row.linked, isTrue);
      expect(row.newer, isTrue);
      expect(row.installed, '0.8');
    });

    test('the same version is in the library, not an update', () {
      final row = rows([item('Some Game', version: '0.8', url: thread)], [game('Some Game', version: '0.8', f95: thread)]).single;
      expect(row.inLibrary, isTrue);
      expect(row.newer, isFalse);
    });

    test('a match on the title alone never claims a new version', () {
      final row = rows([item('Guilty Pleasure', version: '2.0')], [game('Guilty Pleasure', version: '0.5')]).single;
      expect(row.inLibrary, isTrue);
      expect(row.linked, isFalse);
      expect(row.newer, isFalse);
    });

    test('muted games and hidden sites are left out', () {
      final items = [item('Keep'), item('Quiet'), item('Other Site', source: 'azc')];
      expect(rows(items, [], muted: {'quiet'}, hidden: {'azc'}).map((r) => r.item.title), ['Keep']);
    });

    test('hiding a site brings back the row a release lost to it', () {
      final at = DateTime(2026, 10, 20);
      final first = item('Some Game', source: 'azc', at: at);
      final second = item('Some Game', source: 'f95zone', at: at.add(const Duration(days: 1)));
      expect(rows([first, second], []).single.item.source, 'azc');
      expect(rows([first, second], [], hidden: {'azc'}).single.item.source, 'f95zone');
    });

    test('new means after the last Mark all seen', () {
      final seen = DateTime(2026, 10, 25);
      expect(rows([item('New', at: DateTime(2026, 10, 26))], [], seen: seen).single.fresh, isTrue);
      expect(rows([item('Old', at: DateTime(2026, 10, 24))], [], seen: seen).single.fresh, isFalse);
    });
  });

  group('Feed filters', () {
    FeedRow row(String tags, {String title = 'Some Game'}) => FeedRow(item: item(title, body: tags.isEmpty ? '' : 'Tags: $tags'), version: '');

    test('a wanted tag keeps untagged items, so no site vanishes', () {
      const filter = FeedFilter(wanted: {'romance'});
      expect(matchesFeedFilter(row('romance, comedy'), filter), isTrue);
      expect(matchesFeedFilter(row('comedy'), filter), isFalse);
      expect(matchesFeedFilter(row(''), filter), isTrue);
    });

    test('an unwanted tag removes the item', () {
      expect(matchesFeedFilter(row('romance'), const FeedFilter(unwanted: {'romance'})), isFalse);
    });

    test('search covers the title and the developer', () {
      final r = FeedRow(item: item('Some Game', body: 'Developer: Studio'), version: '');
      expect(matchesFeedFilter(r, const FeedFilter(query: 'studio')), isTrue);
      expect(matchesFeedFilter(r, const FeedFilter(query: 'nothing')), isFalse);
    });

    test('shelves sort releases by kind and by what you have', () {
      final list = [
        FeedRow(item: item('A', body: 'Kind: new'), version: ''),
        FeedRow(item: item('B', version: 'Final'), version: ''),
        FeedRow(item: item('C'), version: '', game: game('C')),
        FeedRow(item: item('D'), version: '', watching: true),
      ];
      expect(shelfRows(list, FeedShelf.newGames).single.item.title, 'A');
      expect(shelfRows(list, FeedShelf.complete).single.item.title, 'B');
      expect(shelfRows(list, FeedShelf.myGames).single.item.title, 'C');
      expect(shelfRows(list, FeedShelf.watching).single.item.title, 'D');
      expect(shelfRows(list, FeedShelf.updates).map((r) => r.item.title), ['C', 'D']);
    });

    test('a new, finished game is on both shelves', () {
      final list = [FeedRow(item: item('A', body: 'Kind: new\nKind: complete'), version: '')];
      expect(shelfRows(list, FeedShelf.newGames).length, 1);
      expect(shelfRows(list, FeedShelf.complete).length, 1);
      expect(shelfRows(list, FeedShelf.updates), isEmpty);
    });
  });

  group('Spotlight', () {
    FeedRow row(String title, {bool newer = false, String kind = ''}) => FeedRow(
          item: item(title, body: '[cover] https://example.test/$title.jpg\n$kind'),
          version: '',
          newer: newer,
        );

    test('your updates first, then new games, four at most, each once', () {
      final picks = pickSpotlight([
        row('Plain'),
        row('Fresh', kind: 'Kind: new'),
        row('Mine', newer: true),
        row('Mine', newer: true),
        row('Other'),
        row('More'),
      ]);
      expect(picks.map((r) => r.item.title), ['Mine', 'Fresh', 'Plain', 'Other']);
    });

    test('a release with no art can\'t lead', () {
      expect(pickSpotlight([FeedRow(item: item('No Art'), version: '')]), isEmpty);
    });
  });

  test('releases are grouped by day, newest group first', () {
    final now = DateTime(2026, 10, 30, 15);
    final groups = groupByDay([
      FeedRow(item: item('Today', at: now.subtract(const Duration(hours: 2))), version: ''),
      FeedRow(item: item('Yesterday', at: now.subtract(const Duration(days: 1))), version: ''),
      FeedRow(item: item('Earlier', at: now.subtract(const Duration(days: 4))), version: ''),
      FeedRow(item: item('Long ago', at: now.subtract(const Duration(days: 9))), version: ''),
    ], now: now);
    expect(groups.map((g) => g.$1), ['Today', 'Yesterday', 'Earlier this week', 'Older']);
  });

  group('version path', () {
    test('runs oldest to newest with what you have marked', () {
      final path = buildVersionPath(
        installed: ['0.7', '0.8.2'],
        changelog: ['0.9', '0.8.2', '0.8', '0.7'],
        latest: 'v0.9',
        played: '0.8.2',
      );
      expect(path.map((n) => n.version), ['0.7', '0.8', '0.8.2', 'v0.9']);
      expect(path.where((n) => n.installed).map((n) => n.version), ['0.7', '0.8.2']);
      expect(path.last.latest, isTrue);
      expect(path.singleWhere((n) => n.here).version, '0.8.2');
    });

    test('a long changelog keeps what you have and the latest', () {
      final path = buildVersionPath(
        installed: ['0.1'],
        changelog: [for (var i = 20; i > 0; i--) '0.$i'],
        latest: '0.20',
      );
      expect(path.length, 7);
      expect(path.first.version, '0.1');
      expect(path.last.version, '0.20');
    });

    test('v and no v are the same version', () {
      expect(sameVersion('v0.5', '0.5'), isTrue);
      expect(sameVersion('V.0.5', '0.5'), isTrue);
      expect(sameVersion('0.5', '0.6'), isFalse);
    });
  });

  group('weekly play', () {
    final now = DateTime(2026, 10, 30, 12); // a Friday

    test('adds up sessions by Monday-to-Sunday week, oldest first', () {
      final weeks = weeklyPlay([
        PlaySession('a', DateTime(2026, 10, 26, 9), 100), // this Monday
        PlaySession('a', DateTime(2026, 10, 30, 9), 50), // today
        PlaySession('b', DateTime(2026, 10, 25, 23), 7), // last Sunday
      ], now, weeks: 3);
      expect(weeks.map((w) => w.seconds), [0, 7, 150]);
      expect(weeks.last.start, DateTime(2026, 10, 26));
      expect(weeks.first.start, DateTime(2026, 10, 12));
    });

    test('leaves out what is too old', () {
      final weeks = weeklyPlay([PlaySession('a', DateTime(2025, 1, 1), 100)], now);
      expect(weeks.every((w) => w.seconds == 0), isTrue);
    });
  });

  test('a merged game keeps its session history', () {
    const ud = UserData(sessions: []);
    final merged = ud.copyWith(sessions: [PlaySession('a', DateTime(2026), 10)]).withGameMerged('a', 'b');
    expect(merged.sessions.single.baseKey, 'b');
  });

  test('user data keeps watch, mute and sessions across a save', () {
    final ud = UserData(watching: const {'a'}, muted: const {'b'}, sessions: [PlaySession('c', DateTime(2026, 1, 2), 30)]);
    final back = UserData.fromJson(ud.toJson());
    expect(back.watching, {'a'});
    expect(back.muted, {'b'});
    expect(back.sessions.single.seconds, 30);
  });

  group('quick find', () {
    test('library games come first, and a Feed release of one is not repeated', () {
      final hits = findGames('some', [game('Some Game')], [item('Some Game'), item('Some Other')]);
      expect(hits.map((h) => h.title), ['Some Game', 'Some Other']);
      expect(hits.first.game, isNotNull);
    });

    test('every word has to match, in any order', () {
      expect(findGames('game some', [game('Some Game')], []).length, 1);
      expect(findGames('some nothing', [game('Some Game')], []), isEmpty);
    });

    test('matches the developer too', () {
      expect(findGames('studio', [game('Some Game', developer: 'Studio')], []).length, 1);
    });
  });

  group('Library views', () {
    test('a view is recognised from the filter', () {
      expect(activeView(const FilterState()), LibraryView.all);
      expect(activeView(const FilterState(updatesOnly: true)), LibraryView.newVersion);
      expect(activeView(const FilterState(statuses: {'on-hold'})), LibraryView.onHold);
      expect(activeView(const FilterState(statuses: {'on-hold', 'skimmed'})), isNull);
    });

    test('a saved view survives a round trip', () {
      const view = FilterState(
        includeTags: ['romance'],
        statuses: {'playing'},
        sort: SortMode.playTime,
        unfetchedOnly: true,
        minRating: 4,
      );
      final back = FilterState.fromJson(view.toJson());
      expect(back.includeTags, ['romance']);
      expect(back.statuses, {'playing'});
      expect(back.sort, SortMode.playTime);
      expect(back.unfetchedOnly, isTrue);
      expect(back.minRating, 4);
    });

    test('Filters counts what the quick views don\'t show', () {
      expect(const FilterState(statuses: {'playing'}).activeFilters, 0);
      expect(const FilterState(includeTags: ['a'], showHidden: true).activeFilters, 2);
    });
  });

  group('card wall', () {
    test('fits as many cards as the minimum allows', () {
      final wall = wallColumns(1384, 272);
      expect(wall.columns, 4);
      expect(wall.cardWidth, closeTo(332.5, 0.01));
    });

    test('always leaves at least one column', () {
      expect(wallColumns(100, 272).columns, 1);
    });
  });

  test('feedTitleKey ignores version numbers and punctuation', () {
    expect(feedTitleKey("Grandma's House [v0.5]"), feedTitleKey('Grandmas House'));
    expect(feedTitleKey('Some Game v1.2.3'), 'some game');
  });
}
