import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/crash_log.dart';
import 'package:vn_pathfinder/services/drive_info.dart';
import 'package:vn_pathfinder/services/duplicates.dart';
import 'package:vn_pathfinder/services/library_cache.dart';
import 'package:vn_pathfinder/services/old_versions.dart';
import 'package:vn_pathfinder/services/renpy_local.dart';
import 'package:vn_pathfinder/services/safe_remove.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

Directory _renpy(String lib, String name) {
  final d = Directory(p.join(root.path, lib, name));
  Directory(p.join(d.path, 'game', 'saves')).createSync(recursive: true);
  File(p.join(d.path, 'game', 'script.rpy')).writeAsStringSync('label start:');
  File(p.join(d.path, '${name.split('-').first}.py')).writeAsStringSync('');
  File(p.join(d.path, '${name.split('-').first}.exe')).writeAsStringSync('');
  return d;
}

Directory _rpgmMv(String lib, String name) {
  final d = Directory(p.join(root.path, lib, name));
  Directory(p.join(d.path, 'www', 'js')).createSync(recursive: true);
  File(p.join(d.path, 'www', 'js', 'rpg_core.js')).writeAsStringSync('');
  File(p.join(d.path, 'Game.exe')).writeAsStringSync('');
  File(p.join(d.path, 'package.json')).writeAsStringSync('{}');
  return d;
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_safety'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('games joined with Merge into Another Game are not duplicates of each other', () async {
    _renpy('A', 'SeasonOne-1.0-pc');
    _renpy('B', 'SeasonTwo-1.0-pc');
    final dirs = [Directory(p.join(root.path, 'A')), Directory(p.join(root.path, 'B'))];
    final before = await ScannerService.scanAll(dirs);
    final keys = [for (final g in before) g.versions.single.baseKey];
    expect(keys.length, 2);
    final merged = await ScannerService.scanAll(dirs, merges: {keys[1]: keys[0]});
    expect(merged.length, 1, reason: 'the two seasons show as one game');
    expect(findDuplicates(merged, [for (final d in dirs) d.path]), isEmpty);
  });

  test('a library folder added twice by two paths: the merge removes nothing', () async {
    final real = _renpy('A', 'Game-0.6-pc');
    final link = p.join(root.path, 'B');
    final r = Process.runSync('cmd', ['/c', 'mklink', '/J', link, p.join(root.path, 'A')]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final through = p.join(link, 'Game-0.6-pc');
    expect(sameFolder(real.path, through), isTrue);
    expect(sameFolder(real.path, _renpy('C', 'Game-0.6-pc').path), isFalse);

    final dirs = [p.join(root.path, 'A'), link];
    final sets = findDuplicates(await ScannerService.scanAll([for (final d in dirs) Directory(d)]), dirs);
    expect(sets.length, 1, reason: 'the same game seen through both library paths');
    final plan = await planMerge(sets.single);
    await expectLater(runMerge(plan, toTrash: false), throwsA(isA<FileSystemException>()));
    expect(File(p.join(real.path, 'game', 'script.rpy')).existsSync(), isTrue, reason: 'the only copy is still there');
    Directory(link).deleteSync(); // removes the junction only
  });

  test('a folder with an open file is reported in use and left alone', () {
    final d = _renpy('A', 'Game-0.6-pc');
    final open = File(p.join(d.path, 'game', 'script.rpy')).openSync(mode: FileMode.append);
    try {
      expect(() => checkNotInUse(d.path), throwsA(isA<FileSystemException>()));
    } finally {
      open.closeSync();
    }
    expect(() => checkNotInUse(d.path), returnsNormally);
    expect(d.existsSync(), isTrue);
  });

  test('saves are carried for RPG Maker and VX Ace too, not only Ren\'Py', () {
    final old = Directory(p.join(root.path, 'Old'))..createSync();
    final neu = Directory(p.join(root.path, 'New'))..createSync();
    File(p.join(old.path, 'www', 'save', 'file1.rpgsave'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mv');
    File(p.join(old.path, 'Save01.rvdata2')).writeAsStringSync('vx');
    File(p.join(old.path, 'game', 'saves', '1-1-LT1.save'))
      ..createSync(recursive: true)
      ..writeAsStringSync('renpy');
    File(p.join(old.path, 'readme.txt')).writeAsStringSync('not a save');
    expect(savesIn(old.path).length, 3);
    carrySaves(old.path, neu.path);
    expect(File(p.join(neu.path, 'www', 'save', 'file1.rpgsave')).readAsStringSync(), 'mv');
    expect(File(p.join(neu.path, 'Save01.rvdata2')).readAsStringSync(), 'vx');
    expect(File(p.join(neu.path, 'game', 'saves', '1-1-LT1.save')).existsSync(), isTrue);
    expect(File(p.join(neu.path, 'readme.txt')).existsSync(), isFalse);
  });

  test('merging an RPG Maker duplicate moves its saves into the kept copy', () async {
    final keep = _rpgmMv('A', 'Rpg-1.0');
    final other = _rpgmMv('B', 'Rpg-1.0');
    File(p.join(other.path, 'www', 'save', 'file1.rpgsave'))
      ..createSync(recursive: true)
      ..writeAsStringSync('slot 1');
    final dirs = [p.join(root.path, 'A'), p.join(root.path, 'B')];
    final sets = findDuplicates(await ScannerService.scanAll([for (final d in dirs) Directory(d)]), dirs);
    expect(sets.length, 1);
    final plan = await planMerge(sets.single);
    expect(plan.copies.single.savesToMove, [p.join('www', 'save', 'file1.rpgsave')]);
    expect(plan.copies.single.savesUnchecked, isFalse);
    await runMerge(plan, toTrash: false);
    expect(other.existsSync(), isFalse);
    expect(File(p.join(keep.path, 'www', 'save', 'file1.rpgsave')).readAsStringSync(), 'slot 1');
  });

  test('Add a game skips ZIP entries that would land outside the game folder', () async {
    final zip = Archive()
      ..addFile(ArchiveFile('good.txt', 4, utf8.encode('good')))
      ..addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')))
      ..addFile(ArchiveFile('sub/../../evil2.txt', 4, utf8.encode('evil')));
    final file = File(p.join(root.path, 'in.zip'))..writeAsBytesSync(ZipEncoder().encode(zip));
    final target = Directory(p.join(root.path, 'lib', 'Game'));
    await ScannerService.extractArchive(file, target);
    expect(File(p.join(target.path, 'good.txt')).readAsStringSync(), 'good');
    expect(File(p.join(root.path, 'lib', 'evil.txt')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'evil2.txt')).existsSync(), isFalse);
  });

  test('the log keeps writing after it rotates', () async {
    final dir = Directory(p.join(root.path, 'logs'));
    CrashLog.directoryForTesting = dir;
    CrashLog.start();
    final filler = 'x' * 1000;
    for (var i = 0; i < 1100; i++) {
      CrashLog.write(filler);
    }
    CrashLog.write('during rotation');
    await CrashLog.stopForTesting(); // waits for the rotation to finish
    CrashLog.start();
    CrashLog.write('after rotation');
    await CrashLog.stopForTesting();
    CrashLog.directoryForTesting = null;
    final log = File(p.join(dir.path, 'app.log')).readAsStringSync();
    expect(log, contains('during rotation'));
    expect(log, contains('after rotation'));
    expect(File(p.join(dir.path, 'app.1.log')).existsSync(), isTrue);
  });

  test('the report saved in the logs folder hides the library folders too', () async {
    final appdata = Directory(p.join(root.path, 'VN Pathfinder'));
    final dir = Directory(p.join(appdata.path, 'logs'))..createSync(recursive: true);
    final lib = p.join(root.path, 'MyGames');
    File(p.join(appdata.path, 'settings.json')).writeAsStringSync(jsonEncode({
      'library_dirs': [lib]
    }));
    File(p.join(dir.path, 'app.log')).writeAsStringSync('=== VN Pathfinder test started ===\nscanning $lib\\Game\n');
    File(p.join(dir.path, 'unclean-1')).writeAsStringSync('');
    CrashLog.directoryForTesting = dir;
    final report = CrashLog.start();
    await CrashLog.stopForTesting();
    CrashLog.directoryForTesting = null;
    expect(report, isNotNull);
    final saved = dir.listSync().whereType<File>().firstWhere((f) => p.basename(f.path).startsWith('crash-'));
    final text = saved.readAsStringSync();
    expect(text, isNot(contains(lib)));
    expect(text, contains('<library 1>'));
  });

  test('a damaged cache entry never stops the quick start', () async {
    final g = _renpy('A', 'Game-0.6-pc');
    final cache = <String, dynamic>{
      g.path: {'engine': 'renpy', 'saves': 'not a map', 'local_t': 1},
      p.join(root.path, 'A', 'Other'): 'garbage',
    };
    Directory(p.join(root.path, 'A', 'Other')).createSync();
    final quick = await ScannerService.scanCached([Directory(p.join(root.path, 'A'))], cache);
    expect(quick.groups.length, 1);
    final full = await ScannerService.scanLibrary([Directory(p.join(root.path, 'A'))], cache: cache);
    expect(full.groups.length, 1);
    expect(LibraryCache.fileForTesting, isNotNull);
  });

  test('a compressed index that would grow past the limit is refused', () {
    final bomb = zlib.encode(List.filled(4 << 20, 0));
    expect(inflateCapped(bomb, 1 << 20), isNull);
    expect(inflateCapped(zlib.encode(utf8.encode('hello')), 1 << 20), utf8.encode('hello'));
  });

  test('Send to the Recycle Bin moves a folder with no prompt for an ordinary size', () async {
    final d = Directory(p.join(root.path, 'vnp-trash-test-folder'))..createSync();
    File(p.join(d.path, 'a.txt')).writeAsStringSync('tiny');
    await moveToTrash(d.path);
    expect(d.existsSync(), isFalse);
  });
}
