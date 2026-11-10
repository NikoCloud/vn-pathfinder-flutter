import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/widgets/modals/local_fetch_panel.dart';

void main() {
  testWidgets('the Local panel reads a real game on its isolate and shows what it found', (t) async {
    final root = Directory.systemTemp.createTempSync('vnp_panel');
    addTearDown(() => root.deleteSync(recursive: true));
    final game = Directory(p.join(root.path, 'Harbor-0.6-pc', 'game'))..createSync(recursive: true);
    File(p.join(game.path, 'options.rpy'))
        .writeAsStringSync('define config.name = _("Harbor Lights")\ndefine config.version = "0.6"\n');
    final v = scanGameVersion(game.parent)!;
    final group = GameGroup(baseKey: v.baseKey, displayName: v.displayName, versions: [v]);

    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: LocalFetchPanel(group: group))),
    ));
    expect(find.text('Reading the game files…'), findsOneWidget);
    // The read runs on a real isolate; give it real time.
    for (var i = 0; i < 50 && find.text('Harbor Lights').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(find.text('Harbor Lights'), findsOneWidget);
    expect(find.text('0.6'), findsOneWidget);
    expect(find.text('Reading the game files…'), findsNothing);
  });
}
