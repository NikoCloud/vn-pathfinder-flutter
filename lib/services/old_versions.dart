import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/game_group.dart';
import '../models/game_version.dart';
import 'extraction_log.dart';

/// Old versions kept as their downloads (#24): when an update replaces a
/// version, its archive can move to a hidden `.vnpf-old-versions` folder in
/// its library folder instead of being lost with the game folder. The
/// developer's archive is already as small as that version gets, so nothing
/// is recompressed. The scanner skips dot-folders, so Library and Archive
/// never show them; the game page lists them with Restore.
const oldVersionsFolder = '.vnpf-old-versions';
const _manifest = 'old_versions.json';

class KeptDownload {
  final String file; // full path of the kept archive
  final String baseKey;
  final String version;
  final String title;
  final DateTime keptAt;
  const KeptDownload(this.file, this.baseKey, this.version, this.title, this.keptAt);

  Map<String, dynamic> toJson(String folder) => {
        'file': p.relative(file, from: folder),
        'base_key': baseKey,
        'version': version,
        'title': title,
        'kept_at': keptAt.toIso8601String(),
      };

  static KeptDownload? fromJson(Map j, String folder) {
    final file = j['file'] as String?;
    if (file == null) return null;
    return KeptDownload(p.join(folder, file), '${j['base_key'] ?? ''}', '${j['version'] ?? ''}',
        '${j['title'] ?? ''}', DateTime.tryParse('${j['kept_at'] ?? ''}') ?? DateTime(0));
  }
}

/// The archive [v] was extracted from, if it's still there: the extraction
/// log first, then an archive in the game whose version and folder match.
String? archiveForVersion(GameGroup group, GameVersion v) {
  for (final a in group.archives) {
    final path = a.archivePath.path;
    if (!File(path).existsSync()) continue;
    final folder = ExtractionLog.folderFor(path);
    if (folder != null && p.equals(folder, v.folderPath.path)) return path;
  }
  for (final a in group.archives) {
    if (!File(a.archivePath.path).existsSync()) continue;
    if (a.matchedFolder == v.folderName && a.versionStr.isNotEmpty && a.versionStr == v.versionStr) {
      return a.archivePath.path;
    }
  }
  return null;
}

List<KeptDownload> _read(String folder) {
  try {
    final list = jsonDecode(File(p.join(folder, _manifest)).readAsStringSync()) as List;
    return [for (final j in list) ?KeptDownload.fromJson(j as Map, folder)];
  } catch (_) {
    return [];
  }
}

void _write(String folder, List<KeptDownload> items) {
  final f = File(p.join(folder, _manifest));
  final tmp = File('${f.path}.new')..writeAsStringSync(jsonEncode([for (final k in items) k.toJson(folder)]));
  tmp.renameSync(f.path);
}

/// Moves [archivePath] into [libraryRoot]'s hidden old-versions folder and
/// records which game and version it is.
KeptDownload stashArchive({
  required String archivePath,
  required String libraryRoot,
  required String baseKey,
  required String version,
  required String title,
}) {
  final folder = Directory(p.join(libraryRoot, oldVersionsFolder))..createSync(recursive: true);
  var target = p.join(folder.path, p.basename(archivePath));
  var n = 2;
  while (File(target).existsSync()) {
    target = p.join(folder.path, '${p.basenameWithoutExtension(archivePath)} ($n)${p.extension(archivePath)}');
    n++;
  }
  _move(File(archivePath), target);
  ExtractionLog.forget(archivePath);
  final kept = KeptDownload(target, baseKey, version, title, DateTime.now());
  _write(folder.path, [..._read(folder.path), kept]);
  return kept;
}

/// Kept downloads of [baseKey] across [libraryDirs], newest version first.
List<KeptDownload> keptDownloads(String baseKey, List<String> libraryDirs) => [
      for (final d in libraryDirs)
        for (final k in _read(p.join(d, oldVersionsFolder)))
          if (k.baseKey == baseKey && File(k.file).existsSync()) k,
    ];

/// Puts a kept archive back in its library folder, ready to extract, and
/// forgets it. Returns where it now is.
String restoreKept(KeptDownload kept) {
  final folder = p.dirname(kept.file);
  final root = p.dirname(folder);
  var target = p.join(root, p.basename(kept.file));
  var n = 2;
  while (File(target).existsSync()) {
    target = p.join(root, '${p.basenameWithoutExtension(kept.file)} ($n)${p.extension(kept.file)}');
    n++;
  }
  _move(File(kept.file), target);
  _write(folder, [for (final k in _read(folder)) if (!p.equals(k.file, kept.file)) k]);
  return target;
}

void _move(File from, String to) {
  try {
    from.renameSync(to);
  } on FileSystemException {
    from.copySync(to);
    from.deleteSync();
  }
}

/// Copies saves only [oldFolder] has, or newer ones, into [newFolder]'s
/// game/saves before the old folder is removed. Ren'Py also keeps every save
/// in AppData; this covers saves kept only inside the game folder.
void carrySaves(String oldFolder, String newFolder) {
  final from = Directory(p.join(oldFolder, 'game', 'saves'));
  if (!from.existsSync()) return;
  final to = Directory(p.join(newFolder, 'game', 'saves'))..createSync(recursive: true);
  for (final f in from.listSync().whereType<File>()) {
    final dest = File(p.join(to.path, p.basename(f.path)));
    final time = f.lastModifiedSync();
    if (dest.existsSync() && !time.isAfter(dest.lastModifiedSync())) continue;
    f.copySync(dest.path);
    dest.setLastModifiedSync(time);
  }
}
