import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';
import '../providers/library_provider.dart';
import 'scanner_service.dart';

/// The picture Ren'Py stores in a save, for the "pick up where you left off"
/// shelf. Saves can show anything, so these go through GameArt like all art,
/// and Discreet blurs them.
class SaveShot {
  final String image;
  final DateTime at;
  const SaveShot(this.image, this.at);
}

/// The newest .save file in [folders], with when it was written.
(String, DateTime)? newestSave(Iterable<String> folders) {
  (String, DateTime)? best;
  for (final folder in folders) {
    final dir = Directory(folder);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.save')) continue;
      final at = entity.lastModifiedSync();
      if (best == null || at.isAfter(best.$2)) best = (entity.path, at);
    }
  }
  return best;
}

Directory get _cache =>
    Directory(p.join(Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'save_shots'));

/// Pulls the screenshot out of a save, once per save file version.
Future<String?> _extract((String save, int stamp, String cacheDir) job) async {
  final (save, stamp, cacheDir) = job;
  final name = sha1.convert(utf8.encode('$save@$stamp')).toString();
  final out = File(p.join(cacheDir, '$name.png'));
  if (out.existsSync()) return out.path;
  final bytes = readZipEntry(File(save), 'screenshot.png');
  if (bytes == null || bytes.isEmpty) return null;
  await out.parent.create(recursive: true);
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}

Future<SaveShot?> saveShotFor(GameGroup group) async {
  final folders = [
    for (final v in group.versions.reversed) ...[v.localSaveDir.path, ?v.appdataSaveDir?.path],
  ];
  final newest = await compute(newestSave, folders);
  if (newest == null) return null;
  try {
    final image = await compute(_extract, (newest.$1, newest.$2.millisecondsSinceEpoch, _cache.path));
    return image == null ? null : SaveShot(image, newest.$2);
  } catch (e) {
    debugPrint('Save preview failed: $e');
    return null;
  }
}

final saveShotProvider = FutureProvider.family<SaveShot?, String>((ref, baseKey) async {
  final group = ref.watch(libraryGroupsProvider).where((g) => g.baseKey == baseKey).firstOrNull;
  return group == null ? null : saveShotFor(group);
});
