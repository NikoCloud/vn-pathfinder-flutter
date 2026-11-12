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
    r'instagram|youtube|reddit|tumblr|deviantart|bluesky|nutaku|dlsite|fantia|tipeee|paypal|'
    r'unifans|buy ?me ?a ?coffee|bmc|telegram|ci-?en|afdian|liberapay|official ?(?:website|site)';
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

/// A creator-support link recognized from its web address.
typedef SupportLink = ({String label, String url});

/// Known creator-support platforms, matched by host. Each platform appears at
/// most once, keeping a creator page over a single post when both are linked.
List<SupportLink> supportLinksFromUrls(Iterable<String> urls) {
  final byLabel = <String, String>{};
  for (final raw in urls) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[),.;\]>]+$'), '');
    final normalized = cleaned.startsWith('//') ? 'https:$cleaned' : cleaned;
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) continue;
    final path = uri.path.replaceAll(RegExp(r'^/+|/+$'), '');
    final label = _supportPlatformLabel(uri.host.toLowerCase(), path.toLowerCase());
    if (label == null) continue;
    final existing = byLabel[label];
    if (existing == null || (_isSinglePostUrl(existing) && !_isSinglePostUrl(normalized))) {
      byLabel[label] = normalized;
    }
  }
  return [
    for (final e in byLabel.entries) (label: e.key, url: e.value),
  ];
}

bool _isSinglePostUrl(String url) =>
    RegExp(r'/(?:posts?|updates?|status|notes?|devlog)(?:/|$)', caseSensitive: false).hasMatch(url);

String? _supportPlatformLabel(String host, String path) {
  final firstSeg = path.isEmpty ? '' : path.split('/').first;
  if (host == 'patreon.com' || host.endsWith('.patreon.com')) {
    if (path.isEmpty) return null;
    if (const {'login', 'home', 'search', 'about', 'apps', 'policy', 'terms'}.contains(firstSeg)) {
      return null;
    }
    return 'Patreon';
  }
  if (host == 'subscribestar.adult' ||
      host.endsWith('.subscribestar.adult') ||
      host == 'subscribestar.com' ||
      host.endsWith('.subscribestar.com')) {
    return path.isEmpty ? null : 'SubscribeStar';
  }
  if (host == 'unifans.io' || host.endsWith('.unifans.io')) {
    return path.isEmpty ? null : 'UniFans';
  }
  if (host == 'itch.io' || host.endsWith('.itch.io')) {
    final isCreatorSubdomain = host.endsWith('.itch.io') && host != 'www.itch.io';
    if (isCreatorSubdomain) return 'Itch.io';
    if (path.isEmpty) return null;
    if (const {'search', 'login', 'register', 'games', 'jams', 'board', 'docs', 'developers', 'press'}
        .contains(firstSeg)) {
      return null;
    }
    return 'Itch.io';
  }
  if (host == 'discord.gg' || host.endsWith('.discord.gg')) {
    return path.isEmpty ? null : 'Discord';
  }
  if (host == 'discord.com' ||
      host.endsWith('.discord.com') ||
      host == 'discordapp.com' ||
      host.endsWith('.discordapp.com')) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && (segments.first == 'invite' || segments.first == 'servers')) {
      return 'Discord';
    }
    return null;
  }
  if (host == 'buymeacoffee.com' || host.endsWith('.buymeacoffee.com')) {
    return path.isEmpty ? null : 'Buy Me a Coffee';
  }
  if (host == 'ko-fi.com' || host.endsWith('.ko-fi.com')) return path.isEmpty ? null : 'Ko-fi';
  if (host == 'boosty.to' || host.endsWith('.boosty.to')) return path.isEmpty ? null : 'Boosty';
  if (host == 'fanbox.cc' || host.endsWith('.fanbox.cc')) {
    final isCreatorSubdomain = host.endsWith('.fanbox.cc') && host != 'www.fanbox.cc';
    return (isCreatorSubdomain || path.isNotEmpty) ? 'Fanbox' : null;
  }
  if (host == 'gumroad.com' || host.endsWith('.gumroad.com')) {
    final isCreatorSubdomain = host.endsWith('.gumroad.com') && host != 'www.gumroad.com';
    return (isCreatorSubdomain || path.isNotEmpty) ? 'Gumroad' : null;
  }
  if (host == 'fantia.jp' || host.endsWith('.fantia.jp')) return path.isEmpty ? null : 'Fantia';
  if (host == 'tipeee.com' || host.endsWith('.tipeee.com')) return path.isEmpty ? null : 'Tipeee';
  if (host == 'paypal.me' || host.endsWith('.paypal.me')) return path.isEmpty ? null : 'PayPal';
  if (host == 'ci-en.dlsite.com' || host == 'ci-en.jp' || host.endsWith('.ci-en.jp')) {
    return path.isEmpty ? null : 'Ci-en';
  }
  if (host == 'afdian.net' ||
      host.endsWith('.afdian.net') ||
      host == 'afdian.com' ||
      host.endsWith('.afdian.com')) {
    return path.isEmpty ? null : 'Afdian';
  }
  if (host == 'liberapay.com' || host.endsWith('.liberapay.com')) {
    return path.isEmpty ? null : 'Liberapay';
  }
  return null;
}

