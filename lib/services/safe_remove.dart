import 'dart:io';

import 'package:path/path.dart' as p;

/// Checks run before the app removes a game folder, so a merge or an update
/// can never delete the only copy or leave half a folder behind.

/// [path] after following junctions, links and mapped drives, so a mapped
/// drive and its network path compare equal.
String _identity(String path) {
  var s = path;
  try {
    s = Directory(path).resolveSymbolicLinksSync();
  } catch (_) {}
  if (s.startsWith(r'\\?\UNC\')) s = r'\\' + s.substring(8);
  if (s.startsWith(r'\\?\')) s = s.substring(4);
  return p.normalize(s).toLowerCase();
}

/// True when [a] and [b] are the same folder, even when reached by two
/// different paths. When it can't tell, it says they are the same, so the
/// caller removes nothing.
bool sameFolder(String a, String b) {
  if (p.equals(a, b) || _identity(a) == _identity(b)) return true;
  // A file written through one path that shows up through the other means
  // they're the same folder (a share reached by two server names, say).
  final name = '.vnpf-same-check-$pid-${DateTime.now().microsecondsSinceEpoch}';
  final probe = File(p.join(b, name));
  try {
    probe.writeAsStringSync('');
  } catch (_) {
    return true;
  }
  try {
    return File(p.join(a, name)).existsSync();
  } catch (_) {
    return true;
  } finally {
    try {
      probe.deleteSync();
    } catch (_) {}
  }
}

/// Throws when a file in [folder] is open, a game that's running for
/// example. Windows refuses to rename a folder with an open file in it, so a
/// rename and back tells before anything is deleted.
void checkNotInUse(String folder) {
  final dir = Directory(folder);
  final temp = '$folder.vnpf-check-$pid';
  try {
    dir.renameSync(temp);
  } on FileSystemException {
    throw FileSystemException('A file in it is in use. Close the game and try again.', folder);
  }
  // Put it back. Antivirus or Explorer can hold the folder for a moment, so
  // try a few times before giving up, and then say where it is.
  for (var attempt = 0;; attempt++) {
    try {
      Directory(temp).renameSync(folder);
      return;
    } on FileSystemException {
      if (attempt >= 9) {
        throw FileSystemException(
            'The folder was left as ${p.basename(temp)}. Rename it back to ${p.basename(folder)}.', temp);
      }
      sleep(const Duration(milliseconds: 200));
    }
  }
}
