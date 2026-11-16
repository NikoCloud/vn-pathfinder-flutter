import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/game_group.dart';
import '../models/game_status.dart' show isClearlyNewer;
import '../models/version_stats.dart';
import '../services/game_detect.dart';
import '../services/renpy_local.dart';
import '../services/version_records.dart';
import 'library_provider.dart';

/// Folders being counted right now, so a page shown twice doesn't count twice.
final _counting = <String>{};

/// Counts what each installed Ren'Py version of [g] holds (#44), in the
/// background, for versions never counted, whose folder changed since, or
/// that have no record to compare with yet. The counts are kept with the
/// user's data and the record in the app's data folder, so both outlive the
/// version's folder.
Future<void> countVersions(UserDataNotifier ud, GameGroup g) async {
  for (final v in g.versions) {
    if (v.engine != null && v.engine != GameEngine.renpy) continue;
    await countVersion(ud, g.baseKey, v.versionStr, v.folderPath.path);
  }
}

/// Counts one version folder unless its count and record are up to date.
Future<void> countVersion(UserDataNotifier ud, String baseKey, String version, String path) async {
  if (_counting.contains(path)) return;
  _counting.add(path);
  try {
    final known = ud.statsFor(baseKey, version);
    final record = recordPath(baseKey, version);
    if (known != null && File(record).existsSync() && known.signature == await compute(_signature, path)) return;
    final stats = await compute(_count, [path, record, version]);
    if (stats != null) ud.recordVersionStats(baseKey, version, stats);
  } catch (e) {
    debugPrint('Counting $path failed: $e');
  } finally {
    _counting.remove(path);
  }
}

// Top-level, so only plain values go to the background isolate.
String _signature(String path) => versionSignature(Directory(path));
VersionStats? _count(List<String> a) => countRenpyVersion(Directory(a[0]), recordPath: a[1], version: a[2]);

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

/// Compares two recorded versions in the background. Null when either has
/// no record.
Future<RecordDiff?> compareVersions(String baseKey, String before, String after) =>
    compute(_diff, [recordPath(baseKey, before), recordPath(baseKey, after)]);

RecordDiff? _diff(List<String> paths) {
  final a = VersionRecord.read(paths[0]), b = VersionRecord.read(paths[1]);
  return a == null || b == null ? null : diffRecords(a, b);
}

/// Everything earlier versions had that the newest one doesn't, in the
/// background. [versions] oldest first; versions without a record are skipped.
Future<({List<Gone<String>> media, List<Gone<RecordLine>> lines})> goneFromGame(String baseKey, List<String> versions) =>
    compute(_gone, [for (final v in versions) recordPath(baseKey, v)]);

({List<Gone<String>> media, List<Gone<RecordLine>> lines}) _gone(List<String> paths) =>
    goneSince([for (final path in paths) ?VersionRecord.read(path)]);
