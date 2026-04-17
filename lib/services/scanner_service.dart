import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/archive_item.dart';
import '../models/game_group.dart';
import '../models/game_version.dart';
import '../models/user_data.dart';

// Ported from 1.0 Python logic.

// ── Name Parsing ──────────────────────────────────────────────────────────────

const _platformSuffixes = {
  'pc', 'win', 'windows', 'linux', 'mac',
  'standard', 'free', 'cracked', 'official',
  'ultra', 'compressed', 'public', 'release', 'market',
};

// Matches version suffixes in folder names
final _versionRe = RegExp(
  r'[-_]'
  r'(v\.?\d[\w.]*|\d+\.\d[\w.]*|\d{3,}|Demo|DEMO|demo'
  r'|Chapter[\w_]*|Day\d+[\w_]*|Act\.[\w.]+|Final|FINAL'
  r'|VER_[\w.]+|Vers\.[\w.]+|Episode[\w_-]*)'
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
  return s.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Returns (baseKey, versionStr, displayName)
(String, String, String) parseFolderName(String name) {
  // Strip leading bracket groups like "[Completed]"
  final nameClean = name.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
  final m = _versionRe.firstMatch(nameClean);
  var versionStr = '';
  var baseRaw = nameClean;
  if (m != null) {
    versionStr = m.group(1) ?? '';
    baseRaw = nameClean.substring(0, m.start);
  }
  var tokens = baseRaw.split(RegExp(r'[-_\s]+')).where((t) => t.isNotEmpty).toList();
  tokens = _stripPlatform(tokens);
  if (versionStr.isEmpty) tokens = _stripPlatform(tokens);
  final baseForDisplay = tokens.join(' ');
  final displayName = _camelSplit(baseForDisplay);
  final baseKey = baseForDisplay.replaceAll(RegExp(r'[-_\s]+'), '').toLowerCase();
  return (baseKey, versionStr, displayName.isNotEmpty ? displayName : name);
}

List<int> parseVersionTuple(String v) {
  if (v.isEmpty) return [-2];
  if (v.toLowerCase() == 'demo' || v.toLowerCase() == 'final') return [-1];
  final nums = RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();
  return nums.isNotEmpty ? nums : [-1];
}

int compareVersionTuples(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
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
        final v = scanGameVersion(e);
        if (v != null) versions.add(v);
      } else if (e is File) {
        final ext = p.extension(e.path).toLowerCase();
        if (['.zip', '.rar', '.py', '.rpa'].contains(ext)) {
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
      final sorted = [...g.versions]..sort((a, b) =>
          compareVersionTuples(
              parseVersionTuple(a.versionStr),
              parseVersionTuple(b.versionStr)));
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
  static void autoDetectPatches(List<GameGroup> groups, UserData ud) {
    for (final g in groups) {
      for (final v in g.versions) {
        final patchesDir = Directory(p.join(v.folderPath.path, 'game', '.patches'));
        if (!patchesDir.existsSync()) continue;
        // Patch registration happens in UserDataNotifier.setPatchState;
        // this call surface-checks that the directory exists.
      }
    }
  }
}
