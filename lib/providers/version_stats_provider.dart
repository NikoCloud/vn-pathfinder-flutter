import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/game_group.dart';
import '../models/version_stats.dart';
import '../services/game_detect.dart';
import '../services/renpy_local.dart';
import '../models/game_status.dart' show isClearlyNewer;
import 'library_provider.dart';

/// Folders being counted right now, so a page shown twice doesn't count twice.
final _counting = <String>{};

/// Counts what each installed Ren'Py version of [g] holds (#44), in the
/// background, for versions never counted or whose folder changed since.
/// The result is kept with the user's data, so it outlives the folder.
Future<void> countVersions(UserDataNotifier ud, GameGroup g) async {
  for (final v in g.versions) {
    if (v.engine != null && v.engine != GameEngine.renpy) continue;
    final path = v.folderPath.path;
    if (_counting.contains(path)) continue;
    final known = ud.statsFor(g.baseKey, v.versionStr);
    _counting.add(path);
    try {
      final signature = await compute(_signature, path);
      if (known != null && known.signature == signature) continue;
      final stats = await compute(_count, path);
      if (stats != null) ud.recordVersionStats(g.baseKey, v.versionStr, stats);
    } catch (e) {
      debugPrint('Counting ${v.folderName} failed: $e');
    } finally {
      _counting.remove(path);
    }
  }
}

// Top-level, so only the path is sent to the background isolate.
String _signature(String path) => versionSignature(Directory(path));
VersionStats? _count(String path) => countRenpyVersion(Directory(path));

/// A game's counted versions, oldest first: by when each was built, then by
/// version number where the two compare, then by when they were counted.
List<(String, VersionStats)> statsHistory(Map<String, VersionStats>? byVersion) {
  final list = [for (final e in (byVersion ?? const <String, VersionStats>{}).entries) (e.key, e.value)];
  list.sort((a, b) {
    final x = a.$2.builtAt, y = b.$2.builtAt;
    if (x != null && y != null && x != y) return x.compareTo(y);
    if (isClearlyNewer(a.$1, b.$1)) return 1;
    if (isClearlyNewer(b.$1, a.$1)) return -1;
    return a.$2.countedAt.compareTo(b.$2.countedAt);
  });
  return list;
}
