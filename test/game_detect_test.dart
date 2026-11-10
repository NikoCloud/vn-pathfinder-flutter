import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/services/game_detect.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

String _path(String rel) => p.join(root.path, rel);

void _file(String rel, [List<int>? bytes]) {
  final f = File(_path(rel))..parent.createSync(recursive: true);
  bytes == null ? f.writeAsStringSync('') : f.writeAsBytesSync(bytes);
}

void _dir(String rel) => Directory(_path(rel)).createSync(recursive: true);

void _renpy(String rel) {
  _file('$rel/game/archive.rpa');
  _file('$rel/${p.basename(rel).split('-').first}.exe');
}

GameEngine? _engine(String rel, {bool other = false}) => detectEngine(Directory(_path(rel)), allowOther: other);

List<String> _found(LibrarySearch s) =>
    [for (final (d, _) in s.games) p.relative(d.path, from: root.path).replaceAll(r'\', '/')];

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_detect'));
  tearDown(() => root.deleteSync(recursive: true));

  group('engine signatures', () {
    test('each engine is recognised from its own files', () {
      _renpy('R');
      _file('U/Game.exe');
      _dir('U/Game_Data');
      _dir('UE/Engine');
      _dir('UE/Proj/Content/Paks');
      _file('UE/Proj.exe');
      _file('MV/www/js/rpg_core.js');
      _file('MZ/js/rmmz_core.js');
      _file('VX/Game.rgss3a');
      _file('GD/Game.exe');
      _file('GD/Game.pck');
      _file('GE/Game.exe', [0x4d, 0x5a, ...List.filled(20, 0), 0x47, 0x44, 0x50, 0x43]);
      _file('W/Data.wolf');
      _file('K/data.xp3');
      _file('E/resources/app.asar');
      _file('F/movie.swf');
      _file('H/index.html');
      _dir('M/Game.app/Contents/Resources/autorun/game');
      expect(_engine('R'), GameEngine.renpy);
      expect(_engine('U'), GameEngine.unity);
      expect(_engine('UE'), GameEngine.unreal);
      expect(_engine('MV'), GameEngine.rpgmMv);
      expect(_engine('MZ'), GameEngine.rpgmMz);
      expect(_engine('VX'), GameEngine.rpgmVx);
      expect(_engine('GD'), GameEngine.godot);
      expect(_engine('GE'), GameEngine.godot, reason: 'a .pck built into the exe ends in GDPC');
      expect(_engine('W'), GameEngine.wolf);
      expect(_engine('K'), GameEngine.kirikiri);
      expect(_engine('E'), GameEngine.html);
      expect(_engine('F'), GameEngine.flash);
      expect(_engine('H'), GameEngine.html);
      expect(_engine('M'), GameEngine.renpyMac);
    });

    test('a save backup, a category named RenPy and a stray lib folder are not games', () {
      _file('SaveBackup/game/saves/1-1-LT1.save');
      _renpy('Cat/RenPy/GameA-0.1');
      _file('lib/windows-x86_64/python.exe');
      expect(_engine('SaveBackup'), isNull);
      expect(_engine('Cat'), isNull);
      expect(_engine('lib'), isNull);
    });

    test('a Unity _Data folder without the usual files still counts', () {
      _file('OddUnity/OddUnity.exe');
      _file('OddUnity/OddUnity_Data/sharedassets0.assets');
      expect(_engine('OddUnity'), GameEngine.unity);
    });

    test('a folder of programs counts only where Other is allowed, and a split archive never', () {
      _file('Custom/Custom.exe');
      _file('Split/RJ1.part1.exe');
      _file('Split/RJ1.part2.rar');
      expect(_engine('Custom'), isNull);
      expect(_engine('Custom', other: true), GameEngine.other);
      expect(_engine('Split', other: true), isNull);
    });
  });

  group('searching a library folder level by level', () {
    test('finds wrapped games, category folders and versions side by side', () {
      _renpy('Flat-1.0-pc');
      _renpy('Wrap/Wrap-1.0/Wrap-1.0-pc');
      _renpy('Categories/RenPy/CatA-0.1-pc');
      _file('Categories/Unity/CatB/CatB.exe');
      _dir('Categories/Unity/CatB/CatB_Data');
      _renpy('Multi/Multi-0.1-pc');
      _renpy('Multi/Multi-0.2-pc');
      _renpy('Played/F95/Dev01/Nested/v0.1');
      final found = _found(searchLibrary(root));
      expect(
          found,
          containsAll([
            'Flat-1.0-pc',
            'Wrap/Wrap-1.0/Wrap-1.0-pc',
            'Categories/RenPy/CatA-0.1-pc',
            'Categories/Unity/CatB',
            'Multi/Multi-0.1-pc',
            'Multi/Multi-0.2-pc',
            'Played/F95/Dev01/Nested/v0.1',
          ]));
      expect(found.indexOf('Flat-1.0-pc'), lessThan(found.indexOf('Multi/Multi-0.1-pc')), reason: 'level 0 first');
    });

    test("stops at a game: an HTML file inside a Ren'Py game is not a second game", () {
      _renpy('Game-1.0-pc');
      _file('Game-1.0-pc/extras/web/index.html');
      expect(_found(searchLibrary(root)), ['Game-1.0-pc']);
    });

    test('Search subfolders off looks only at the top', () {
      _renpy('Top-1.0-pc');
      _renpy('Cat/Deep-1.0-pc');
      expect(_found(searchLibrary(root, subfolders: false)), ['Top-1.0-pc']);
    });

    test('a folder of programs deep down is not a game, only at the top', () {
      _file('Tools/Utilities/Batch/thing.exe');
      _dir('Tools/Docs');
      _file('TopTool/tool.exe');
      expect(_found(searchLibrary(root)), ['TopTool']);
    });

    test('archives in folders that are not games are found; dot-folders are skipped', () {
      _file('Game-1.0.zip');
      _file('To try/Other-0.5.rar');
      _file('To try/Packed-0.2.7z');
      _renpy('To try/Played-1.0-pc');
      _file('To try/Played-1.0-pc/inner.zip');
      _renpy('.vnp-removed/Hidden-1.0-pc');
      final s = searchLibrary(root);
      expect(s.archives.map((f) => p.basename(f.path)).toSet(), {'Game-1.0.zip', 'Other-0.5.rar', 'Packed-0.2.7z'});
      expect(_found(s), ['To try/Played-1.0-pc']);
    });

    test('games deeper than the limit are not found', () {
      _renpy('a/b/c/d/e/f/g/h/i/TooDeep-1.0');
      expect(searchLibrary(root).games, isEmpty);
    });
  });

  group('reading a found game', () {
    test('a folder named only by its version takes its title from the folder above', () {
      _renpy('Dev/Nested/v0.5');
      final v = scanGameVersion(Directory(_path('Dev/Nested/v0.5')))!;
      expect(v.baseKey, 'nested');
      expect(v.versionStr, contains('0.5'));
      expect(v.folderName, 'v0.5');
      expect(v.engine, GameEngine.renpy);
    });

    test('the exe that matches the game is launched, not a crash handler or uninstaller', () {
      _file('Zombie/Zombie.exe');
      _file('Zombie/UnityCrashHandler64.exe');
      _dir('Zombie/Zombie_Data');
      _file('Inst/unins000.exe');
      _file('Inst/World.exe');
      _dir('Inst/World_Data');
      expect(p.basename(pickGameExe(Directory(_path('Zombie')))!.path), 'Zombie.exe');
      expect(p.basename(pickGameExe(Directory(_path('Inst')))!.path), 'World.exe');
    });

    test('version-only names', () {
      for (final n in ['v0.5', '0.6.1', 'Version 2', 'v1.0 Beta']) {
        expect(isVersionOnlyName(n), isTrue, reason: n);
      }
      for (final n in ['Game-0.5', 'Chapter 2', 'Nested']) {
        expect(isVersionOnlyName(n), isFalse, reason: n);
      }
    });
  });

  test('a whole library scan groups games found at different depths', () async {
    _renpy('Played/Hanamura/Game-0.1-pc');
    _renpy('Unplayed/Game-0.2-pc');
    final groups = await ScannerService.scanAll([root]);
    expect(groups.single.versions.map((v) => v.versionStr), ['0.1', '0.2']);
  });

  test('the Engine filter and the game page use the recognised engine', () {
    GameVersion v(GameEngine? e, {Map<String, dynamic> meta = const {}}) => GameVersion(
          folderName: 'G-1.0',
          folderPath: Directory('G-1.0'),
          baseKey: 'g',
          versionStr: '1.0',
          displayName: 'G',
          localSaveDir: Directory('G-1.0/game/saves'),
          isRenpy: e == GameEngine.renpy,
          engine: e,
          metadata: meta,
        );
    expect(engineFilterKey(v(GameEngine.unity)), 'unity');
    expect(engineFilterKey(v(GameEngine.rpgmMz)), 'rpgm');
    expect(engineFilterKey(v(GameEngine.godot)), 'other');
    expect(engineFilterKey(v(null, meta: {'engine': 'Unreal'})), 'unreal');
    expect(v(GameEngine.godot).engineName, 'Godot');
    expect(v(GameEngine.other, meta: {'engine': 'Unity'}).engineName, 'Unity');
  });
}
