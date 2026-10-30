// Status detection and the user's picks — see lib/models/game_status.dart.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_status.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';

final day1 = DateTime(2026, 10, 1, 20);

GameVersion version(String v, [SaveInfo saves = const SaveInfo()]) => GameVersion(
      folderName: 'Game-$v',
      folderPath: Directory('Game-$v'),
      baseKey: 'game',
      versionStr: v,
      displayName: 'Game',
      localSaveDir: Directory('saves'),
      saves: saves,
    );

GameGroup game(List<GameVersion> versions) =>
    GameGroup(baseKey: 'game', displayName: 'Game', versions: versions);

/// Saves written while playing [inVersion] (local copies in that version's
/// folder, plus the shared AppData ones).
SaveInfo played({bool local = true, int manual = 2, int auto = 5, String? saveVersion}) => SaveInfo(
      lastSaveAt: day1,
      hasLocalSaves: local,
      manualSaves: manual,
      autoSaves: auto,
      newestSaveVersion: saveVersion,
      newestSaveAt: day1,
    );

GameStatus status(GameGroup g, [UserData ud = const UserData()]) => effectiveGameStatus(g, ud);

void main() {
  test('never played → Unplayed', () {
    expect(status(game([version('0.5')])), GameStatus.unplayed);
  });

  test('saves or tracked playtime → Playing', () {
    expect(status(game([version('0.5', played())])), GameStatus.playing);
    expect(status(game([version('0.5')]), const UserData(playtime: {'game': 600})), GameStatus.playing);
  });

  test('only autosaves → Skimmed', () {
    expect(status(game([version('0.5', played(manual: 0))])), GameStatus.skimmed);
  });

  group('Updated since last played', () {
    test('a newer version than the one last launched from the app', () {
      final g = game([version('0.5', played()), version('0.6')]);
      expect(status(g, const UserData(lastPlayedVersion: {'game': '0.5'})), GameStatus.updated);
      expect(status(g, const UserData(lastPlayedVersion: {'game': '0.6'})), GameStatus.playing);
    });

    test('saves in an older folder but not the newest', () {
      expect(status(game([version('0.5', played()), version('0.6')])), GameStatus.updated);
      expect(status(game([version('0.5', played()), version('0.6', played())])), GameStatus.playing);
    });

    test('newest save made in an older game version (single folder)', () {
      // Fresh install of 0.6: no local saves; AppData saves from 0.5 remain.
      expect(status(game([version('0.6', played(local: false, saveVersion: '0.5'))])), GameStatus.updated);
      expect(status(game([version('0.6', played(local: false, saveVersion: '0.6'))])), GameStatus.playing);
      // Word versions don't line up with a game's own version string.
      expect(status(game([version('Chapter-3', played(local: false, saveVersion: '0.2'))])), GameStatus.playing);
    });

    test('Playing / On Hold picks surface as Updated; other picks win', () {
      final g = game([version('0.5', played()), version('0.6')]);
      expect(status(g, const UserData(status: {'game': 'on-hold'})), GameStatus.updated);
      expect(status(g, const UserData(status: {'game': 'completed'})), GameStatus.completed);
      expect(status(game([version('0.5', played())]), const UserData(status: {'game': 'on-hold'})),
          GameStatus.onHold);
    });
  });

  test('a manual unplayed mark beats saves', () {
    expect(status(game([version('0.5', played())]), const UserData(manualUnplayed: {'Game-0.5'})),
        GameStatus.unplayed);
  });

  test('filters start with every status selected', () {
    expect(const FilterState().statuses, {for (final s in GameStatus.values) s.id});
  });
}
