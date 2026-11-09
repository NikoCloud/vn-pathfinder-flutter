import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/services/disk_space.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

void _game(String root, String folder) {
  final dir = Directory(p.join(root, folder, 'game'))..createSync(recursive: true);
  File(p.join(dir.path, 'script.rpy')).writeAsStringSync('label start:\n    return\n');
}

void main() {
  group('settings', () {
    test('an older single folder becomes the first of the list', () {
      final s = AppSettings.fromJson({'library_dir': r'D:\Games'});
      expect(s.libraryDirs, [r'D:\Games']);
      expect(s.libraryDir, r'D:\Games');
    });

    test('the list is saved, with the first folder kept for older versions', () {
      final s = AppSettings(libraryDirs: const [r'D:\Games', r'E:\More']);
      final json = s.toJson();
      expect(json['library_dirs'], [r'D:\Games', r'E:\More']);
      expect(json['library_dir'], r'D:\Games');
      expect(AppSettings.fromJson(json).libraryDirs, [r'D:\Games', r'E:\More']);
    });

    test('no folder means an empty first folder', () {
      expect(AppSettings.fromJson({}).libraryDir, '');
    });
  });

  group('adding a folder', () {
    const dirs = [r'D:\Games', r'E:\More'];

    test('a new folder is fine', () {
      expect(libraryDirProblem(dirs, r'F:\VNs'), isNull);
    });

    test('the same folder, one inside another, or one holding another is refused', () {
      expect(libraryDirProblem(dirs, r'D:\Games'), isNotNull);
      expect(libraryDirProblem(dirs, r'D:\Games\Ren'), isNotNull);
      expect(libraryDirProblem(dirs, r'E:\'), isNotNull);
    });

    test('a folder whose name only starts the same is fine', () {
      expect(libraryDirProblem(dirs, r'D:\Games2'), isNull);
    });

    test('a path finds the folder that holds it', () {
      expect(libraryRootFor(dirs, r'E:\More\Game.zip'), r'E:\More');
      expect(libraryRootFor(dirs, r'Z:\elsewhere.zip'), r'D:\Games');
    });
  });

  group('scanning', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('vnpf_folders_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('games in every folder are found, and versions in different folders group', () async {
      final a = p.join(tmp.path, 'a'), b = p.join(tmp.path, 'b');
      _game(a, 'HarborLights-0.5-pc');
      _game(b, 'HarborLights-0.6-pc');
      _game(b, 'OtherGame-1.0-pc');
      final groups = await ScannerService.scanAll([Directory(a), Directory(b)]);
      expect(groups.length, 2);
      final harbor = groups.firstWhere((g) => g.versions.length == 2);
      expect(harbor.versions.map((v) => v.versionStr).toSet(), {'0.5', '0.6'});
    });

    test('a folder that is not there is skipped', () async {
      final a = p.join(tmp.path, 'a');
      _game(a, 'Game-1.0-pc');
      final groups = await ScannerService.scanAll([Directory(a), Directory(p.join(tmp.path, 'gone'))]);
      expect(groups.length, 1);
    });
  });

  group('free space', () {
    test('sizes read the way people say them', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(640 * 1024 * 1024), '640 MB');
      expect(formatBytes(1536 * 1024 * 1024), '1.5 GB');
      expect(formatBytes(2 * 1024 * 1024 * 1024 * 1024), '2.0 TB');
    });

    test('the temp folder has a drive with room', () async {
      final s = await diskSpaceFor(Directory.systemTemp.path);
      expect(s, isNotNull);
      expect(s!.total, greaterThan(s.free));
      expect(s.free, greaterThan(0));
    });

    test('a missing folder has no answer', () async {
      expect(await diskSpaceFor(r'Q:\definitely\not\here'), isNull);
    });
  });
}
