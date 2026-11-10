import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/archive_item.dart';
import '../models/game_group.dart';
import 'gallery_service.dart';
import '../models/game_version.dart';
import '../models/user_data.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'game_detect.dart';

// Ported from 1.0 Python logic.

// ── Name Parsing ──────────────────────────────────────────────────────────────

const _platformSuffixes = {
  'pc', 'win', 'windows', 'linux', 'mac',
  'standard', 'free', 'cracked', 'official',
  'ultra', 'compressed', 'public', 'release', 'market',
};

// Matches version suffixes in folder names. Chapter/Episode keep a number that
// follows a separator ("Chapter-1") without swallowing a platform tag after it
// ("Episode-10-pc" → "Episode-10"). A space also separates a version, but only
// a dotted one ("New in City 0.3.3", "BBUltimate v0.11") so titles like
// "Persona 4" or "Cyberpunk 2077" keep their numbers.
final _versionRe = RegExp(
  r'(?:[-_]|\s(?=(?:v?\.?|a\.)\d+\.\d))'
  r'(v\.?\d[\w.]*|a\.\d[\w.]*|\d+\.\d[\w.]*|\d{3,}|Demo|DEMO|demo'
  r'|Chapter[-_]?\d[\w.]*|Chapter\w*|Day\d+[\w_]*|Act\.[\w.]+|Final|FINAL'
  r'|VER_[\w.]+|Vers\.[\w.]+|Episode[-_]?\d[\w.]*|Episode\w*)'
  r'(?:[-_\s].+)?$',
  caseSensitive: false,
);

List<String> _stripPlatform(List<String> tokens) {
  while (tokens.isNotEmpty &&
      _platformSuffixes.contains(tokens.last.toLowerCase())) {
    tokens.removeLast();
  }
  return tokens;
}

String _camelSplit(String s) {
  s = s.replaceAll(RegExp(r'[-_]+'), ' ');
  s = s.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  // A capital that starts a new word after another capital:
  // "AFamily" → "A Family", "HTMLGame" → "HTML Game".
  s = s.replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}');
  return s.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Returns (baseKey, versionStr, displayName)
(String, String, String) parseFolderName(String name) {
  final (tokens, versionStr) = _folderNameParts(name);
  final baseForDisplay = tokens.join(' ');
  final displayName = _camelSplit(baseForDisplay);
  final baseKey = _titleKey(tokens);
  return (baseKey, versionStr, displayName.isNotEmpty ? displayName : name);
}

/// Title tokens (platform tags stripped) and version string of a folder or
/// archive name — the raw parts behind [parseFolderName].
(List<String>, String) _folderNameParts(String name) {
  // Strip leading bracket groups like "[Completed]"
  final nameClean = name.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
  final m = _versionRe.firstMatch(nameClean);
  var versionStr = '';
  var baseRaw = nameClean;
  if (m != null) {
    versionStr = m.group(1) ?? '';
    baseRaw = nameClean.substring(0, m.start);
  }
  // "_" is a word character, so "v0.4.8_Win" arrives with its platform tag
  // attached ("-Win" is split off by the regex) — drop trailing platform/junk
  // words the same way the title does.
  if (versionStr.contains('_')) {
    final parts = _stripPlatform(versionStr.split('_'));
    if (parts.isNotEmpty) versionStr = parts.join('_');
  }
  var tokens = baseRaw.split(RegExp(r'[-_\s]+')).where((t) => t.isNotEmpty).toList();
  tokens = _stripPlatform(tokens);
  if (versionStr.isEmpty) tokens = _stripPlatform(tokens);
  return (tokens, versionStr);
}

String _titleKey(List<String> tokens) =>
    tokens.join(' ').replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();

/// Inner archive folders that say nothing about the game.
const _genericFolderNames = {
  'game', 'games', 'windows', 'win', 'win32', 'win64', 'pc', 'linux', 'mac',
  'build', 'dist', 'release', 'x64', 'x86', 'output', 'data', 'files',
  'content', 'extracted', 'newfolder',
};

