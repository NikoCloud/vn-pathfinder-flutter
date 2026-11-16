// #52: saves carried into a new version must not make it look played.
// Invented game throughout.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_status.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';

class _UserData extends UserDataNotifier {
  _UserData(super.ref, UserData data) : super(initial: data);
  @override
  Future<void> save() async {}
}

ProviderContainer _container([UserData data = const UserData()]) {
  final c = ProviderContainer(overrides: [userDataProvider.overrideWith((ref) => _UserData(ref, data))]);
  addTearDown(c.dispose);
  return c;
}

// After the update: only the new folder is left, holding the carried saves.
final _updated = GameGroup(
  baseKey: 'lanternbay',
  displayName: 'Lantern Bay',
  versions: [
    GameVersion(
      folderName: 'LanternBay-0.5',
      folderPath: Directory('LanternBay-0.5'),
      baseKey: 'lanternbay',
      versionStr: '0.5',
      displayName: 'Lantern Bay',
      localSaveDir: Directory('saves'),
      saves: SaveInfo(hasLocalSaves: true, lastSaveAt: DateTime(2026, 11, 1)),
    ),
  ],
);

void main() {
  test('without a record, carried saves alone read as the new version played', () {
    // The bug, kept as a check on the rule the fix works around.
    expect(hasUpdateSinceLastPlayed(_updated, const UserData()), isFalse);
  });

  test('saves carried from 0.4 leave 0.5 waiting to be played', () {
    final c = _container();
    c.read(userDataProvider.notifier).savesCarriedFrom('lanternbay', '0.4');
    expect(c.read(userDataProvider).lastPlayedVersion['lanternbay'], '0.4');
    expect(hasUpdateSinceLastPlayed(_updated, c.read(userDataProvider)), isTrue);
  });

  test('a version launched from the app is never overwritten', () {
    final c = _container(const UserData(lastPlayedVersion: {'lanternbay': '0.5'}));
    c.read(userDataProvider.notifier).savesCarriedFrom('lanternbay', '0.4');
    expect(c.read(userDataProvider).lastPlayedVersion['lanternbay'], '0.5');
    expect(hasUpdateSinceLastPlayed(_updated, c.read(userDataProvider)), isFalse);
  });

  test('an unknown old version records nothing', () {
    final c = _container();
    c.read(userDataProvider.notifier).savesCarriedFrom('lanternbay', '');
    expect(c.read(userDataProvider).lastPlayedVersion, isEmpty);
  });
}
