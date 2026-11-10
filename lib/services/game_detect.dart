import 'dart:io';

import 'package:path/path.dart' as p;

/// The engine a game folder was made with, recognised from files every
/// engine leaves in a fixed place (#13). Tested on a 240-folder library and a
/// 1,487-game test tree before it was written.
enum GameEngine {
  renpy("Ren'Py"),
  renpyMac("Ren'Py (Mac build)"),
  unity('Unity'),
  unreal('Unreal'),
  rpgmMv('RPG Maker MV'),
  rpgmMz('RPG Maker MZ'),
  rpgmVx('RPG Maker VX Ace / XP'),
  godot('Godot'),
  wolf('Wolf RPG'),
  kirikiri('Kirikiri'),
  html('HTML'),
  flash('Flash'),

  /// A folder with a program in it but no known engine. Only accepted at the
  /// top of a library folder, as before, so tool and installer folders
  /// further down aren't mistaken for games.
  other('Other');

  final String label;
  const GameEngine(this.label);
}

/// Folders never opened while searching: saves, caches and the app's own.
const _skipDirs = {
  'saves', '__pycache__', 'cache', 'logs', 'screenshots', '__macosx',
  // Engine internals: never hold games, and can hold hundreds of folders,
  // each a round trip on a network share. Not "renpy": people name
  // category folders that, and Ren'Py's own renpy/ sits inside a game, where
  // the search has already stopped.
  'lib', 'libs', 'site-packages', 'node_modules', 'locales', 'swiftshader', '.git',
};

bool _isEngineInternal(String lowerName) => _skipDirs.contains(lowerName) || lowerName.startsWith('python');

/// A folder with more entries than this isn't opened (photo dumps, backups).
const maxEntriesToOpen = 2000;

/// How deep Search subfolders looks. Organised libraries put games four
/// levels down (status / source / developer / game / version).
const maxSearchDepth = 8;

/// Programs that are installers, uninstallers or split self-extracting
/// archives, not games.
final _notAGameExe = RegExp(r'(setup|install|unins\d*|\.part\d+)\.exe$', caseSensitive: false);

class _Listing {
  final Map<String, String> files; // lowercase name → real name
  final Map<String, String> dirs;
  const _Listing(this.files, this.dirs);
  int get length => files.length + dirs.length;
}

_Listing _list(String path) {
  final files = <String, String>{}, dirs = <String, String>{};
  try {
    for (final e in Directory(path).listSync()) {
      final name = p.basename(e.path);
      if (e is Directory) {
        dirs[name.toLowerCase()] = name;
      } else if (e is File) {
        files[name.toLowerCase()] = name;
      }
    }
  } catch (_) {}
  return _Listing(files, dirs);
}

bool _has(String path, List<String> parts) => FileSystemEntity.typeSync(p.joinAll([path, ...parts])) != FileSystemEntityType.notFound;

bool _endsWithGdpc(String exe) {
  RandomAccessFile? f;
  try {
    f = File(exe).openSync();
    final len = f.lengthSync();
    if (len < 4) return false;
    f.setPositionSync(len - 4);
    final tail = f.readSync(4);
    return String.fromCharCodes(tail) == 'GDPC';
  } catch (_) {
    return false;
  } finally {
    f?.closeSync();
  }
}

/// The engine of [dir], or null when it isn't a game folder. With
/// [allowOther], a folder holding a program but no known engine counts as
/// [GameEngine.other] (the top of a library folder, or a folder the user
/// picked by hand).
GameEngine? detectEngine(Directory dir, {bool allowOther = false}) =>
    _detect(dir.path, _list(dir.path), allowOther: allowOther);

