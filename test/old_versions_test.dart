import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/old_versions.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_old'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a kept download goes to the hidden folder, is listed for its game, and restores to the library folder', () async {
    final archive = File(p.join(root.path, 'Game-0.5-pc.zip'))..writeAsStringSync('zip bytes');
    final kept = stashArchive(
        archivePath: archive.path, libraryRoot: root.path, baseKey: 'game', version: '0.5', title: 'Game');
    expect(archive.existsSync(), isFalse);
    expect(p.basename(p.dirname(kept.file)), oldVersionsFolder);
    expect(keptDownloads('game', [root.path]).single.version, '0.5');
    expect(keptDownloads('other', [root.path]), isEmpty);

    // The hidden folder is skipped by the library scan.
    final groups = await ScannerService.scanAll([root]);
    expect(groups.expand((g) => g.archives), isEmpty);

    final back = restoreKept(keptDownloads('game', [root.path]).single);
    expect(p.dirname(back), root.path);
    expect(File(back).readAsStringSync(), 'zip bytes');
    expect(keptDownloads('game', [root.path]), isEmpty);
  });

  test('a second download with the same name is kept beside the first', () {
    for (final v in ['0.5', '0.5b']) {
      final a = File(p.join(root.path, 'Game.zip'))..writeAsStringSync(v);
      stashArchive(archivePath: a.path, libraryRoot: root.path, baseKey: 'game', version: v, title: 'Game');
    }
    expect(keptDownloads('game', [root.path]).length, 2);
  });

  test('saves only the old folder has, or newer ones, move to the new version', () {
    final oldSaves = Directory(p.join(root.path, 'Old', 'game', 'saves'))..createSync(recursive: true);
    final newSaves = Directory(p.join(root.path, 'New', 'game', 'saves'))..createSync(recursive: true);
    File(p.join(oldSaves.path, 'only-old.save')).writeAsStringSync('a');
    File(p.join(oldSaves.path, 'both.save'))
      ..writeAsStringSync('old')
      ..setLastModifiedSync(DateTime(2026, 1, 1));
    File(p.join(newSaves.path, 'both.save'))
      ..writeAsStringSync('new')
      ..setLastModifiedSync(DateTime(2026, 6, 1));
    carrySaves(p.join(root.path, 'Old'), p.join(root.path, 'New'));
    expect(File(p.join(newSaves.path, 'only-old.save')).existsSync(), isTrue);
    expect(File(p.join(newSaves.path, 'both.save')).readAsStringSync(), 'new', reason: 'the newer save stays');
  });
}
