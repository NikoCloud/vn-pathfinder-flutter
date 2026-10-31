// Merging two library entries the scanner can't tell are the same game.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/services/update_check_service.dart';

GameGroup entry(String key, String title, {Map<String, dynamic> meta = const {}}) => GameGroup(
      baseKey: key,
      displayName: title,
      versions: [
        GameVersion(
          folderName: '$key-1.0',
          folderPath: Directory(key),
          baseKey: key,
          versionStr: '1.0',
          displayName: title,
          localSaveDir: Directory('saves'),
          metadata: meta,
        ),
      ],
    );

void main() {
  group('scanning with merges', () {
    late Directory lib;
    setUp(() => lib = Directory.systemTemp.createTempSync('vnp_merge'));
    tearDown(() => lib.deleteSync(recursive: true));

    void folder(String name) => Directory(p.join(lib.path, name, 'game')).createSync(recursive: true);
    String key(String name) => parseFolderName(name).$1;

    test('merged folders become versions of one game, in version order', () async {
      folder('LightofmyLife-1.0.4-pc');
      folder('LightofmyLifeS2-0.9.2-pc');
      folder('Other-1.0-pc');
      expect((await ScannerService.scanAll(lib)).length, 3);

      final source = key('LightofmyLifeS2-0.9.2-pc');
      final target = key('LightofmyLife-1.0.4-pc');
      final groups = await ScannerService.scanAll(lib, merges: {source: target});

      expect(groups.length, 2);
      final merged = groups.singleWhere((g) => g.baseKey == target);
      expect(merged.versions.map((v) => v.folderName),
          ['LightofmyLifeS2-0.9.2-pc', 'LightofmyLife-1.0.4-pc']);
      // A version remembers its own game, which is how it can be separated.
      expect(merged.versions.first.baseKey, source);
    });

    test('a new version of the merged game joins automatically', () async {
      folder('LightofmyLife-1.0.4-pc');
      folder('LightofmyLifeS2-0.9.2-pc');
      folder('LightofmyLifeS2-0.10.2-pc');
      final groups = await ScannerService.scanAll(lib,
          merges: {key('LightofmyLifeS2-0.9.2-pc'): key('LightofmyLife-1.0.4-pc')});
      expect(groups.single.versions.length, 3);
    });

    test('removing the merge makes them separate again', () async {
      folder('LightofmyLife-1.0.4-pc');
      folder('LightofmyLifeS2-0.9.2-pc');
      final ud = const UserData().withGameMerged(
          key('LightofmyLifeS2-0.9.2-pc'), key('LightofmyLife-1.0.4-pc'));
      expect((await ScannerService.scanAll(lib, merges: ud.gameMerges)).length, 1);
      final undone = ud.copyWith(gameMerges: {...ud.gameMerges}..remove(key('LightofmyLifeS2-0.9.2-pc')));
      expect((await ScannerService.scanAll(lib, merges: undone.gameMerges)).length, 2);
    });

    test('an archive of the merged game stays attached to it', () async {
      folder('Game-1.0-pc');
      folder('GameTypo-0.5-pc');
      File(p.join(lib.path, 'GameTypo-0.6-pc.zip')).writeAsBytesSync([0]);
      final groups = await ScannerService.scanAll(lib, merges: {key('GameTypo-0.5-pc'): key('Game-1.0-pc')});
      expect(groups.single.archives.length, 1);
    });
  });

  group('withGameMerged', () {
    const source = 'typo', target = 'game';

    test('play history is combined', () {
      final ud = const UserData(
        playtime: {source: 100, target: 50},
        playCount: {source: 2, target: 3},
        lastPlayed: {source: '2026-10-01T10:00:00', target: '2026-09-01T10:00:00'},
        lastPlayedVersion: {source: '0.9', target: '1.0'},
      ).withGameMerged(source, target);
      expect(ud.playtime, {target: 150});
      expect(ud.playCount, {target: 5});
      expect(ud.lastPlayed, {target: '2026-10-01T10:00:00'});
      expect(ud.lastPlayedVersion, {target: '0.9'});
    });

    test('data only the merged-in game had moves across', () {
      final ud = const UserData(
        notes: {source: 'note'},
        tags: {source: ['a']},
        status: {source: 'completed'},
        customArt: {source: 'art.png'},
      ).withGameMerged(source, target);
      expect(ud.notes, {target: 'note'});
      expect(ud.tags, {target: ['a']});
      expect(ud.status, {target: 'completed'});
      expect(ud.customArt, {target: 'art.png'});
    });

    test('where both have a value the target keeps its own, and notes and tags combine', () {
      final ud = const UserData(
        notes: {source: 'second', target: 'first'},
        tags: {source: ['a', 'b'], target: ['b', 'c']},
        status: {source: 'completed', target: 'on-hold'},
        customDisplayNames: {source: 'Typo', target: 'Game'},
      ).withGameMerged(source, target);
      expect(ud.notes, {target: 'first\n\nsecond'});
      expect(ud.tags[target], unorderedEquals(['a', 'b', 'c']));
      expect(ud.status, {target: 'on-hold'});
      expect(ud.customDisplayNames, {target: 'Game'});
    });

    test('mod state follows the game', () {
      final ud = const UserData(
        appliedPatches: {'$source::0.9': {'mod.rpa': true}, 'other::1.0': {'x.rpa': false}},
        patchAssignments: {'mod.zip': source},
      ).withGameMerged(source, target);
      expect(ud.appliedPatches.keys, unorderedEquals(['$target::0.9', 'other::1.0']));
      expect(ud.patchAssignments, {'mod.zip': target});
    });

    test('merging a merged game keeps every folder together', () {
      final ud = const UserData().withGameMerged('a', 'b').withGameMerged('b', 'c');
      expect(ud.gameMerges, {'a': 'c', 'b': 'c'});
    });

    test('a merge survives saving and loading', () {
      final ud = const UserData().withGameMerged(source, target);
      expect(UserData.fromJson(ud.toJson()).gameMerges, {source: target});
    });
  });

  group('looksLikeSameGame', () {
    const f95 = 'https://f95zone.to/threads/light-of-my-life.29628/';

    test('the same forum thread, even with different titles', () {
      expect(
        UpdateCheckService.looksLikeSameGame(
          entry('a', 'Long Road Home', meta: {'f95_url': f95}),
          entry('b', 'Long Road Home S2', meta: {'f95_url': f95}),
        ),
        isTrue,
      );
    });

    test('the same title, ignoring punctuation', () {
      expect(
        UpdateCheckService.looksLikeSameGame(entry('a', "Grandma's House"), entry('b', 'Grandmas House')),
        isTrue,
      );
    });

    test('unrelated games', () {
      expect(UpdateCheckService.looksLikeSameGame(entry('a', 'One'), entry('b', 'Two')), isFalse);
    });
  });
}
