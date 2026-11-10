import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/library_cache.dart';

/// Runs before every test file: scans in tests write their library cache to a
/// temporary file, never to the real %APPDATA%\VN Pathfinder.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final tmp = Directory.systemTemp.createTempSync('vnp_test_cache');
  LibraryCache.fileForTesting = File(p.join(tmp.path, 'library_cache.json'));
  await testMain();
}