/// Names the folder an extracted game goes into, from the best parts of the
/// archive's file name and the single folder inside it (when there is one):
///   • title — the one matching a game already in the library ([libraryKeys]),
///     else the more descriptive one (more words), the inner folder on a tie;
///     generic inner folders ("game", "Windows", …) don't count;
///   • version — the more specific one (more numbers: 4.3.1 beats 4.3), the
///     higher one if they're equally specific.
/// Platform tags and junk after the version are dropped, so the result parses
/// back cleanly: `<Title>-<version>`.
/// `<title>-<version>` for a folder, but only in a form that [parseFolderName]
/// reads back as that game and a version with the same number, so the new
/// folder joins the game as its newest version. Download labels can be loose
/// ("Chapter 3.6.5 Patched", "Ch.3.6.5"); those fall back to just the version
/// number. Null when nothing reads back, so the caller can plan another name.
String? readableFolderName(String title, String version) {
  String clean(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(RegExp(r'[. ]+$'), '').trim();
  final titleKey = parseFolderName(clean(title)).$1;
  if (titleKey.isEmpty) return null;
  final number = RegExp(r'\d+(?:\.\d+)*[a-z]?', caseSensitive: false).firstMatch(version)?.group(0);
  final pre = RegExp(r'\b(alpha|beta|rc\d*|demo|final)\b', caseSensitive: false).firstMatch(version)?.group(0);
  // With a number, the folder uses just the number, plus a word that changes
  // its order (Alpha, Beta, RC, Demo, Final), so the same version labelled
  // differently by two sources gets one folder.
  final candidates = number != null
      ? [if (pre != null) ...['$number $pre', '$number-$pre', '$number$pre'], number]
      : [version.trim(), version.trim().replaceAll(RegExp(r'\s+'), '-')];
  for (final v in candidates) {
    if (v.isEmpty) continue;
    final name = clean('${title.trim()}-$v');
    final (key, parsed, _) = parseFolderName(name);
    // Alpha, Beta and RC change the order only if they survive the read-back.
    // Demo and Final are kept as written; the parser doesn't rank them after
    // a number yet (#17).
    final ordered = pre != null && !RegExp(r'^(demo|final)$', caseSensitive: false).hasMatch(pre);
    final keepsPre = !ordered || v == number || parsed.toLowerCase().contains(pre.toLowerCase());
    if (key == titleKey && parsed.isNotEmpty && keepsPre && (number == null || parsed.contains(number))) return name;
  }
  return null;
}

String planExtractFolderName({
  required String archiveStem,
  String? innerFolder,
  Set<String> libraryKeys = const {},
}) {
  final fromArchive = _folderNameParts(archiveStem);
  final innerUseful = innerFolder != null &&
      !_genericFolderNames.contains(_titleKey([innerFolder]));
  final fromInner = innerUseful ? _folderNameParts(innerFolder) : null;

  // Title
  var title = fromArchive.$1;
  if (fromInner != null && fromInner.$1.isNotEmpty) {
    final innerKnown = libraryKeys.contains(_titleKey(fromInner.$1));
    final archiveKnown = libraryKeys.contains(_titleKey(fromArchive.$1));
    int words(List<String> t) => _camelSplit(t.join(' ')).split(' ').length;
    if (fromArchive.$1.isEmpty || (innerKnown && !archiveKnown)) {
      title = fromInner.$1;
    } else if (!archiveKnown || innerKnown) {
      if (words(fromInner.$1) >= words(fromArchive.$1)) title = fromInner.$1;
    }
  }

  // Version
  final versions = [if (fromInner != null) fromInner.$2, fromArchive.$2]
      .where((v) => v.isNotEmpty)
      .toList();
  var version = '';
  for (final v in versions) {
    if (version.isEmpty) {
      version = v;
      continue;
    }
    final more = _versionNumbers(v).length - _versionNumbers(version).length;
    if (more > 0 || (more == 0 && compareVersionStrings(v, version) > 0)) version = v;
  }

  final name = [title.join(' '), if (version.isNotEmpty) version]
      .join('-')
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
      .replaceAll(RegExp(r'[. ]+$'), '');
  // Only use the plan if it reads back as the title + version we picked.
  final (key, parsedVersion, _) = parseFolderName(name);
  if (name.isEmpty || key != _titleKey(title) || parsedVersion != version) {
    return innerUseful ? innerFolder : archiveStem;
  }
  return name;
}

/// Orders folder-derived version strings, oldest first:
///   unknown (empty) < Demo < numbered versions < Final.
/// Numbered versions compare their digit runs in order (0.11.12 < 0.12.7;
/// 1.0 < 1.0.1), then the text after the last number: pre-releases come
/// before the plain release (0.5 Alpha < 0.5 Beta < 0.5 RC < 0.5), and other
/// letters after it (0.5 < 0.5a < 0.5b).
int compareVersionStrings(String a, String b) {
  final ra = _versionRank(a), rb = _versionRank(b);
  if (ra != rb) return ra.compareTo(rb);
  final na = _versionNumbers(a), nb = _versionNumbers(b);
  for (var i = 0; i < na.length && i < nb.length; i++) {
    if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
  }
  if (na.length != nb.length) return na.length.compareTo(nb.length);
  final sa = _suffixRank(a), sb = _suffixRank(b);
  if (sa.$1 != sb.$1) return sa.$1.compareTo(sb.$1);
  return sa.$2.compareTo(sb.$2);
}

int _versionRank(String v) {
  final s = v.trim().toLowerCase();
  if (s.isEmpty) return -2;
  if (s == 'demo') return -1;
  if (s == 'final') return 1;
  return 0;
}

List<int> _versionNumbers(String v) =>
    RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();

/// (rank, text) for what follows the last number: pre-release words below the
/// plain release (0), any other letters above it.
(int, String) _suffixRank(String v) {
  final last = RegExp(r'\d+').allMatches(v).lastOrNull;
  final tail = (last == null ? v : v.substring(last.end))
      .replaceAll(RegExp(r'[-_.\s]+'), '')
      .toLowerCase();
  if (tail.isEmpty) return (0, '');
  if (tail.startsWith('alpha')) return (-3, tail);
  if (tail.startsWith('beta')) return (-2, tail);
  if (RegExp(r'^(rc|pre|preview|test)').hasMatch(tail)) return (-1, tail);
  return (1, tail);
}

// ── Game Detection ────────────────────────────────────────────────────────────

/// True when [dir] holds a Ren'Py game (see [detectEngine]).
bool isRenpyDir(Directory dir) => detectEngine(dir) == GameEngine.renpy;

/// Programs that ship beside a game but aren't it.
final _helperExe = RegExp(r'(crashhandler|crashpad|unins\d*|setup|install|uninstall|-32|notification_helper|dxwebsetup|vc_?redist|ue4prereq|unitycrash)',
    caseSensitive: false);

/// The program that starts the game in [dir]: the one named like the game's
/// own files (`Name.exe` beside `Name_Data` or `Name.py`), else the first
/// that isn't a crash handler, installer or uninstaller.
File? pickGameExe(Directory dir) {
  final entries = dir.listSync(followLinks: false);
  final exes = entries.whereType<File>().where((f) => f.path.toLowerCase().endsWith('.exe')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (exes.isEmpty) return null;
  final stems = <String>{
    for (final e in entries)
      if (e is Directory && e.path.toLowerCase().endsWith('_data'))
        p.basename(e.path).substring(0, p.basename(e.path).length - 5).toLowerCase()
      else if (e is File && e.path.toLowerCase().endsWith('.py'))
        p.basenameWithoutExtension(e.path).toLowerCase(),
  };
  for (final exe in exes) {
    if (stems.contains(p.basenameWithoutExtension(exe.path).toLowerCase())) return exe;
  }
  return exes.where((e) => !_helperExe.hasMatch(p.basename(e.path))).firstOrNull ?? exes.first;
}

// ── Save Directory Detection ──────────────────────────────────────────────────

String? _readSaveDirFromOptions(Directory gamePath) {
  final opt = File(p.join(gamePath.path, 'game', 'options.rpy'));
  if (!opt.existsSync()) return null;
  try {
    final text = opt.readAsStringSync();
    final m = RegExp(r'''config\.save_directory\s*=\s*["']([^"']+)["']''').firstMatch(text);
    return m?.group(1);
  } catch (_) {
    return null;
  }
}

Directory? _findAppdataSaveDir(String baseKey, Directory appdataRenpy) {
  if (!appdataRenpy.existsSync()) return null;
  try {
    final candidates = appdataRenpy.listSync().whereType<Directory>().toList();
    for (final c in candidates) {
      final stripped = c.path.split(p.separator).last
          .replaceAll(RegExp(r'[-_]\d{6,}$'), '');
      final ck = stripped.replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();
      if (ck == baseKey) return c;
      final ml = [baseKey.length, ck.length, 5].reduce((a, b) => a < b ? a : b);
      if (ml >= 5 && ck.startsWith(baseKey.substring(0, ml))) return c;
    }
  } catch (_) {}
  return null;
}

Directory? _resolveAppdata(Directory gamePath, String baseKey) {
  final appdataRenpy = Directory(
      p.join(Platform.environment['APPDATA'] ?? '', 'RenPy'));
  final name = _readSaveDirFromOptions(gamePath);
  if (name != null) {
    final exact = Directory(p.join(appdataRenpy.path, name));
    if (exact.existsSync()) return exact;
  }
  return _findAppdataSaveDir(baseKey, appdataRenpy);
}

// ── Metadata Loading ──────────────────────────────────────────────────────────

const _metadataDir = '.vnpf';
const _metadataFile = 'metadata.json';

Map<String, dynamic> loadGameMetadata(Directory folderPath) {
  final f = File(p.join(folderPath.path, _metadataDir, _metadataFile));
  if (!f.existsSync()) return {};
  try {
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

Future<void> saveGameMetadata(Directory folderPath, Map<String, dynamic> meta) async {
  final dir = Directory(p.join(folderPath.path, _metadataDir));
  dir.createSync(recursive: true);
  await File(p.join(dir.path, _metadataFile)).writeAsString(
    const JsonEncoder.withIndent('  ').convert(meta),
  );
}

/// Returns the cover art path for a game version.
/// Priority: .vnpf/cover.jpg/png > gui/main_menu.png > gui/game_menu.png >
///           gui/window_icon.png > largest gui image
File? findArtPath(Directory gamePath) {
  const artCandidates = [
    '../.vnpf/cover.jpg',
    '../.vnpf/cover.png',
    '../.vnpf/cover.webp',
    'gui/main_menu.png',
    'gui/main_menu.jpg',
    'gui/game_menu.png',
    'gui/game_menu.jpg',
    'gui/window_icon.png',
  ];
  final gameDir = Directory(p.join(gamePath.path, 'game'));
  for (final rel in artCandidates) {
    final f = File(p.normalize(p.join(gameDir.path, rel)));
    if (f.existsSync() && f.lengthSync() > 1000) return f;
  }
  final guiDir = Directory(p.join(gameDir.path, 'gui'));
  if (guiDir.existsSync()) {
    try {
      final imgs = guiDir.listSync().whereType<File>().where((f) {
        final ext = f.path.split('.').last.toLowerCase();
        return ext == 'png' || ext == 'jpg' || ext == 'jpeg';
      }).toList();
      if (imgs.isNotEmpty) {
        imgs.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
        if (imgs.first.lengthSync() > 20000) return imgs.first;
      }
    } catch (_) {}
  }
  return null;
}

/// Returns ordered image paths for the carousel (cover first, then screenshots).
List<File> groupCarouselPaths(GameGroup g, String? customArtPath) {
  // Custom art override
  if (customArtPath != null) {
    final cf = File(customArtPath);
    if (cf.existsSync()) {
      final paths = <File>[cf];
      _addScreenshots(g, paths);
      return paths;
    }
  }
  // .vnpf cover
  for (final v in g.versions.reversed) {
    final vnpf = Directory(p.join(v.folderPath.path, _metadataDir));
    for (final ext in ['cover.jpg', 'cover.png', 'cover.webp']) {
      final cover = File(p.join(vnpf.path, ext));
      if (cover.existsSync()) {
        final paths = <File>[cover];
        _addScreenshots(g, paths);
        return paths;
      }
    }
  }
  // In-game art
  for (final v in g.versions.reversed) {
    final art = findArtPath(v.folderPath);
    if (art != null) {
      final paths = <File>[art];
      _addScreenshots(g, paths);
      return paths;
    }
  }
  // Screenshots only (no cover)
  final paths = <File>[];
  _addScreenshots(g, paths);
  return paths;
}

void _addScreenshots(GameGroup g, List<File> paths) {
  for (final v in g.versions.reversed) {
    final vnpf = Directory(p.join(v.folderPath.path, _metadataDir));
    if (!vnpf.existsSync()) continue;
    for (final s in GalleryService.screenshots(vnpf)) {
      if (!paths.contains(s)) paths.add(s);
    }
  }
}

// ── Scanner ───────────────────────────────────────────────────────────────────

/// Reads one game folder. [engine] is passed when the library search has
/// already recognised it; otherwise it's detected here, with a folder of
/// programs and no known engine accepted (a top folder or one picked by hand).
/// [cached] is this folder's entry from the library cache, if any: its save
/// info is reused when both save folders' timestamps are unchanged (Ren'Py
/// writes every save as a new file renamed into place, which changes the
/// folder's time). [onCache] receives the entry to keep for next time.
GameVersion? scanGameVersion(Directory dir,
    {GameEngine? engine, Map? cached, void Function(Map<String, dynamic> entry)? onCache}) {
  engine ??= detectEngine(dir, allowOther: true);
  if (engine == null) return null;
  final renpy = engine == GameEngine.renpy;

  // A folder named only by its version (Game/v0.5) takes its title from the
  // folder above.
  final folder = p.basename(dir.path);
  final parsedName = isVersionOnlyName(folder) ? '${p.basename(dir.parent.path)}-$folder' : folder;
  final (baseKey, versionStr, displayName) = parseFolderName(parsedName);
  if (baseKey.isEmpty) return null;

  // Find exe
  File? exePath;
  try {
    exePath = pickGameExe(dir);
    if (exePath == null && !renpy) {
      final subdirs = dir.listSync().whereType<Directory>().toList();
      if (subdirs.length == 1) exePath = pickGameExe(subdirs.first);
    }
  } catch (_) {}

  final localSaves = Directory(p.join(dir.path, 'game', 'saves'));
  final appdataSaves = renpy ? _resolveAppdata(dir, baseKey) : null;
  return GameVersion(
    folderName: p.basename(dir.path),
    folderPath: dir,
    baseKey: baseKey,
    versionStr: versionStr,
    displayName: displayName,
    exePath: exePath,
    localSaveDir: localSaves,
    appdataSaveDir: appdataSaves,
    metadata: loadGameMetadata(dir),
    isRenpy: renpy,
    engine: engine,
    saves: _savesWithCache(localSaves, appdataSaves, engine, cached, onCache),
    hasVnpf: Directory(p.join(dir.path, _metadataDir)).existsSync(),
  );
}

/// Reads a version's saves from its local game/saves folder and Ren'Py's
/// AppData folder (Ren'Py writes each save to both; AppData also keeps saves
/// from earlier installs). Kept cheap: name listings plus a few file stats.
///   • Save names say who made them: "auto-1-LT1" autosave, "quick-1-LT1"
///     quicksave, "1-1-LT1" a save the player made; engine/game-made saves
///     ("_tracesave-…", named ones) are ignored.
///   • Ren'Py rotates autosaves so auto-1 is always the newest, and rewrites
///     `persistent` whenever the game runs — their times stand in for "last
///     played", and auto-1's own record gives the game version last played.
/// A folder's modified time in ms, or null when it doesn't exist.
int? _folderTime(Directory? d) {
  if (d == null) return null;
  try {
    final st = d.statSync();
    return st.type == FileSystemEntityType.notFound ? null : st.modified.millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

SaveInfo _savesWithCache(Directory local, Directory? appdata, GameEngine engine, Map? cached,
    void Function(Map<String, dynamic>)? onCache) {
  final localTime = _folderTime(local), appdataTime = _folderTime(appdata);
  SaveInfo? saves;
  // Reused only when everything matches; any doubt means a full read.
  if (cached != null &&
      cached['saves'] is Map &&
      cached['local_t'] == localTime &&
      cached['appdata_t'] == appdataTime &&
      cached['appdata'] == appdata?.path) {
    saves = SaveInfo.fromJson(cached['saves'] as Map);
  }
  saves ??= _readSaves(local, appdata);
  onCache?.call({
    'engine': engine.name,
    'local_t': localTime,
    'appdata_t': appdataTime,
    'appdata': appdata?.path,
    'saves': saves.toJson(),
  });
  return saves;
}

SaveInfo _readSaves(Directory local, Directory? appdata) {
  final localNames = _listNames(local);
  final hasLocalSaves = localNames.any((n) => n.endsWith('.save'));
  // Counts from both folders' names; file stats/reads from the local copy
  // when this version has one.
  final names = {...localNames, if (appdata != null) ..._listNames(appdata)};
  final dir = hasLocalSaves || appdata == null ? local : appdata;

  var manual = 0, auto = 0;
  for (final n in names) {
    if (!n.endsWith('.save')) continue;
    if (n.startsWith('auto-')) {
      auto++;
    } else if (n.startsWith('quick-') || RegExp(r'^\d+-\d+').hasMatch(n)) {
      manual++;
    }
  }

  File fileFor(String name) {
    final preferred = File(p.join(dir.path, name));
    if (appdata == null || preferred.existsSync()) return preferred;
    return File(p.join(appdata.path, name));
  }

  DateTime? modified(String name) {
    try {
      return fileFor(name).lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  // The newest save: auto-1, else quick-1, else any save the player made.
  String? newest;
  for (final pattern in [RegExp(r'^auto-1[-.]'), RegExp(r'^quick-1[-.]'), RegExp(r'^\d+-\d+')]) {
    newest = names.where((n) => n.endsWith('.save') && pattern.hasMatch(n)).firstOrNull;
    if (newest != null) break;
  }
  final newestAt = newest == null ? null : modified(newest);

  DateTime? lastSaveAt = newestAt;
  for (final source in [local, ?appdata]) {
    final persistent = File(p.join(source.path, 'persistent'));
    try {
      if (persistent.existsSync()) {
        final t = persistent.lastModifiedSync();
        if (lastSaveAt == null || t.isAfter(lastSaveAt)) lastSaveAt = t;
      }
    } catch (_) {}
  }

  return SaveInfo(
    lastSaveAt: lastSaveAt,
    hasLocalSaves: hasLocalSaves,
    manualSaves: manual,
    autoSaves: auto,
    newestSaveVersion: newest == null ? null : _saveGameVersion(fileFor(newest)),
    newestSaveAt: newestAt,
  );
}

List<String> _listNames(Directory dir) {
  try {
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList();
  } catch (_) {
    return const [];
  }
}

/// The game version (config.version) a Ren'Py save was made in — the "json"
/// entry of the save's zip, e.g. {"_version": "0.3.2", ...}.
String? _saveGameVersion(File save) {
  final bytes = readZipEntry(save, 'json');
  if (bytes == null) return null;
  try {
    final json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    final version = json is Map ? json['_version'] : null;
    return version is String && version.trim().isNotEmpty ? version.trim() : null;
  } catch (_) {
    return null;
  }
}

/// Reads one entry of a zip without loading the rest — a Ren'Py save's tiny
/// "json" sits next to a multi-megabyte pickled "log". Finds the entry via
/// the central directory and inflates just that (stored or deflated).
List<int>? readZipEntry(File file, String entryName) {
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    final length = raf.lengthSync();
    final tailLength = length < 65557 ? length : 65557; // EOCD + max comment
    raf.setPositionSync(length - tailLength);
    final tail = raf.readSync(tailLength);
    final tailData = ByteData.sublistView(tail);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tailData.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;
    final dirSize = tailData.getUint32(eocd + 12, Endian.little);
    final dirOffset = tailData.getUint32(eocd + 16, Endian.little);
    raf.setPositionSync(dirOffset);
    final dir = raf.readSync(dirSize);
    final dirData = ByteData.sublistView(dir);
    var pos = 0;
    while (pos + 46 <= dir.length && dirData.getUint32(pos, Endian.little) == 0x02014b50) {
      final method = dirData.getUint16(pos + 10, Endian.little);
      final compressedSize = dirData.getUint32(pos + 20, Endian.little);
      final nameLength = dirData.getUint16(pos + 28, Endian.little);
      final extraLength = dirData.getUint16(pos + 30, Endian.little);
      final commentLength = dirData.getUint16(pos + 32, Endian.little);
      final headerOffset = dirData.getUint32(pos + 42, Endian.little);
      final name = utf8.decode(dir.sublist(pos + 46, pos + 46 + nameLength), allowMalformed: true);
      if (name == entryName) {
        raf.setPositionSync(headerOffset);
        final header = ByteData.sublistView(raf.readSync(30));
        if (header.getUint32(0, Endian.little) != 0x04034b50) return null;
        raf.setPositionSync(headerOffset +
            30 +
            header.getUint16(26, Endian.little) +
            header.getUint16(28, Endian.little));
        final data = raf.readSync(compressedSize);
        if (method == 0) return data;
        if (method == 8) return ZLibCodec(raw: true).decode(data);
        return null;
      }
      pos += 46 + nameLength + extraLength + commentLength;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
  }
}

ArchiveItem scanArchive(File file) {
  final (baseKey, versionStr, _) = parseFolderName(
      p.basenameWithoutExtension(file.path));
  String modTime = '';
  try {
    modTime = file.statSync().modified.toIso8601String().substring(0, 10);
  } catch (_) {}
  int? size;
  try {
    size = file.lengthSync();
  } catch (_) {}
  return ArchiveItem(
    archivePath: file,
    baseKey: baseKey,
    versionStr: versionStr,
    modTime: modTime,
    sizeBytes: size,
  );
}

class ScannerService {
  /// Scans on a background isolate: it's all synchronous disk work (folder
  /// listings, metadata, save files) that would otherwise freeze the UI.
  /// [merges] is UserData.gameMerges: folders with a key in it join the game
  /// it points to.
  /// Every folder in [libraryDirs] is scanned. Versions of one game in
  /// different folders group into one game. A folder that can't be read,
  /// such as a drive that isn't plugged in, is skipped.
  /// Folders in [noSubfolders] are searched at their top level only; every
  /// other folder is also searched in its subfolders (#13).
  static Future<List<GameGroup>> scanAll(List<Directory> libraryDirs,
      {Map<String, String> merges = const {}, Set<String> noSubfolders = const {}}) async =>
      (await scanLibrary(libraryDirs, merges: merges, noSubfolders: noSubfolders)).groups;

  /// The full search. [cache] is the library cache from the last scan (game
  /// folder path → entry); the result carries the new one.
  static Future<ScanResult> scanLibrary(List<Directory> libraryDirs,
      {Map<String, String> merges = const {},
      Set<String> noSubfolders = const {},
      Map<String, dynamic> cache = const {},
      void Function(ScanProgress)? onProgress}) {
    if (onProgress == null) return Isolate.run(() => _scanAllSync(libraryDirs, merges, noSubfolders, cache, null));
    return _withProgress((send) => _scanAllSync(libraryDirs, merges, noSubfolders, cache, send), onProgress);
  }

  /// The isolate's entry point, made here so it carries only [work]: a
  /// closure made inside [_withProgress] would share its scope, Completer
  /// included, which can't be sent to another isolate.
  static void Function(SendPort) _isolateEntry(ScanResult Function(void Function(ScanProgress)) work) =>
      (SendPort out) {
        try {
          out.send(work(out.send));
        } catch (e, st) {
          out.send(['$e', '$st']);
        }
      };

  /// Runs [work] on a background isolate, passing its progress back.
  static Future<ScanResult> _withProgress(
      ScanResult Function(void Function(ScanProgress)) work, void Function(ScanProgress) onProgress) async {
    final port = ReceivePort();
    final done = Completer<ScanResult>();
    port.listen((msg) {
      if (msg is ScanProgress) {
        onProgress(msg);
      } else if (msg is ScanResult) {
        done.complete(msg);
        port.close();
      } else if (msg is List && msg.length == 2) {
        done.completeError(msg[0] as Object, StackTrace.fromString('${msg[1]}'));
        port.close();
      }
    });
    try {
      await Isolate.spawn(_isolateEntry(work), port.sendPort);
    } catch (e) {
      port.close();
      rethrow;
    }
    return done.future;
  }

  /// The quick pass for a normal start: only the games the cache knows,
  /// with saves reread where their timestamps changed. No searching, no
  /// archives; the full search follows and catches anything new or moved.
  static Future<ScanResult> scanCached(List<Directory> libraryDirs, Map<String, dynamic> cache,
      {Map<String, String> merges = const {}}) {
    return Isolate.run(() {
      final versions = <GameVersion>[];
      final next = <String, dynamic>{};
      final roots = [for (final d in libraryDirs) d.path];
      for (final entry in cache.entries) {
        final path = entry.key;
        if (!roots.any((r) => p.isWithin(r, path))) continue;
        final dir = Directory(path);
        if (!dir.existsSync()) continue;
        final e = entry.value as Map;
        final engine = GameEngine.values.where((g) => g.name == e['engine']).firstOrNull;
        final v = scanGameVersion(dir, engine: engine, cached: e, onCache: (c) => next[path] = c);
        if (v != null) versions.add(v);
      }
      return ScanResult(_buildGroups(versions, const [], merges), next);
    });
  }

  static ScanResult _scanAllSync(List<Directory> libraryDirs, Map<String, String> merges,
      Set<String> noSubfolders, Map<String, dynamic> cache, void Function(ScanProgress)? progress) {
    final versions = <GameVersion>[];
    final archives = <ArchiveItem>[];
    final next = <String, dynamic>{};

    // Finding games, every library folder first.
    final found = <(Directory, GameEngine)>[];
    var checked = 0;
    for (final dir in libraryDirs) {
      // A folder that isn't reachable right now is skipped; its games come
      // back when it is.
      progress?.call(ScanProgress(ScanStage.finding, done: checked, found: found.length, folder: dir.path));
      if (!dir.existsSync()) continue;
      final s = searchLibrary(dir, subfolders: !noSubfolders.contains(dir.path), onFolder: (path, level, games) {
        checked++;
        progress?.call(ScanProgress(ScanStage.finding, done: checked, found: found.length + games, folder: path));
      });
      found.addAll(s.games);
      for (final f in s.archives) {
        archives.add(scanArchive(f));
      }
    }

    // Reading each game: metadata and saves.
    for (final (i, (folder, engine)) in found.indexed) {
      progress?.call(ScanProgress(ScanStage.saves, done: i, total: found.length, found: found.length, folder: folder.path));
      final v = scanGameVersion(folder,
          engine: engine, cached: cache[folder.path] as Map?, onCache: (c) => next[folder.path] = c);
      if (v != null) versions.add(v);
    }

    return ScanResult(_buildGroups(versions, archives, merges), next);
  }

  static List<GameGroup> _buildGroups(
      List<GameVersion> versions, List<ArchiveItem> archives, Map<String, String> merges) {
    final groups = <String, GameGroup>{};

    for (final v in versions) {
      final k = merges[v.baseKey] ?? v.baseKey;
      groups[k] = groups[k] == null
          ? GameGroup(baseKey: k, displayName: v.displayName, versions: [v])
          : () {
              final g = groups[k]!;
              final newVersions = [...g.versions, v];
              return g.copyWith(
                displayName: v.displayName.length > g.displayName.length
                    ? v.displayName
                    : null,
                versions: newVersions,
              );
            }();
    }

    // Sort versions within each group by version tuple
    for (final k in groups.keys) {
      final g = groups[k]!;
      final sorted = [...g.versions]
        ..sort((a, b) => compareVersionStrings(a.versionStr, b.versionStr));
      groups[k] = g.copyWith(versions: sorted);
    }

    // Attach archives
    for (final a in archives) {
      final k = merges[a.baseKey] ?? a.baseKey;
      if (groups.containsKey(k)) {
        final g = groups[k]!;
        // Try to match archive version to a game version
        String? matched;
        for (final v in g.versions) {
          if (v.versionStr.isNotEmpty && v.versionStr == a.versionStr) {
            matched = v.folderName;
            break;
          }
        }
        matched ??= g.versions.isEmpty ? null : g.versions.last.folderName;
        final updated = a.copyWith(matchedFolder: matched);
        groups[k] = g.copyWith(archives: [...g.archives, updated]);
      } else {
        final (_, _, disp) = parseFolderName(p.basenameWithoutExtension(a.archivePath.path));
        groups[k] = GameGroup(baseKey: k, displayName: disp, archives: [a]);
      }
    }

    final result = groups.values.toList()
      ..sort((a, b) => a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase()));
    return result;
  }

  /// Scan each game version's .patches/ folder and register new entries in UserData.
  /// .patches/ lives at the ROOT of the game directory (sibling of game/), NOT inside game/.
  static void autoDetectPatches(List<GameGroup> groups, UserData ud) {
    for (final g in groups) {
      for (final v in g.versions) {
        final patchesDir = Directory(p.join(v.folderPath.path, '.patches'));
        if (!patchesDir.existsSync()) continue;
        // Patch registration logic could go here or in UserData
      }
    }
  }

  /// Extracts an archive into the target directory.
  static Future<void> extractArchive(File archiveFile, Directory targetDir) async {
    final bytes = await archiveFile.readAsBytes();
    final Archive archive;
    
    final ext = p.extension(archiveFile.path).toLowerCase();
    if (ext == '.zip') {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (ext == '.tar' || ext == '.gz') {
      archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else {
      throw Exception('Unsupported archive format: $ext');
    }

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final f = File(p.join(targetDir.path, filename));
        f.parent.createSync(recursive: true);
        await f.writeAsBytes(data);
      } else {
        Directory(p.join(targetDir.path, filename)).createSync(recursive: true);
      }
    }
  }

  /// Finds files and folders in the library root that are not recognized as games or archives.
  static List<FileSystemEntity> findOrphans(List<Directory> libraryDirs, List<GameGroup> existingGroups) {
    final allEntries = <FileSystemEntity>[];
    for (final dir in libraryDirs) {
      try {
        allEntries.addAll(dir.listSync());
      } catch (_) {}
    }
    final orphans = <FileSystemEntity>[];

    // Build a set of paths that are already known
    final knownPaths = <String>{};
    for (final group in existingGroups) {
      for (final version in group.versions) {
        knownPaths.add(p.canonicalize(version.folderPath.path));
      }
      for (final archive in group.archives) {
        knownPaths.add(p.canonicalize(archive.archivePath.path));
      }
    }

    // Also ignore hidden files/folders and common system files
    final ignoreNames = {
      '.vnpf',
      '\$RECYCLE.BIN',
      'System Volume Information',
      'desktop.ini',
      'thumbs.db'
    };

    for (final entry in allEntries) {
      final name = p.basename(entry.path);
      if (name.startsWith('.') || ignoreNames.contains(name)) continue;

      final canonicalPath = p.canonicalize(entry.path);
      if (!knownPaths.contains(canonicalPath)) {
        orphans.add(entry);
      }
    }

    return orphans;
  }
}

/// A scan's games and the library cache to keep for the next start.
class ScanResult {
  final List<GameGroup> groups;
  final Map<String, dynamic> cache;
  const ScanResult(this.groups, this.cache);
}

enum ScanStage { finding, saves }

/// How far a scan has got, sent from its isolate for the loading screen.
class ScanProgress {
  final ScanStage stage;

  /// Folders checked while finding; games read while reading saves.
  final int done;

  /// Games to read (reading saves only; 0 while finding).
  final int total;
  final int found;

  /// The folder being looked at, to name one that stalls.
  final String? folder;

  const ScanProgress(this.stage, {this.done = 0, this.total = 0, this.found = 0, this.folder});

  double? get fraction => stage == ScanStage.saves && total > 0 ? done / total : null;
}
