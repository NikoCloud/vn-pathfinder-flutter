import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';

/// A game's saved images in .vnpf: one cover.* and numbered screenshot_N.*.
/// Order comes from the numbers, so reordering means renaming.
class GalleryService {
  /// The .vnpf folder that holds [g]'s images: the newest version with any,
  /// else the latest version's.
  static Directory folderFor(GameGroup g) {
    for (final v in g.versions.reversed) {
      final dir = Directory(p.join(v.folderPath.path, '.vnpf'));
      if (dir.existsSync() && (cover(dir) != null || screenshots(dir).isNotEmpty)) return dir;
    }
    return Directory(p.join(g.latestVersion!.folderPath.path, '.vnpf'));
  }

  static File? cover(Directory vnpf) {
    if (!vnpf.existsSync()) return null;
    for (final f in vnpf.listSync().whereType<File>()) {
      if (p.basename(f.path).toLowerCase().startsWith('cover.')) return f;
    }
    return null;
  }

  /// Screenshots in display order: screenshot_2 before screenshot_10.
  static List<File> screenshots(Directory vnpf) {
    if (!vnpf.existsSync()) return [];
    return vnpf
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('screenshot_'))
        .toList()
      ..sort((a, b) => screenshotNumber(a).compareTo(screenshotNumber(b)));
  }

  static int screenshotNumber(File f) =>
      int.tryParse(RegExp(r'screenshot_(\d+)').firstMatch(p.basename(f.path))?.group(1) ?? '') ?? 1 << 30;

  /// Renumbers [ordered] so they display in that order.
  static void reorder(Directory vnpf, List<File> ordered) {
    final temporary = [
      for (final (i, f) in ordered.indexed)
        f.renameSync(p.join(vnpf.path, 'reorder_$i${p.extension(f.path)}')),
    ];
    for (final (i, f) in temporary.indexed) {
      f.renameSync(p.join(vnpf.path, 'screenshot_${i + 1}${p.extension(f.path)}'));
    }
  }

  /// Makes screenshot [image] the cover. The old cover takes its place in the
  /// screenshots, so nothing is lost.
  static void setCover(Directory vnpf, File image) {
    final old = cover(vnpf);
    final shots = screenshots(vnpf);
    final position = shots.indexWhere((f) => f.path == image.path);
    final parked = image.renameSync(p.join(vnpf.path, 'new_cover${p.extension(image.path)}'));
    File? demoted;
    if (old != null) {
      demoted = old.renameSync(p.join(vnpf.path, 'old_cover${p.extension(old.path)}'));
    }
    parked.renameSync(p.join(vnpf.path, 'cover${p.extension(parked.path)}'));

    final remaining = screenshots(vnpf);
    if (demoted != null) {
      remaining.insert(position < 0 ? remaining.length : position.clamp(0, remaining.length), demoted);
    }
    reorder(vnpf, remaining);
  }

  /// Deletes [image], and closes the gap it leaves in the numbering.
  static void remove(Directory vnpf, File image) {
    image.deleteSync();
    reorder(vnpf, screenshots(vnpf));
  }

  /// Copies [picked] into the gallery. Without a cover yet, the first one
  /// becomes the cover, as it did in 1.0.
  static void add(Directory vnpf, List<File> picked) {
    vnpf.createSync(recursive: true);
    final files = [...picked];
    if (cover(vnpf) == null && files.isNotEmpty) {
      final first = files.removeAt(0);
      first.copySync(p.join(vnpf.path, 'cover${p.extension(first.path).toLowerCase()}'));
    }
    final existing = screenshots(vnpf);
    var next = existing.isEmpty ? 1 : screenshotNumber(existing.last) + 1;
    for (final f in files) {
      f.copySync(p.join(vnpf.path, 'screenshot_${next++}${p.extension(f.path).toLowerCase()}'));
    }
  }
}