GameEngine? _detect(String path, _Listing l, {required bool allowOther}) {
  final files = l.files, dirs = l.dirs;
  bool anyFile(bool Function(String) test) => files.keys.any(test);
  final exes = files.keys.where((n) => n.endsWith('.exe')).toList();

  // Ren'Py: game/ holding scripts or archives. A bare game/ (a save backup
  // with only game/saves) isn't a game.
  if (dirs.containsKey('game')) {
    // The folder's own listing usually settles it (Ren'Py's renpy/ engine
    // folder or its launcher .py), which saves listing game/: it can hold
    // hundreds of files, each a round trip on a network share.
    if (dirs.containsKey('renpy') || anyFile((n) => n.endsWith('.py'))) return GameEngine.renpy;
    final g = _list(p.join(path, dirs['game']!));
    if (g.files.keys.any((n) => n.endsWith('.rpa') || n.endsWith('.rpyc') || n.endsWith('.rpy') || n.endsWith('.rpymc'))) {
      return GameEngine.renpy;
    }
  }
  // A renpy/ engine folder without game/ (a broken copy) still counts, but
  // only if it holds the engine: a category folder named "RenPy" must not.
  if (dirs.containsKey('renpy') && !dirs.containsKey('game')) {
    final r = dirs['renpy']!;
    if (_has(path, [r, 'bootstrap.py']) || _has(path, [r, '__init__.py']) || _has(path, [r, 'common'])) {
      return GameEngine.renpy;
    }
  }
  // macOS builds: Game.app/Contents/Resources/autorun holds a Ren'Py game.
  for (final d in dirs.keys) {
    if (d.endsWith('.app') && _has(path, [dirs[d]!, 'Contents', 'Resources', 'autorun', 'game'])) {
      return GameEngine.renpyMac;
    }
  }

  // Unity: <Name>_Data beside <Name>.exe, or UnityPlayer.dll.
  if (files.containsKey('unityplayer.dll') ||
      dirs.keys.any((d) => d.endsWith('_data') && files.containsKey('${d.substring(0, d.length - 5)}.exe'))) {
    return GameEngine.unity;
  }

  // Unreal: Engine/ plus a project folder with Content/Paks or Binaries.
  if (dirs.containsKey('engine') &&
      dirs.entries.any((e) =>
          e.key != 'engine' && (_has(path, [e.value, 'Content', 'Paks']) || _has(path, [e.value, 'Binaries'])))) {
    return GameEngine.unreal;
  }

  // RPG Maker. Each deeper check runs only when the listing already shows the
  // folder it needs: on a network share every check is a round trip.
  final www = dirs['www'], js = dirs['js'];
  if ((www != null && _has(path, [www, 'js', 'rpg_core.js'])) || (js != null && _has(path, [js, 'rpg_core.js']))) {
    return GameEngine.rpgmMv;
  }
  if ((js != null && _has(path, [js, 'rmmz_core.js'])) || (www != null && _has(path, [www, 'js', 'rmmz_core.js']))) {
    return GameEngine.rpgmMz;
  }
  if (anyFile((n) => n.endsWith('.rgss3a') || n.endsWith('.rgss2a') || n.endsWith('.rgssad')) ||
      (files.containsKey('game.ini') && files.containsKey('game.exe'))) {
    return GameEngine.rpgmVx;
  }

  // Wolf RPG / Kirikiri.
  if (files.containsKey('data.wolf') ||
      (dirs.containsKey('data') && _list(p.join(path, dirs['data']!)).files.keys.any((n) => n.endsWith('.wolf')))) {
    return GameEngine.wolf;
  }
  if (files.containsKey('data.xp3')) return GameEngine.kirikiri;

  // Godot: a .pck beside the exe.
  if (exes.isNotEmpty && anyFile((n) => n.endsWith('.pck'))) return GameEngine.godot;

  // HTML games packaged as apps (Electron, NW.js).
  final resources = dirs['resources'];
  if ((resources != null && (_has(path, [resources, 'app.asar']) || _has(path, [resources, 'app']))) ||
      files.containsKey('chrome_100_percent.pak') ||
      (files.containsKey('package.json') && files.containsKey('nw.dll'))) {
    return GameEngine.html;
  }

  if (anyFile((n) => n.endsWith('.swf'))) return GameEngine.flash;
  if (files.containsKey('index.html')) return GameEngine.html;

  // Godot with the .pck built into the exe (the exe ends in "GDPC"). Reading
  // an exe is the costliest check here: on a network share Windows Defender
  // scans the whole file when it's opened. So it's tried last, and only on a
  // folder shaped like a single-file export: one or two programs, a few
  // other files, no folders.
  final candidates = exes.where((n) => !_notAGameExe.hasMatch(n)).toList();
  if (candidates.isNotEmpty && candidates.length <= 2 && dirs.length <= 1 && files.length <= 8) {
    for (final exe in candidates) {
      if (_endsWithGdpc(p.join(path, files[exe]!))) return GameEngine.godot;
    }
  }

  if (allowOther) {
    if (exes.any((n) => !_notAGameExe.hasMatch(n))) return GameEngine.other;
    // A game of unknown engine one folder down (Game/Game/Game.exe), as the
    // scanner always found. Not when the inner folder is a recognisable game:
    // that one is found on the next level, and this is just its category.
    if (dirs.length == 1 && files.keys.every((n) => !n.endsWith('.exe'))) {
      final innerPath = p.join(path, dirs.values.first);
      final inner = _list(innerPath);
      if (inner.files.keys.any((n) => n.endsWith('.exe') && !_notAGameExe.hasMatch(n)) &&
          _detect(innerPath, inner, allowOther: false) == null) {
        return GameEngine.other;
      }
    }
  }
  return null;
}

