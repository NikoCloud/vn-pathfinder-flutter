import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/archive_item.dart';
import '../models/game_group.dart';
import '../models/game_version.dart';
import '../models/user_data.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

// Ported from 1.0 Python logic.

// ── Name Parsing ──────────────────────────────────────────────────────────────

const _platformSuffixes = {
  'pc', 'win', 'windows', 'linux', 'mac',
  'standard', 'free', 'cracked', 'official',
  'ultra', 'compressed', 'public', 'release', 'market',
};

// Matches version suffixes in folder names. Chapter/Episode keep a number that
// follows a separator ("Chapter-1") without swallowing a platform tag after it
// ("Episode-10-pc" → "Episode-10").
final _versionRe = RegExp(
  r'[-_]'
  r'(v\.?\d[\w.]*|\d+\.\d[\w.]*|\d{3,}|Demo|DEMO|demo'
  r'|Chapter[-_]?\d[\w.]*|Chapter\w*|Day\d+[\w_]*|Act\.[\w.]+|Final|FINAL'
  r'|VER_[\w.]+|Vers\.[\w.]+|Episode[-_]?\d[\w.]*|Episode\w*)'
  r'(?:[-_].+)?$',
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

bool isRenpyDir(Directory dir) {
  if (!dir.existsSync()) return false;
  if (Directory(p.join(dir.path, 'game')).existsSync()) return true;
  try {
    return dir.listSync().any((e) => e is File && e.path.endsWith('.py'));
  } catch (_) {
    return false;
  }
}

bool isExeGameDir(Directory dir) {
  if (!dir.existsSync()) return false;
  if (isRenpyDir(dir)) return false;
  try {
    if (dir.listSync().any((e) => e is File && e.path.endsWith('.exe'))) {
      return true;
    }
    final subdirs = dir.listSync().whereType<Directory>().toList();
    if (subdirs.length == 1) {
      return subdirs.first.listSync().any((e) => e is File && e.path.endsWith('.exe'));
    }
  } catch (_) {}
  return false;
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
    for (final ext in ['cover.jpg', 'cover.png']) {
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
    final shots = vnpf.listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('screenshot_'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final s in shots) {
      if (!paths.contains(s)) paths.add(s);
    }
  }
}

// ── Scanner ───────────────────────────────────────────────────────────────────

GameVersion? scanGameVersion(Directory dir) {
  final renpy = isRenpyDir(dir);
  final nonRenpy = !renpy && isExeGameDir(dir);
  if (!renpy && !nonRenpy) return null;

  final (baseKey, versionStr, displayName) = parseFolderName(p.basename(dir.path));
  if (baseKey.isEmpty) return null;

  // Find exe
  File? exePath;
  try {
    final exes = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.exe') && !f.path.contains('-32'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    exePath = exes.isEmpty ? null : exes.first;

    if (exePath == null && !renpy) {
      final subdirs = dir.listSync().whereType<Directory>().toList();
      if (subdirs.length == 1) {
        final subExes = subdirs.first.listSync().whereType<File>()
            .where((f) => f.path.endsWith('.exe') && !f.path.contains('-32'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        exePath = subExes.isEmpty ? null : subExes.first;
      }
    }
  } catch (_) {}

  return GameVersion(
    folderName: p.basename(dir.path),
    folderPath: dir,
    baseKey: baseKey,
    versionStr: versionStr,
    displayName: displayName,
    exePath: exePath,
    localSaveDir: Directory(p.join(dir.path, 'game', 'saves')),
    appdataSaveDir: renpy ? _resolveAppdata(dir, baseKey) : null,
    metadata: loadGameMetadata(dir),
    isRenpy: renpy,
  );
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
  static Future<List<GameGroup>> scanAll(Directory libraryDir) async {
    return await Future(() => _scanAllSync(libraryDir));
  }

  static List<GameGroup> _scanAllSync(Directory libraryDir) {
    final versions = <GameVersion>[];
    final archives = <ArchiveItem>[];

    final List<FileSystemEntity> entries;
    try {
      entries = libraryDir.listSync();
    } catch (_) {
      return [];
    }

    for (final e in entries) {
      if (e is Directory) {
        // Dot-folders are hidden/system — including in-progress extractions
        // (.vnp-extract-…).
        if (p.basename(e.path).startsWith('.')) continue;
        final v = scanGameVersion(e);
        if (v != null) versions.add(v);
      } else if (e is File) {
        final ext = p.extension(e.path).toLowerCase();
        // Archive types shown in the Archives tab.
        // .rpa/.rpy/.py = Ren'Py assets/scripts loose in library root
        // .zip/.rar/.7z = game download archives
        // Anything else at library root that isn't a game folder → orphan
        if (['.zip', '.rar', '.7z', '.rpa', '.rpy', '.py'].contains(ext)) {
          archives.add(scanArchive(e));
        }
      }
    }

    return _buildGroups(versions, archives);
  }

  static List<GameGroup> _buildGroups(
      List<GameVersion> versions, List<ArchiveItem> archives) {
    final groups = <String, GameGroup>{};

    for (final v in versions) {
      final k = v.baseKey;
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
      final k = a.baseKey;
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
  static List<FileSystemEntity> findOrphans(Directory libraryDir, List<GameGroup> existingGroups) {
    if (!libraryDir.existsSync()) return [];

    final allEntries = libraryDir.listSync();
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
