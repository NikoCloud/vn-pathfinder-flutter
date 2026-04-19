/// A single raw item from any feed source.
/// Intentionally unprocessed — this is the "see what the data looks like"
/// phase. Normalization is a future milestone (see ROADMAP / GitHub issues).
class RawFeedItem {
  final String id;          // unique key: '{source}::{url or discord message id}'
  final String source;      // 'f95zone' | 'lewdcorner' | 'discord'
  final String sourceLabel; // human-readable e.g. 'F95Zone', 'LewdCorner', or discord server name
  final String title;       // RSS item title (raw, may still contain XenForo prefix tags)
  final String rawBody;     // raw description/content as received — may be HTML or plain text
  final String url;         // canonical link to the thread/message
  final DateTime? publishedAt;
  final String author;      // RSS dc:creator or Discord username
  final String channelName; // Discord: #channel-name; RSS: forum feed name

  const RawFeedItem({
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
