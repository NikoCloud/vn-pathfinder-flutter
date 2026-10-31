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

// Link labels forum posts run into a developer's name ("Quonix Patreon").
const _developerLinks = r'patreon|subscribe ?star|itch(?:\.io)?|steam|discord|twitter|'
    r'website|homepage|blog|boosty|ko-?fi|gumroad|linktree|fanbox|pixiv|facebook|'
    r'instagram|youtube|reddit|tumblr|deviantart|bluesky|nutaku|dlsite|fantia|tipeee|paypal';
final _linkSeparator = RegExp(r'\s[-–—|/]\s');
final _onlyLink = RegExp('^(?:$_developerLinks)\$', caseSensitive: false);
final _trailingLink =
    RegExp('[\\s,:;|/(\\[-]+(?:$_developerLinks)[)\\]]?\$', caseSensitive: false);
final _webAddress = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);

/// A developer's name without the links and page text scraped along with it:
/// "Quonix Patreon - Discord" → "Quonix". Also used on saved metadata, so
/// names fetched before this existed are cleaned without fetching again.
String cleanDeveloperName(String raw) {
  final firstLine = raw.trim().split(RegExp(r'[\r\n\t]')).first;
  final line = firstLine.replaceAll(_webAddress, ' ').trim();
  final parts = line.split(_linkSeparator).map((s) => s.trim()).where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '';
  var name = parts.firstWhere((s) => !_onlyLink.hasMatch(s), orElse: () => parts.first);
  while (true) {
    final shorter = name.replaceFirst(_trailingLink, '').trim();
    if (shorter == name || shorter.isEmpty) break;
    name = shorter;
  }
  name = name.replaceAll(RegExp(r'[\s\-|–—:,]+$'), '').trim();
  // "website: https://…" is a link with its label, not a name.
  return _webAddress.hasMatch(firstLine) && _onlyLink.hasMatch(name) ? '' : name;
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
