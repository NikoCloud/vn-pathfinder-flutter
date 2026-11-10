import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/services/duplicates.dart';
import 'package:vn_pathfinder/widgets/modals/duplicates_dialog.dart';

GameVersion _v(String path) => GameVersion(
      folderName: 'Game-0.6',
      folderPath: Directory(path),
      baseKey: 'game',
      versionStr: '0.6',
      displayName: 'Game',
      localSaveDir: Directory('$path/game/saves'),
    );

void main() {
  testWidgets('the banner says duplicates were found, and nothing shows without them', (t) async {
    final g = GameGroup(baseKey: 'game', displayName: 'Game', versions: [_v(r'D:\A\Game-0.6'), _v(r'E:\B\Game-0.6')]);
    await t.pumpWidget(ProviderScope(
      overrides: [duplicatesProvider.overrideWithValue([DuplicateSet(g, '0.6', g.versions[0], [g.versions[1]])])],
      child: const MaterialApp(home: Scaffold(body: DuplicatesBanner())),
    ));
    expect(find.textContaining('Duplicates identified. Do you wish to merge?'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await t.pumpWidget(ProviderScope(
      overrides: [duplicatesProvider.overrideWithValue(const [])],
      child: const MaterialApp(home: Scaffold(body: DuplicatesBanner())),
    ));
    expect(find.textContaining('Duplicates identified'), findsNothing);
  });
}
