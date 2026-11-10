import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/game_group.dart';
import '../models/game_version.dart';
import 'drive_info.dart';

/// The same version of one game in more than one folder (#21), common when a
/// library spans several drives. The copy in the highest library folder is
/// kept; nothing is merged until the user asks.
class DuplicateSet {
  final GameGroup group;
  final String versionStr;
  final GameVersion keep;
  final List<GameVersion> others;
  const DuplicateSet(this.group, this.versionStr, this.keep, this.others);

  String get title => group.effectiveTitle;
}

/// Index of the library folder holding [path]; folders not in the list sort last.
int _rank(String path, List<String> libraryDirs) {
  for (final (i, d) in libraryDirs.indexed) {
    if (p.equals(d, path) || p.isWithin(d, path)) return i;
  }
  return libraryDirs.length;
}

List<DuplicateSet> findDuplicates(List<GameGroup> groups, List<String> libraryDirs) {
  final out = <DuplicateSet>[];
  for (final g in groups) {
    final byVersion = <String, List<GameVersion>>{};
    for (final v in g.versions) {
      if (v.versionStr.isEmpty) continue;
      byVersion.putIfAbsent(v.versionStr.toLowerCase(), () => []).add(v);
    }
    for (final copies in byVersion.values) {
      if (copies.length < 2) continue;
      final sorted = [...copies]
        ..sort((a, b) => _rank(a.folderPath.path, libraryDirs).compareTo(_rank(b.folderPath.path, libraryDirs)));
      out.add(DuplicateSet(g, sorted.first.versionStr, sorted.first, sorted.skip(1).toList()));
    }
  }
  out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return out;
}

/// One copy to remove, with what the merge would do to it.
class CopyPlan {
  final String folder;
  final int bytes;
  final int files;

  /// Saves that move into the kept copy (not there yet).
  final List<String> savesToMove;

  /// Saves both copies have: the newer one is kept (true = this copy's).
  final Map<String, bool> conflicts;
  final DriveInfo drive;

  const CopyPlan(this.folder, this.bytes, this.files, this.savesToMove, this.conflicts, this.drive);
}

class MergePlan {
  final DuplicateSet set;
  final List<CopyPlan> copies;
  const MergePlan(this.set, this.copies);
}

/// Works out what merging [set] would do: sizes, file counts and saves. Reads
/// only; walks each copy, so it can take a moment on a slow drive.
Future<MergePlan> planMerge(DuplicateSet set) async {
  final keep = set.keep.folderPath.path;
  final copies = <CopyPlan>[];
  for (final other in set.others) {
    final folder = other.folderPath.path;
    final (bytes, files, move, conflicts) = await Isolate.run(() => _inspect(folder, keep));
    copies.add(CopyPlan(folder, bytes, files, move, conflicts, await driveInfoFor(folder)));
  }
  return MergePlan(set, copies);
}

(int, int, List<String>, Map<String, bool>) _inspect(String folder, String keep) {
  var bytes = 0, files = 0;
  try {
    for (final e in Directory(folder).listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        files++;
        try {
          bytes += e.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  final move = <String>[];
  final conflicts = <String, bool>{};
  final from = Directory(p.join(folder, 'game', 'saves'));
  if (from.existsSync()) {
    for (final f in from.listSync().whereType<File>()) {
      final name = p.basename(f.path);
      final there = File(p.join(keep, 'game', 'saves', name));
      if (!there.existsSync()) {
        move.add(name);
      } else {
        conflicts[name] = f.lastModifiedSync().isAfter(there.lastModifiedSync());
      }
    }
  }
  return (bytes, files, move, conflicts);
}

/// Merges per [plan]: copies saves into the kept copy (the newer file wins a
/// conflict, with its time kept), then removes each other copy, to the Trash
/// when [toTrash] and that copy's drive allows it, else permanently.
Future<void> runMerge(MergePlan plan, {required bool toTrash}) async {
  final keepSaves = Directory(p.join(plan.set.keep.folderPath.path, 'game', 'saves'));
  for (final c in plan.copies) {
    final names = [...c.savesToMove, ...c.conflicts.entries.where((e) => e.value).map((e) => e.key)];
    if (names.isNotEmpty) keepSaves.createSync(recursive: true);
    for (final name in names) {
      final src = File(p.join(c.folder, 'game', 'saves', name));
      final dest = p.join(keepSaves.path, name);
      final time = src.lastModifiedSync();
      src.copySync(dest);
      File(dest).setLastModifiedSync(time);
    }
    if (toTrash && c.drive.trashSafe) {
      await moveToTrash(c.folder);
    } else {
      await Directory(c.folder).delete(recursive: true);
    }
  }
}
