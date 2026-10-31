/// A feed body as plain text. Forum RSS bodies are HTML; F95Zone's are already
/// plain. The [cover] line is read separately (see [RawFeedItem.coverUrl]), and
/// relative times ("NEW 8 hours ago", "Updated: 5 hrs") are dropped because
/// they go stale in the cache.
String feedPlainText(String body) => body
    .replaceAll(RegExp(r'<br\s*/?>\s*', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'&#0?39;'), "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'^\[cover\]\s*\S+\s*$', multiLine: true), '')
    .replaceAll(RegExp(r'^(?:Updated|Kind|Posted):.*$', multiLine: true), '')
    .replaceAll(RegExp(r'^[ \t]+|[ \t]+$', multiLine: true), '')
    .replaceAll(RegExp(r'^(?:new|updated?|post edited)\b.*\bago$', multiLine: true, caseSensitive: false), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// The version a feed item announces ("Version: …" line in its body, which
/// is HTML on some forums).
String? extractFeedVersion(RawFeedItem item) {
  final m = RegExp(r'^Version:\s*(.+)$', multiLine: true).firstMatch(item.plainBody);
  final version = m?.group(1)?.trim();
  return version == null || version.isEmpty ? null : version;
}

/// [extractFeedVersion] in one spelling, for comparing. Empty when there's none.
String feedVersionKey(RawFeedItem item) =>
    (extractFeedVersion(item) ?? '').toLowerCase().replaceFirst(RegExp(r'^v\.?'), '').trim();

/// A game's title as one comparable key: lowercase, no version numbers, no
/// punctuation. Used across sites and for Watch and Mute.
String feedTitleKey(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
    .replaceAll(RegExp(r"v?\d+[\d.]*[a-z]?(\s*(alpha|beta|rc)\s*\d*)?", caseSensitive: false), '')
    .replaceAll(RegExp(r"[^a-z0-9\s]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

enum FeedKind { newGame, update, complete }

/// A single item from any site, with the facts every site's list provides
/// written as "Key: value" lines in [rawBody].
class RawFeedItem {
  final String id;          // unique key: '{source}::{url}'
  final String source;      // 'f95zone' | 'lewdcorner' | 'azc'
  final String sourceLabel; // human-readable e.g. 'F95Zone', 'LewdCorner'
  final String title;       // RSS item title (raw, may still contain XenForo prefix tags)
  final String rawBody;     // raw description/content as received — may be HTML or plain text
  final String url;         // canonical link to the thread/message
  final DateTime? publishedAt;
  final String author;      // RSS dc:creator or the site's developer field
  final String channelName; // RSS: forum feed name

  RawFeedItem({
    required this.id,
    required this.source,
    required this.sourceLabel,
    required this.title,
    required this.rawBody,
    required this.url,
    this.publishedAt,
    this.author = '',
    this.channelName = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'source_label': sourceLabel,
    'title': title,
    'raw_body': rawBody,
    'url': url,
    'published_at': publishedAt?.toIso8601String(),
    'author': author,
    'channel_name': channelName,
  };

  factory RawFeedItem.fromJson(Map<String, dynamic> j) => RawFeedItem(
    id: j['id'] as String? ?? '',
    source: j['source'] as String? ?? '',
    sourceLabel: j['source_label'] as String? ?? '',
    title: j['title'] as String? ?? '',
    rawBody: j['raw_body'] as String? ?? '',
    url: j['url'] as String? ?? '',
    publishedAt: j['published_at'] != null
        ? DateTime.tryParse(j['published_at'] as String)
        : null,
    author: j['author'] as String? ?? '',
    channelName: j['channel_name'] as String? ?? '',
  );

  /// This row with the date the release rule gave it. [isNew] marks it as a
  /// new game, for a site that stops saying so after the first edit.
  RawFeedItem settled(DateTime? at, {bool isNew = false}) => RawFeedItem(
    id: id,
    source: source,
    sourceLabel: sourceLabel,
    title: title,
    rawBody: isNew && !isNewGame ? '$rawBody\nKind: new' : rawBody,
    url: url,
    publishedAt: at,
    author: author,
    channelName: channelName,
  );

  /// [rawBody] as text.
  late final String plainBody = feedPlainText(rawBody);

  /// From a site's Latest Updates list. Its public forum feed is the other
  /// source, where the date is a thread's latest post, not a release.
  bool get fromSiteList => channelName.startsWith('Latest Updates');

  String _fact(String key) =>
      RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(plainBody)?.group(1)?.trim() ?? '';

  /// Who made the game, or who posted it when a site doesn't say. Rows saved
  /// by older builds can still hold RSS's "invalid@example.com (Name)".
  late final String developer = () {
    final fact = _fact('Developer');
    if (fact.isNotEmpty) return fact;
    return RegExp(r'^\S+@\S+\s*\((.+)\)$').firstMatch(author.trim())?.group(1) ?? author;
  }();

  late final List<String> tags = _fact('Tags').split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  /// Out of 5; 0 means none.
  late final double rating = double.tryParse(_fact('Rating').split(' ').first) ?? 0;

  /// The post text, without the fact lines.
  late final String overview = plainBody
      .replaceAll(RegExp(r'^(?:Version|Developer|Tags|Rating|Platforms):.*$', multiLine: true), '')
      .trim();

  /// The game's art: a [cover] line from a site's list, or the first image in
  /// a forum post.
  late final String coverUrl = () {
    final line = RegExp(r'^\[cover\]\s*(\S+)\s*$', multiLine: true).firstMatch(rawBody)?.group(1);
    if (line != null) return line;
    for (final m in RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).allMatches(rawBody)) {
      final src = m.group(1)!;
      if (src.startsWith('http') && !src.contains('/smilies/') && !src.contains('/emoji/')) return src;
    }
    return '';
  }();

  /// When the thread went up, for a site whose list says.
  late final DateTime? postedAt = () {
    final seconds = RegExp(r'^Posted:\s*(\d+)\s*$', multiLine: true).firstMatch(rawBody)?.group(1);
    return seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(seconds) * 1000, isUtc: true);
  }();

  /// The site marks this as a new game.
  late final bool isNewGame = RegExp(r'^Kind:\s*new\b', multiLine: true).hasMatch(rawBody);

  /// The site marks this as finished, or its version says so.
  late final bool isComplete = () {
    if (RegExp(r'^Kind:\s*complete\b', multiLine: true).hasMatch(rawBody)) return true;
    final version = _fact('Version').toLowerCase();
    return version.contains('final') || version.contains('complete');
  }();

  /// The one label a card shows. A game can be new and complete at once, and
  /// sits on both shelves; finished is the more useful thing to say.
  FeedKind get kind => isComplete
      ? FeedKind.complete
      : isNewGame
          ? FeedKind.newGame
          : FeedKind.update;

  /// A short human-readable timestamp string.
  String get timeAgo {
    final now = DateTime.now();
    final dt = publishedAt;
    if (dt == null) return '';
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
