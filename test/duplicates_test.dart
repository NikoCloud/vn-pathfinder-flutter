import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/drive_info.dart';
import 'package:vn_pathfinder/services/duplicates.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

Directory _game(String lib, String name) {
  final d = Directory(p.join(root.path, lib, name));
  Directory(p.join(d.path, 'game', 'saves')).createSync(recursive: true);
  File(p.join(d.path, 'game', 'archive.rpa')).writeAsStringSync('x' * 100);
  File(p.join(d.path, '${name.split('-').first}.exe')).writeAsStringSync('');
  return d;
}

File _save(Directory game, String name, DateTime time) {
  final f = File(p.join(game.path, 'game', 'saves', name))..writeAsStringSync('save $name $time');
  f.setLastModifiedSync(time);
  return f;
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_dupes'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<DuplicateSet>> scan(List<String> libs) async {
    final dirs = [for (final l in libs) p.join(root.path, l)];
    final groups = await ScannerService.scanAll([for (final d in dirs) Directory(d)]);
    return findDuplicates(groups, dirs);
  }

  test('the same version in two library folders is a duplicate; the higher folder keeps it and Play opens it', () async {
    final a = _game('A', 'Game-0.6-pc');
    _game('B', 'Game-0.6-pc');
    _game('B', 'Game-0.5-pc');
    final dirs = [p.join(root.path, 'A'), p.join(root.path, 'B')];
    final groups = await ScannerService.scanAll([for (final d in dirs) Directory(d)]);
    final sets = findDuplicates(groups, dirs);
    expect(sets.length, 1);
    expect(sets.single.keep.folderPath.path, a.path);
    expect(sets.single.others.single.folderPath.path, p.join(root.path, 'B', 'Game-0.6-pc'));
    expect(groups.single.latestVersion!.folderPath.path, a.path, reason: 'Play opens the copy in the highest folder');
  });

  test('different versions are not duplicates', () async {
    _game('A', 'Game-0.6-pc');
    _game('B', 'Game-0.7-pc');
    expect(await scan(['A', 'B']), isEmpty);
  });

  test('the plan counts files and saves; merging moves saves (newer wins) and deletes the other copy', () async {
    final keep = _game('A', 'Game-0.6-pc');
    final other = _game('B', 'Game-0.6-pc');
    final old = DateTime(2026, 1, 1), recent = DateTime(2026, 6, 1);
    _save(keep, '1-1-LT1.save', old);
    _save(other, '1-1-LT1.save', recent); // newer in the other copy: wins
    _save(keep, '2-1-LT1.save', recent);
    _save(other, '2-1-LT1.save', old); // older in the other copy: the kept one stays
    _save(other, '3-1-LT1.save', recent); // only in the other copy: moves

    final set = (await scan(['A', 'B'])).single;
    final plan = await planMerge(set);
    final c = plan.copies.single;
    expect(c.savesToMove, ['3-1-LT1.save']);
    expect(c.conflicts, {'1-1-LT1.save': true, '2-1-LT1.save': false});
    expect(c.files, greaterThanOrEqualTo(5));

    await runMerge(plan, toTrash: false);
    expect(other.existsSync(), isFalse);
    final saves = p.join(keep.path, 'game', 'saves');
    expect(File(p.join(saves, '3-1-LT1.save')).existsSync(), isTrue);
    expect(File(p.join(saves, '1-1-LT1.save')).readAsStringSync(), contains('$recent'));
    expect(File(p.join(saves, '2-1-LT1.save')).readAsStringSync(), contains('$recent'));
    expect(File(p.join(saves, '1-1-LT1.save')).lastModifiedSync(), recent, reason: 'a moved save keeps its time');
  });

  test('network shares and unknown places are never Trash-safe', () async {
    expect((await driveInfoFor(r'\\nas\games\Game-0.6')).trashSafe, isFalse);
    expect((await driveInfoFor(r'\\nas\games\Game-0.6')).kind, DriveKind.network);
    expect(const DriveInfo(DriveKind.unknown, hasTrash: true).trashSafe, isFalse);
    expect(const DriveInfo(DriveKind.removable, hasTrash: true).trashSafe, isFalse);
    expect(const DriveInfo(DriveKind.internal, hasTrash: false).trashSafe, isFalse, reason: 'FAT or exFAT');
    expect(const DriveInfo(DriveKind.internal, hasTrash: true).trashSafe, isTrue);
  });

  test('the system drive is recognised as internal with a recycle bin', () async {
    final info = await driveInfoFor(Platform.environment['SystemRoot'] ?? r'C:\Windows');
    expect(info.kind, DriveKind.internal, reason: info.reason);
    expect(info.hasTrash, isTrue);
  }, skip: Platform.isWindows ? false : 'Windows only');
}
