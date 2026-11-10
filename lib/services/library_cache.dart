import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the last full scan found each game, with its engine and save info
/// (#13). A normal start reads only these games, then searches for anything
/// new or moved in the background. Written only after a complete scan, in one
/// go, so a crash mid-scan leaves the previous cache intact.
class LibraryCache {
  LibraryCache._();

  /// For tests: where the cache goes instead of AppData.
  static File? fileForTesting;

  static File get _file =>
      fileForTesting ?? File(p.join(Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'library_cache.json'));

  static const _version = 1;

  /// Game folder path → entry. Empty when there's no cache or it can't be read.
  static Map<String, dynamic> load() {
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      if (json['version'] != _version) return {};
      return Map<String, dynamic>.from(json['games'] as Map);
    } catch (_) {
      return {};
    }
  }

  static void save(Map<String, dynamic> games) {
    try {
      final file = _file;
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.new');
      tmp.writeAsStringSync(jsonEncode({'version': _version, 'games': games}));
      tmp.renameSync(file.path);
    } catch (_) {}
  }
}
