import 'dart:io';

String fmtTime(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${m}m';
}

String fmtDate(String iso) {
  if (iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso);
    final delta = DateTime.now().difference(dt);
    if (delta.inDays == 0) return 'Today';
    if (delta.inDays == 1) return 'Yesterday';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    if (delta.inDays < 30) return '${delta.inDays ~/ 7}w ago';
    return '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

/// The one display form for folder-derived version strings. Numbers get a
/// single lowercase "v" ("0.12.7", "V0.2", "v.0.14.0" → "v0.12.7", "v0.2",
/// "v0.14.0"); word versions read as words ("Chapter-1" → "Chapter 1",
/// "Episode_10" → "Episode 10", "Final"); empty → "Unknown".
String fmtVersion(String version) {
  final s = version.trim();
  if (s.isEmpty) return 'Unknown';
  final spaced = s.replaceAll(RegExp(r'[-_]+'), ' ');
  final numeric = RegExp(r'^v\.?(?=\d)', caseSensitive: false).firstMatch(spaced);
  if (numeric != null) return 'v${spaced.substring(numeric.end)}';
  if (RegExp(r'^\d').hasMatch(spaced)) return 'v$spaced';
  return spaced;
}

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String fmtDirSize(Directory dir) {
  try {
    int total = 0;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      total += f.lengthSync();
    }
    return fmtBytes(total);
  } catch (_) {
    return '—';
  }
}

String _monthName(int m) => const [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][m];
