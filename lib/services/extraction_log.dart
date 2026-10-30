import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Where each archive was extracted to. Extracted folders are named from the
/// best of the archive's and its inner folder's names (planExtractFolderName),
/// not the archive's own name, so the Archive tab looks them up here.
/// Persisted at %APPDATA%\VN Pathfinder\extractions.json as
/// { archivePath: extractedFolderPath }.
class ExtractionLog {
  static Map<String, String>? _cache;

  static File get _file => File(p.join(
      Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'extractions.json'));

  static Map<String, String> get _entries {
    if (_cache != null) return _cache!;
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _cache = json.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static String? folderFor(String archivePath) => _entries[archivePath];

  static void record(String archivePath, String folderPath) {
    _entries[archivePath] = folderPath;
    _save();
  }

  static void forget(String archivePath) {
    if (_entries.remove(archivePath) != null) _save();
  }

  static void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_entries));
    } catch (e) {
      debugPrint('ExtractionLog save failed: $e');
    }
  }
}
