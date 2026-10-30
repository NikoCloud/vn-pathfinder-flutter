// Version parsing, ordering, display and extracted-folder naming. Folder names
// are modelled on real library folders.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/utils/formatters.dart';

String versionOf(String folder) => parseFolderName(folder).$2;

GameVersion version(String v, [Map<String, dynamic> metadata = const {}]) => GameVersion(
      folderName: 'Game-$v',
      folderPath: Directory('Game-$v'),
      baseKey: 'game',
      versionStr: v,
      displayName: 'Game',
      localSaveDir: Directory('saves'),
      metadata: metadata,
    );

void main() {
  test('fmtVersion: one display form', () {
    expect(fmtVersion('0.12.7'), 'v0.12.7');
    expect(fmtVersion('v0.03.27'), 'v0.03.27');
    expect(fmtVersion('V0.2'), 'v0.2');
    expect(fmtVersion('v.0.14.0'), 'v0.14.0');
    expect(fmtVersion('Chapter-1'), 'Chapter 1');
    expect(fmtVersion('Episode_10'), 'Episode 10');
    expect(fmtVersion('Final'), 'Final');
    expect(fmtVersion(''), 'Unknown');
  });

  test('parser keeps Chapter/Episode numbers and drops the platform tag', () {
    expect(versionOf('AdventuresofTheFHGuy-Chapter-1-pc'), 'Chapter-1');
    expect(versionOf('Littlegreenhill-Chapter1-pc'), 'Chapter1');
    expect(versionOf('Littlegreenhill-Chapter2_Version_0.1-pc'), 'Chapter2_Version_0.1');
    expect(versionOf('FamilyFaring-Episode-10-pc'), 'Episode-10');
    expect(versionOf('SweetAffection-0.12.7-pc'), '0.12.7');
    expect(versionOf('Betweensalvationandabyss-Final-pc'), 'Final');
    // "_"-joined platform tags are dropped like "-" ones.
    expect(versionOf('Beauty_and_the_Thug_v0.4.8_Win'), 'v0.4.8');
    expect(versionOf('AFamilyVenture-0.09_V4_Alpha-pc'), '0.09_V4_Alpha');
  });

  test('a space separates dotted versions only', () {
    expect(parseFolderName('New in City 0.3.3'), ('newincity', '0.3.3', 'New in City'));
    expect(parseFolderName('BBUltimate v0.11').$1, parseFolderName('BBUltimate v0.8').$1);
    expect(versionOf('School, Love & Friends v2.15'), 'v2.15');
    // Numbers that are part of the title stay there.
    expect(parseFolderName('Persona 4 Rise Gaiden'), ('persona4risegaiden', '', 'Persona 4 Rise Gaiden'));
    expect(versionOf('Cyberpunk 2077'), '');
    expect(versionOf('Love Story v2'), '');
  });

  test('ordering: unknown < Demo < numbers < Final; pre-releases and letters', () {
    final sorted = ['Final', '0.5b', '', '0.5', '1.0', 'Demo', '0.5a', '0.5 Beta', '0.11.12', '0.5 Alpha', '0.12.7']
      ..sort(compareVersionStrings);
    expect(sorted, ['', 'Demo', '0.5 Alpha', '0.5 Beta', '0.5', '0.5a', '0.5b', '0.11.12', '0.12.7', '1.0', 'Final']);
    expect(compareVersionStrings('Act.4.3.Beta', 'Act.4.3.1.Beta'), lessThan(0));
  });

  test('text metadata falls back to the newest version that has it', () {
    final group = GameGroup(baseKey: 'game', displayName: 'Game', versions: [
      version('0.11.12', {'title': 'Sweet Affection', 'synopsis': 'Old synopsis', 'tags_fetched': ['romance']}),
      version('0.12.7'), // just installed: no .vnpf/metadata.json yet
    ]);
    expect(group.effectiveTitle, 'Sweet Affection');
    expect(group.newestMeta((v) => v.metaSynopsis), 'Old synopsis');
    expect(group.newestMetaTags, ['romance']);
  });

  group('planExtractFolderName', () {
    test('keeps the more specific version (archive 4.3.1 vs inner 4.3)', () {
      expect(
        planExtractFolderName(
            archiveStem: 'WhoremongerNTE-Act.4.3.1.Beta-pc', innerFolder: 'WhoremongerNTE-Act.4.3.Beta-pc'),
        'WhoremongerNTE-Act.4.3.1.Beta',
      );
    });

    test('drops platform tags and junk; inner title wins a tie', () {
      expect(
        planExtractFolderName(
            archiveStem: 'MMA_Life_simulator-1.1.0-win-Cracked', innerFolder: 'MMA Life simulator-1.1.0-win'),
        'MMA Life simulator-1.1.0',
      );
      expect(
        planExtractFolderName(archiveStem: 'BuriedDesires-0.5-pc', innerFolder: 'BuriedDesires-0.5-pc'),
        'BuriedDesires-0.5',
      );
    });

    test('version from the archive when the inner folder has none', () {
      expect(planExtractFolderName(archiveStem: 'GameName_v1.2_compressed', innerFolder: 'Game Name'),
          'Game Name-v1.2');
    });

    test('generic inner folders are ignored', () {
      expect(planExtractFolderName(archiveStem: 'SweetAffection-0.13.0-pc', innerFolder: 'game'),
          'SweetAffection-0.13.0');
    });

    test('a title matching a library game wins, so updates join it', () {
      expect(
        planExtractFolderName(
          archiveStem: 'Sweet_Affection-0.13.0-pc',
          innerFolder: 'SA-0.13.0-pc',
          libraryKeys: {'sweetaffection'},
        ),
        'Sweet Affection-0.13.0',
      );
    });

    test('no inner folder: just cleans up the archive name', () {
      expect(planExtractFolderName(archiveStem: 'AFamilyVenture-0.09_V4_Alpha-pc'), 'AFamilyVenture-0.09_V4_Alpha');
    });

    test('planned names parse back to the same game and version', () {
      final planned = planExtractFolderName(
          archiveStem: 'WorldsCrossingAcademy-1.5.0.0-pc', innerFolder: 'WorldsCrossingAcademy-1.5.0.0-pc');
      expect(parseFolderName(planned), ('worldscrossingacademy', '1.5.0.0', 'Worlds Crossing Academy'));
    });
  });
}
