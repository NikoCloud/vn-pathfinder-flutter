// Small pieces of library behaviour: hover cards, sorting, retries, versions.
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/services/scraping_service.dart';

GameGroup game(String title, {String developer = '', double? rating, String released = ''}) => GameGroup(
      baseKey: title.toLowerCase(),
      displayName: title,
      versions: [
        GameVersion(
          folderName: title,
          folderPath: Directory(title),
          baseKey: title.toLowerCase(),
          versionStr: '1.0',
          displayName: title,
          localSaveDir: Directory('saves'),
          metadata: {
            'developer': developer,
            'rating': ?rating,
            'release_date': released,
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
  _UserData(super.ref) : super(initial: const UserData());
  @override
  Future<void> save() async {}
}

ProviderContainer library(List<GameGroup> groups) {
  final c = ProviderContainer(overrides: [
    libraryProvider.overrideWith((ref) => _Library(ref, groups)),
    userDataProvider.overrideWith((ref) => _UserData(ref)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('sorting by developer groups studios, with unknown ones last', () {
    final c = library([
      game('Zebra', developer: 'Alpha'),
      game('Mid'),
      game('Apple', developer: 'Beta'),
      game('Bison', developer: 'Alpha'),
    ]);
    c.read(filterProvider.notifier).setSort(SortMode.developer);
    expect(c.read(filteredGroupsProvider).map((g) => g.displayName), ['Bison', 'Zebra', 'Apple', 'Mid']);
  });

  group('retryOnce', () {
    test('tries a second time after a failure', () async {
      var calls = 0;
      final r = await MetadataService.retryOnce(() async {
        if (++calls == 1) throw const ScrapingException('LewdCorner returned an empty page.');
        return 'ok';
      }, delay: Duration.zero);
      expect(r, 'ok');
      expect(calls, 2);
    });

    test('gives up after the second failure', () async {
      var calls = 0;
      await expectLater(
        MetadataService.retryOnce<String>(() async {
          calls++;
          throw 'network down';
        }, delay: Duration.zero),
        throwsA('network down'),
      );
      expect(calls, 2);
    });

    test('a login problem is not retried', () async {
      var calls = 0;
      await expectLater(
        MetadataService.retryOnce<String>(() async {
          calls++;
          throw const ScrapingException('Not logged in to F95Zone');
        }, delay: Duration.zero),
        throwsA(isA<ScrapingException>()),
      );
      expect(calls, 1);
    });
  });

  group('A.-style versions', () {
    test('are read as the version, so they join the same game', () {
      expect(parseFolderName('Some Game A.2.0.7.2').$2, 'A.2.0.7.2');
      expect(parseFolderName('Some Game A.2.0.7.2').$1, parseFolderName('Some Game-2.0.4-pc').$1);
      expect(parseFolderName('SomeGame-A.1.2-pc').$2, 'A.1.2');
    });

    test('words starting with A are left alone', () {
      expect(parseFolderName('Game A Story-1.0-pc').$2, '1.0');
      expect(parseFolderName('Game A Story-1.0-pc').$3, contains('Story'));
    });
  });
}
