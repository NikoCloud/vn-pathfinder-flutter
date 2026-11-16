import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/library_cache.dart';
import 'package:vn_pathfinder/utils/app_paths.dart';

/// Runs before every test file: the app's data folder (library cache, version
/// records and the rest) is a temporary one, never the real
/// %APPDATA%\VN Pathfinder.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final tmp = Directory.systemTemp.createTempSync('vnp_test_cache');
  LibraryCache.fileForTesting = File(p.join(tmp.path, 'library_cache.json'));
  appDataRootForTesting = tmp.path;
  await testMain();
}