/// Another game by the same developer linked in a forum thread.
typedef OtherGameLink = ({String title, String url});

/// Valid forum-thread links from an "Other Games" field or line, deduplicated
/// by title and excluding [excludeTitle]. Generic non-thread URLs (like search
/// pages) are ignored.
List<OtherGameLink> otherGameLinksFrom(
  Iterable<OtherGameLink> candidates, {
  String excludeTitle = '',
}) {
  final excludedKey = _otherGameKey(excludeTitle);
  final byKey = <String, OtherGameLink>{};

  for (final item in candidates) {
    final cleanedUrl = item.url.trim().replaceAll(RegExp(r'[),.;\]>]+$'), '');
    final normalizedUrl = cleanedUrl.startsWith('//') ? 'https:$cleanedUrl' : cleanedUrl;
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      continue;
    }
    final host = uri.host.toLowerCase();
    final isSupportedForum = host == 'f95zone.to' ||
        host.endsWith('.f95zone.to') ||
        host == 'lewdcorner.com' ||
        host.endsWith('.lewdcorner.com') ||
        host == 'azkoselscorner.com' ||
        host.endsWith('.azkoselscorner.com');
    if (!isSupportedForum) continue;

    final fullPath = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'.toLowerCase();
    if (!fullPath.contains('threads/')) continue;

    var title = item.title
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'^[\s\-–—:|•]+|[\s\-–—:|•]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty ||
        title.toLowerCase().startsWith('http') ||
        const {'link', 'here', 'thread', 'game', 'other games'}.contains(title.toLowerCase())) {
      title = _titleFromThreadUrl(normalizedUrl);
    }
    final key = _otherGameKey(title);
    if (key.isEmpty || (excludedKey.isNotEmpty && key == excludedKey)) continue;
    byKey.putIfAbsent(key, () => (title: title, url: _canonicalThreadUrl(uri)));
  }

  return byKey.values.toList();
}

String _otherGameKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _canonicalThreadUrl(Uri uri) {
  final m = RegExp(r'^(.*?/threads/[^/?#]+/?)', caseSensitive: false).firstMatch(uri.path);
  if (m != null) {
    final cleanPath = m.group(1)!.endsWith('/') ? m.group(1)! : '${m.group(1)!}/';
    return Uri(scheme: uri.scheme, host: uri.host, path: cleanPath).toString();
  }
  return uri.toString();
}

String _titleFromThreadUrl(String url) {
  final m = RegExp(r'threads/([a-z0-9-]+?)(?:-(?:v|ch|ep|part|season|final)-?[0-9a-z.-]+)?\.\d+',
          caseSensitive: false)
      .firstMatch(url);
  final slug = m?.group(1) ?? '';
  if (slug.isEmpty) return '';
  return slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
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