/// What a search of one library folder found.
class LibrarySearch {
  /// Game folders with their engines, in the order found (level by level).
  final List<(Directory, GameEngine)> games;

  /// Archive files lying in folders that aren't games.
  final List<File> archives;
  const LibrarySearch(this.games, this.archives);
}

const archiveExtensions = {'.zip', '.rar', '.7z', '.rpa', '.rpy', '.py'};

/// Finds the games in [libraryDir]. Every top folder is checked first; with
/// [subfolders], each further level opens only folders that weren't games,
/// down to [maxSearchDepth]. Links and junctions are never followed, folders
/// over [maxEntriesToOpen] entries aren't opened, and dot-folders, saves and
/// caches are skipped. A folder of programs with no known engine counts as a
/// game only at the top (level 0), as it always has.
LibrarySearch searchLibrary(Directory libraryDir, {bool subfolders = true}) {
  final games = <(Directory, GameEngine)>[];
  final archives = <File>[];

  final top = _list(libraryDir.path);
  for (final f in top.files.values) {
    if (archiveExtensions.contains(p.extension(f).toLowerCase())) archives.add(File(p.join(libraryDir.path, f)));
  }
  var pending = [
    for (final d in top.dirs.values)
      if (!d.startsWith('.') && !_isLink(p.join(libraryDir.path, d))) p.join(libraryDir.path, d),
  ]..sort();

  for (var level = 0; level <= maxSearchDepth && pending.isNotEmpty; level++) {
    final next = <String>[];
    for (final path in pending) {
      final l = _list(path);
      final engine = _detect(path, l, allowOther: level == 0);
      if (engine != null) {
        games.add((Directory(path), engine));
        continue;
      }
      if (!subfolders || l.length > maxEntriesToOpen) continue;
      for (final f in l.files.values) {
        if (archiveExtensions.contains(p.extension(f).toLowerCase()) && !f.toLowerCase().endsWith('.py')) {
          archives.add(File(p.join(path, f)));
        }
      }
      for (final d in l.dirs.values) {
        if (d.startsWith('.') || _isEngineInternal(d.toLowerCase())) continue;
        final full = p.join(path, d);
        if (_isLink(full)) continue;
        next.add(full);
      }
    }
    next.sort();
    pending = next;
  }
  return LibrarySearch(games, archives);
}

bool _isLink(String path) {
  try {
    return FileSystemEntity.isLinkSync(path);
  } catch (_) {
    return true;
  }
}

/// True for folder names that are only a version ("v0.5", "0.6.1",
/// "Version 2"), whose game title is the folder above.
bool isVersionOnlyName(String name) =>
    RegExp(r'^(v|ver|version)?[\s._-]*\d+(\.\d+)*[a-z]?(\s*(alpha|beta|rc\d*|demo|final))?$', caseSensitive: false)
        .hasMatch(name.trim());
