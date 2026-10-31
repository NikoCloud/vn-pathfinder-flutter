// Gallery files, library stats, ratings, tags and duplicate prompts.
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_status.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/library_stats.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/services/gallery_service.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';

GameGroup game(String title, {String developer = '', double? rating, String released = '', String f95 = ''}) =>
    GameGroup(
      baseKey: title.toLowerCase(),
      displayName: title,
      versions: [
        GameVersion(
          folderName: '$title-1.0',
          folderPath: Directory(title),
          baseKey: title.toLowerCase(),
          versionStr: '1.0',
          displayName: title,
          localSaveDir: Directory('saves'),
          metadata: {
            'developer': developer,
            'rating': ?rating,
            'release_date': released,
            'f95_url': f95,
          },
        ),
      ],
    );

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
}

class _UserData extends UserDataNotifier {
  _UserData(super.ref, UserData data) : super(initial: data);
  @override
  Future<void> save() async {}
}

ProviderContainer library(List<GameGroup> groups, [UserData data = const UserData()]) {
  final c = ProviderContainer(overrides: [
    libraryProvider.overrideWith((ref) => _Library(ref, groups)),
    userDataProvider.overrideWith((ref) => _UserData(ref, data)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('gallery', () {
    late Directory vnpf;
    setUp(() {
      vnpf = Directory.systemTemp.createTempSync('vnp_gallery');
      File(p.join(vnpf.path, 'cover.jpg')).writeAsStringSync('cover');
      for (final n in [1, 2, 10]) {
        File(p.join(vnpf.path, 'screenshot_$n.png')).writeAsStringSync('shot$n');
      }
    });
    tearDown(() => vnpf.deleteSync(recursive: true));

    List<String> contents() => GalleryService.screenshots(vnpf).map((f) => f.readAsStringSync()).toList();
    List<String> names() => GalleryService.screenshots(vnpf).map((f) => p.basename(f.path)).toList();

    test('sorts by number, so 2 comes before 10', () {
      expect(contents(), ['shot1', 'shot2', 'shot10']);
    });

    test('reordering renames the files into the new order', () {
      final shots = GalleryService.screenshots(vnpf);
      GalleryService.reorder(vnpf, [shots[2], shots[0], shots[1]]);
      expect(contents(), ['shot10', 'shot1', 'shot2']);
      expect(names(), ['screenshot_1.png', 'screenshot_2.png', 'screenshot_3.png']);
    });

    test('a screenshot can become the cover, and the old cover takes its place', () {
      GalleryService.setCover(vnpf, GalleryService.screenshots(vnpf)[1]);
      expect(GalleryService.cover(vnpf)!.readAsStringSync(), 'shot2');
      expect(contents(), ['shot1', 'cover', 'shot10']);
      expect(p.extension(GalleryService.cover(vnpf)!.path), '.png');
    });

    test('removing an image closes the gap', () {
      GalleryService.remove(vnpf, GalleryService.screenshots(vnpf)[0]);
      expect(contents(), ['shot2', 'shot10']);
      expect(names(), ['screenshot_1.png', 'screenshot_2.png']);
    });

    test('added images join the end', () {
      final extra = File(p.join(vnpf.parent.path, 'vnp_extra_${vnpf.hashCode}.JPG'))..writeAsStringSync('new');
      addTearDown(extra.deleteSync);
      GalleryService.add(vnpf, [extra]);
      expect(contents(), ['shot1', 'shot2', 'shot10', 'new']);
      expect(names().last, 'screenshot_11.jpg');
    });

    test('with no cover, the first added image becomes the cover', () {
      GalleryService.cover(vnpf)!.deleteSync();
      final a = File(p.join(vnpf.parent.path, 'vnp_a_${vnpf.hashCode}.png'))..writeAsStringSync('a');
      final b = File(p.join(vnpf.parent.path, 'vnp_b_${vnpf.hashCode}.png'))..writeAsStringSync('b');
      addTearDown(a.deleteSync);
      addTearDown(b.deleteSync);
      GalleryService.add(vnpf, [a, b]);
      expect(GalleryService.cover(vnpf)!.readAsStringSync(), 'a');
      expect(contents().last, 'b');
    });
  });

  group('LibraryStats', () {
    final groups = [
      game('One', developer: 'Studio'),
      game('Two', developer: 'Studio'),
      game('Three', developer: 'Other'),
      game('Hidden', developer: 'Other'),
      const GameGroup(baseKey: 'archive', displayName: 'Archive only'),
    ];
    const ud = UserData(
      hidden: {'hidden'},
      playtime: {'one': 3600, 'three': 7200, 'hidden': 999999},
      status: {'two': 'completed'},
    );
    final stats = LibraryStats.from(groups, ud);

    test('counts installed, visible games only', () {
      expect(stats.games, 3);
      expect(stats.versions, 3);
      expect(stats.totalSeconds, 10800);
    });

    test('lists the most played first', () {
      expect(stats.mostPlayed.map((g) => g.title), ['Three', 'One']);
    });

    test('ranks developers by number of games', () {
      expect(stats.topDevelopers.first, (developer: 'Studio', games: 2, seconds: 3600));
    });

    test('breaks down by status', () {
      expect(stats.byStatus[GameStatus.completed], 1);
      expect(stats.byStatus[GameStatus.playing], 2);
    });
  });

  group('ratings', () {
    final groups = [
      game('Low', rating: 2.5),
      game('High', rating: 4.5),
      game('Mid', rating: 3.5),
      game('None'),
    ];

    test('sort highest first, with unrated last', () {
      final c = library(groups);
      c.read(filterProvider.notifier).setSort(SortMode.rating);
      expect(c.read(filteredGroupsProvider).map((g) => g.displayName), ['High', 'Mid', 'Low', 'None']);
    });

    test('filter by a minimum', () {
      final c = library(groups);
      c.read(filterProvider.notifier).setMinRating(3);
      expect(c.read(filteredGroupsProvider).map((g) => g.displayName), unorderedEquals(['High', 'Mid']));
    });
  });

  test('the release date filter skips old and undated games', () {
    final recent = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
    final c = library([game('New', released: recent), game('Old', released: '2019-01-01'), game('Undated')]);
    c.read(filterProvider.notifier).setReleasedWithinDays(365);
    expect(c.read(filteredGroupsProvider).map((g) => g.displayName), ['New']);
  });

  group('duplicate prompts', () {
    const thread = 'https://f95zone.to/threads/game.1/';

    test('pair up games sharing a thread', () {
      final c = library([game('Game', f95: thread), game('Game S2', f95: thread), game('Other')]);
      final found = c.read(duplicatesProvider);
      expect(found['game']!.single.baseKey, 'game s2');
      expect(found['game s2']!.single.baseKey, 'game');
      expect(found.containsKey('other'), isFalse);
    });

    test('stay gone once dismissed', () {
      final dismissed = UserData(notDuplicates: {UserData.pairKey('game', 'game s2')});
      final c = library([game('Game', f95: thread), game('Game S2', f95: thread)], dismissed);
      expect(c.read(duplicatesProvider), isEmpty);
    });

    test('the dismissed list survives saving', () {
      final data = UserData(notDuplicates: {UserData.pairKey('b', 'a')});
      expect(UserData.fromJson(data.toJson()).notDuplicates, {'a|b'});
    });
  });

  group('image picks in Fetch Metadata', () {
    const result = MetadataResult(
      provider: 'x',
      id: 'x',
      title: 'x',
      developer: '',
      sourceUrl: '',
      coverUrl: 'a',
      screenshotUrls: ['b', 'c', 'd'],
      rating: 4.2,
    );

    test('any image can be the cover', () {
      final r = result.withImages(cover: 'c');
      expect(r.coverUrl, 'c');
      expect(r.screenshotUrls, ['a', 'b', 'd']);
      expect(r.rating, 4.2);
    });

    test('removed images are left out', () {
      final r = result.withImages(removed: {'a', 'd'});
      expect(r.coverUrl, 'b');
      expect(r.screenshotUrls, ['c']);
    });

    test('a removed cover pick falls back to the first image left', () {
      expect(result.withImages(cover: 'c', removed: {'c'}).coverUrl, 'a');
    });

    test('removing everything leaves nothing to download', () {
      final r = result.withImages(removed: {'a', 'b', 'c', 'd'});
      expect(r.coverUrl, '');
      expect(r.screenshotUrls, isEmpty);
    });
  });
}
