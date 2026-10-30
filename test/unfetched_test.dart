// The Unfetched filter: games with no .vnpf folder on any version.
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

GameVersion version(String v, {bool vnpf = false}) => GameVersion(
      folderName: 'Game-$v',
      folderPath: Directory('Game-$v'),
      baseKey: 'game',
      versionStr: v,
      displayName: 'Game',
      localSaveDir: Directory('saves'),
      hasVnpf: vnpf,
    );

GameGroup game(String key, List<GameVersion> versions) =>
    GameGroup(baseKey: key, displayName: key, versions: versions);

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
}

class _UserData extends UserDataNotifier {
  _UserData(super.ref, UserData data) {
    state = data;
  }
}

void main() {
  test('no .vnpf folder on any version → Unfetched', () {
    expect(game('a', [version('1')]).isUnfetched, isTrue);
    expect(game('a', [version('1'), version('2')]).isUnfetched, isTrue);
  });

  test('a .vnpf folder on any version counts, since metadata falls back across versions', () {
    expect(game('a', [version('1', vnpf: true)]).isUnfetched, isFalse);
    expect(game('a', [version('1', vnpf: true), version('2')]).isUnfetched, isFalse);
  });

  group('scanning a game folder', () {
    late Directory lib;
    setUp(() => lib = Directory.systemTemp.createTempSync('vnp_unfetched'));
    tearDown(() => lib.deleteSync(recursive: true));

    Directory gameFolder() {
      final dir = Directory(p.join(lib.path, 'Game-1.0'));
      Directory(p.join(dir.path, 'game')).createSync(recursive: true);
      return dir;
    }

    test('without a .vnpf folder', () {
      expect(scanGameVersion(gameFolder())!.hasVnpf, isFalse);
    });

    test('with a .vnpf folder', () {
      final dir = gameFolder();
      Directory(p.join(dir.path, '.vnpf')).createSync();
      expect(scanGameVersion(dir)!.hasVnpf, isTrue);
    });
  });

  test('the filter shows only unfetched games and the count skips hidden ones', () {
    final container = ProviderContainer(overrides: [
      libraryProvider.overrideWith((ref) => _Library(ref, [
            game('fetched', [version('1', vnpf: true)]),
            game('bare', [version('1')]),
            game('also-bare', [version('1')]),
            game('hidden', [version('1')]),
          ])),
      userDataProvider.overrideWith((ref) => _UserData(ref, const UserData(hidden: {'hidden'}))),
    ]);
    addTearDown(container.dispose);

    expect(container.read(unfetchedCountProvider), 2);
    expect(container.read(filteredGroupsProvider).length, 3);

    container.read(filterProvider.notifier).setUnfetchedOnly(true);
    expect(
      container.read(filteredGroupsProvider).map((g) => g.baseKey),
      unorderedEquals(['bare', 'also-bare']),
    );
  });
}
