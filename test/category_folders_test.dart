// A folder of games with a stray file in it ("Finished" holding an installer
// or a readme page) is a category, and the games inside are found. Invented
// games throughout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/scanner_service.dart';

void _renpy(String dir) {
  Directory(p.join(dir, 'game')).createSync(recursive: true);
  File(p.join(dir, 'game', 'script.rpyc')).writeAsStringSync('x');
  Directory(p.join(dir, 'renpy')).createSync(recursive: true);
  File(p.join(dir, 'Game.exe')).writeAsStringSync('x');
  File(p.join(dir, 'Game.py')).writeAsStringSync('x');
}

void _unity(String dir) {
  Directory(p.join(dir, 'Game_Data')).createSync(recursive: true);
  File(p.join(dir, 'Game.exe')).writeAsStringSync('x');
  File(p.join(dir, 'UnityPlayer.dll')).writeAsStringSync('x');
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('vnpf_categories_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<Map<String, List<String>>> scan() async {
    final r = await ScannerService.scanLibrary([root]);
    return {
      for (final g in r.groups)
        g.displayName: [for (final v in g.versions) p.relative(v.folderPath.path, from: root.path)],
    };
  }

  test('a stray program, page or Flash file beside the games doesn\'t make the folder a game', () async {
    _renpy(p.join(root.path, 'Finished', 'Lantern Bay-1.0'));
    _renpy(p.join(root.path, 'Finished', 'Harbour Lights-2.1'));
    _unity(p.join(root.path, 'Not finished', 'Quillfen Tales-0.5'));
    _renpy(p.join(root.path, 'Old', 'Marrow Wind-0.3'));
    File(p.join(root.path, 'Finished', 'SomeInstaller.exe')).writeAsStringSync('x');
    File(p.join(root.path, 'Not finished', 'index.html')).writeAsStringSync('x');
    File(p.join(root.path, 'Old', 'intro.swf')).writeAsStringSync('x');

    final games = await scan();
    expect(games.keys, unorderedEquals(['Lantern Bay', 'Harbour Lights', 'Quillfen Tales', 'Marrow Wind']));
    expect(games['Lantern Bay'], [p.join('Finished', 'Lantern Bay-1.0')]);
  });

  test('a folder of programs with no known engine is still a game when nothing inside is one', () async {
    final dir = Directory(p.join(root.path, 'Brasswick-0.4'))..createSync(recursive: true);
    File(p.join(dir.path, 'Brasswick.exe')).writeAsStringSync('x');
    Directory(p.join(dir.path, 'data')).createSync();
    expect((await scan()).keys, ['Brasswick']);
  });
}
