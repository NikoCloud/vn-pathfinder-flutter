import 'dart:io';

import 'package:path/path.dart' as p;

/// A development build, made with `--dart-define=VNPF_DEV=true`. It keeps its
/// own settings and library data so it can run beside a normal copy, and it
/// never offers app updates.
const isDevBuild = bool.fromEnvironment('VNPF_DEV');

/// The app's own data folder: `%APPDATA%\VN Pathfinder`, or
/// `%APPDATA%\VN Pathfinder Dev` for a development build. Ren'Py's folder and
/// the game folders themselves are shared either way.
String appDataPath([String? child, String? child2]) {
  final root = p.join(Platform.environment['APPDATA'] ?? '', isDevBuild ? 'VN Pathfinder Dev' : 'VN Pathfinder');
  return p.join(root, child ?? '', child2 ?? '');
}

/// First start of a development build: copy the normal copy's settings and
/// library data across, so it opens on the same library. Images and logs are
/// left behind; they're fetched or written again as needed. Never runs again
/// once the folder exists, and never writes to the normal copy's folder.
void seedDevData() {
  if (!isDevBuild) return;
  final dev = Directory(appDataPath());
  if (dev.existsSync()) return;
  final normal = Directory(p.join(Platform.environment['APPDATA'] ?? '', 'VN Pathfinder'));
  dev.createSync(recursive: true);
  if (!normal.existsSync()) return;
  for (final f in normal.listSync().whereType<File>()) {
    if (p.extension(f.path).toLowerCase() != '.json') continue;
    try {
      f.copySync(p.join(dev.path, p.basename(f.path)));
    } catch (_) {
      // A file another program holds: the dev build starts without it.
    }
  }
}
