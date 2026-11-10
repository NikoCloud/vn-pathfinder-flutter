import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/archive_item.dart';
import 'package:vn_pathfinder/services/extraction_service.dart';

const _sevenZip = r'C:\Program Files\7-Zip\7z.exe';

void main() {
  test('7z archives are their own type and extract through 7-Zip', () {
    final t = ArchiveTypeExt.fromExtension('.7Z');
    expect(t, ArchiveType.sevenZip);
    expect(t.label, '7Z');
    expect(t.canExtract, isTrue);
    expect(t.needs7Zip, isTrue);
  });

  test('which types extract, and with what', () {
    expect(ArchiveType.zip.canExtract, isTrue);
    expect(ArchiveType.zip.needs7Zip, isFalse);
    expect(ArchiveType.rar.needs7Zip, isTrue);
    for (final t in [ArchiveType.rpa, ArchiveType.rpy, ArchiveType.py, ArchiveType.unknown]) {
      expect(t.canExtract, isFalse, reason: t.label);
    }
  });

  test('a .7z extracts through 7-Zip like a RAR', () async {
    final tmp = Directory.systemTemp.createTempSync('vnp7z');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final game = p.join(tmp.path, 'src', 'SevenGame-2.0-pc');
    Directory(p.join(game, 'game')).createSync(recursive: true);
    File(p.join(game, 'game', 'script.rpy')).writeAsStringSync('label start:\n    return\n');
    final archive = p.join(tmp.path, 'SevenGame-2.0-pc.7z');
    final made = await Process.run(_sevenZip, ['a', archive, game]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    final out = p.join(tmp.path, 'out');
    await ExtractionJob().extractWith7Zip(_sevenZip, archive, out, (_) {});
    expect(File(p.join(out, 'SevenGame-2.0-pc', 'game', 'script.rpy')).existsSync(), isTrue);
  }, skip: File(_sevenZip).existsSync() ? false : '7-Zip is not installed');
}
