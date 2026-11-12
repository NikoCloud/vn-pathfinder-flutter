import '../utils/formatters.dart';
import 'metadata_service.dart';

/// How Fetch Metadata combines sources (#43): tags from every ticked source
/// without duplicates, creator links chosen one by one, and the same-game
/// check that decides which sources start ticked. Fetching several games at
/// once relies on the defaults alone, so they only ever lean towards saving
/// less.

// ── Tags ─────────────────────────────────────────────────────────────────────

final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// The key two tags are compared by: letters and digits in any script, lower
/// case, everything else dropped. "Male Protagonist", "male-protagonist" and
/// "male_protagonist" are one tag; a Japanese or accented tag keeps its
/// letters. Never shown or saved.
String tagKey(String tag) => tag.toLowerCase().replaceAll(_notLetterOrDigit, '');

/// A tag kept after combining, with the sources that had it.
typedef MergedTag = ({String tag, List<String> sources});

/// Every tag of [bySource], highest-priority source first. One tag per key,
/// spelled as the first source that has it spells it; tags with an empty key
/// (symbols only) are dropped.
List<MergedTag> mergeTags(List<(String, List<String>)> bySource) {
  final order = <String>[];
  final spelling = <String, String>{};
  final sources = <String, List<String>>{};
  for (final (source, tags) in bySource) {
    for (final raw in tags) {
      final tag = raw.trim();
      final key = tagKey(tag);
      if (key.isEmpty) continue;
      if (!spelling.containsKey(key)) {
        spelling[key] = tag;
        order.add(key);
      }
      final list = sources.putIfAbsent(key, () => []);
      if (!list.contains(source)) list.add(source);
    }
  }
  return [for (final k in order) (tag: spelling[k]!, sources: sources[k]!)];
}

// ── Creator links ────────────────────────────────────────────────────────────

/// One creator link as the window shows it: its platform, address, the
/// source that found it and where.
class LinkRow {
  final String source;
  final String platform;
  final String url;
  final LinkWhere where;
  const LinkRow({required this.source, required this.platform, required this.url, required this.where});

  /// Stable across rebuilds, for remembering the user's tick.
  String get id => '$source|$url';
}

/// The rows for one source's links. A recognised support platform only; the
/// same address twice keeps the more trusted place it was found.
List<LinkRow> linkRowsFor(String source, List<FoundLink> links) => [
      for (final l in foundLinksFrom(links))
        LinkRow(source: source, platform: supportLinksFromUrls([l.url]).first.label, url: l.url, where: l.where),
    ];

/// The links to save: the ticked ones, one per platform, the first row
/// ([rows] is in priority order) winning a platform.
List<SupportLink> chosenLinks(List<LinkRow> rows, bool Function(LinkRow) ticked) {
  final out = <String, String>{};
  for (final r in rows) {
    if (ticked(r)) out.putIfAbsent(r.platform, () => r.url);
  }
  return [for (final e in out.entries) (label: e.key, url: e.value)];
}

/// Whether a link row starts ticked: found where the developer is named, by a
/// source that passed the same-game check.
bool linkStartsTicked(LinkRow row, {required bool sourceMatches}) => sourceMatches && row.where.trusted;

// ── The same-game check ──────────────────────────────────────────────────────

String _loose(String s) => s.toLowerCase().replaceAll(_notLetterOrDigit, '');

/// Whether [r] is the game being fetched: its title is the game's or what the
/// user searched for, and, when the game's developer is known, the developer
/// matches too ("Some Studio" and "Some Studio Productions" count).
bool matchesLocalGame(MetadataResult r, {required String title, String query = '', String developer = ''}) {
  final t = _loose(r.title);
  if (t.isEmpty || (t != _loose(title) && t != _loose(query))) return false;
  final mine = _loose(developer);
  if (mine.isEmpty) return true;
  final theirs = _loose(r.developer);
  return theirs.isNotEmpty && (theirs.startsWith(mine) || mine.startsWith(theirs));
}

/// The result the other sources are checked against: the first of [inOrder]
/// (highest priority first) that is the game being fetched, or null when none
/// clearly is. With no anchor, nothing starts ticked.
MetadataResult? anchorResult(List<MetadataResult> inOrder,
    {required String title, String query = '', String developer = ''}) {
  for (final r in inOrder) {
    if (matchesLocalGame(r, title: title, query: query, developer: developer)) return r;
  }
  return null;
}

/// Whether [r] starts ticked for tags and links: it is the anchor, or the same
/// game as the anchor on title and developer ([MetadataService.sameGame]).
bool passesSameGame(MetadataResult r, MetadataResult? anchor) =>
    anchor != null && (identical(r, anchor) || MetadataService.sameGame(anchor, r));
