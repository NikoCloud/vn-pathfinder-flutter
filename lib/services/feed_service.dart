import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/feed_item.dart';
import '../utils/formatters.dart';
import '../providers/settings_provider.dart';
import 'feed_history.dart';
import 'scraping_service.dart';

/// How a refresh went. The rows themselves arrive as each page is read.
/// [problems] says which sites need a look, by source key: 'public' means only
/// the logged-out feed answered, 'behind' means the site stopped answering
/// partway back, 'failed' means nothing did. [sites] says how far back each
/// site's list has now been read.
class FeedFetch {
  final problems = <String, String>{};
  final sites = <String, SiteCatchUp>{};
}

/// Fetches raw feed items from all configured sources.
///
/// F95Zone is fetched via the SAM JSON API (/sam/latest_alpha/latest_data.php)
/// which requires login cookies — routed through [ScrapingService].
///
/// LewdCorner's Latest Updates data needs a login, so it's also routed through
/// [ScrapingService]; logged out, the public forum feeds stand in.
class FeedService {
  /// The wait between opening one thread and the next.
  static const threadGap = Duration(seconds: 2);

  /// F95Zone's prefix number for a finished game.
  static const _f95Completed = 18;

  static const _ua = 'VN-Pathfinder/2.0 (https://github.com/NikoCloud/vn-pathfinder-flutter)';

  /// JS returning a loaded document's source: the XML itself for an XML
  /// document, or the <pre> text when Chromium shows the response as text.
  static const _documentSourceJs = '''
(() => {
  const root = document.documentElement;
  if (root && root.nodeName.toLowerCase() !== 'html') {
    return new XMLSerializer().serializeToString(document);
  }
  const pre = document.querySelector('body > pre');
  return pre ? pre.textContent : (root ? root.outerHTML : '');
})()''';

  // ── F95Zone tag ID → name lookup (from latestUpdates.tags in page HTML) ──
  static const Map<int, String> _f95Tags = {
    7: 'adventure', 9: 'animated', 12: 'bdsm', 13: 'bestiality',
    14: 'blackmail', 17: 'cuckold', 18: 'dating sim', 20: 'drugs',
    25: 'exhibitionism', 27: 'fantasy', 28: 'female protagonist',
    30: 'incest', 36: 'lesbian', 38: 'male protagonist', 44: 'slave',
    45: 'rpg', 46: 'sandbox', 50: 'school setting', 51: 'sci-fi',
    52: 'sexual harassment', 53: 'simulator', 54: 'stripping',
    55: 'strategy', 56: 'superpowers', 57: 'teasing', 58: 'text based',
    60: 'turn based combat', 61: 'twin', 62: 'urination',
    63: 'vaginal sex', 64: 'virgin', 65: 'voyeurism',
    66: 'workplace romance', 75: 'milf', 76: 'multiple protagonists',
    78: 'oral sex', 80: 'pregnancy', 82: 'prostitution',
    83: 'rape', 84: 'real porn', 85: 'religion',
    88: 'romance', 89: 'school', 94: 'spanking',
    95: 'titfuck', 97: 'transformation', 98: 'trap',
    99: 'turn based', 100: 'urination', 103: 'corruption',
    107: '3dcg', 108: 'ahegao', 109: 'anal sex',
    110: 'asian protagonist', 111: 'big ass', 112: 'big tits',
    113: 'blind protagonist', 114: 'bukakke', 115: 'censored',
    116: 'cheating', 117: 'close combat', 118: 'cosplay',
    119: 'creampie', 120: 'dating', 121: 'dick rating',
    122: 'dilf', 123: 'dirty talk', 124: 'domination',
    125: 'dystopian setting', 126: 'elf', 127: 'female domination',
    128: 'fisting', 129: 'foot fetish', 130: 'big tits',
    131: 'gay', 132: 'goblin', 133: 'graphic violence',
    134: 'groping', 135: 'group sex', 136: 'handjob',
    137: 'harem', 138: 'horror', 139: 'humor',
    140: 'hypnosis', 141: 'interracial', 142: 'lactation',
    143: 'loli', 144: 'magic', 145: 'male domination',
    146: 'masturbation', 147: 'mini-game', 148: 'monster',
    149: 'monster girl', 150: 'multiple endings', 151: 'murder',
    152: 'music', 153: 'ntr', 154: 'old man',
    155: 'open world', 156: 'oral sex', 157: 'paranormal',
    158: 'patreon', 159: 'platformer', 160: 'point & click',
    161: 'possession', 162: 'post-apocalyptic', 163: 'puzzle',
    164: 'rape', 165: 'real life', 166: 'religion',
    167: 'romance', 168: 'school', 169: 'science fiction',
    170: 'school setting', 171: 'seduction', 172: 'side scroller',
    173: 'male protagonist', 174: 'small tits', 175: 'spanking',
    176: 'stealth', 177: 'succubus', 178: 'survival',
    179: 'swinging', 180: 'text based', 181: 'thriller',
    182: 'time stop', 183: 'titfuck', 184: 'torture',
    185: 'toys', 186: 'transformation', 187: 'twins',
    188: 'urination', 189: 'vampire', 190: 'virgin',
    191: 'voyeurism', 192: 'watersports', 193: 'witch',
    194: 'zombies', 237: 'oral sex', 254: 'harem',
    258: 'netorare', 259: 'romance', 278: 'creampie',
    330: 'romance', 351: 'teasing', 394: 'monster girl',
    535: 'groping', 783: 'animated', 817: 'big ass',
    1507: '2dcg',
  };

  // ── Public entry point ────────────────────────────────────────────────────

  /// Reads every enabled site, handing rows to [onRows] as each page arrives.
  /// [sites] says how far back each one was last caught up.
  static Future<FeedFetch> fetchAll(
    ScrapingService scraping,
    AppSettings settings, {
    required void Function(List<RawFeedItem>) onRows,
    Map<String, SiteCatchUp> sites = const {},
  }) async {
    final fetch = FeedFetch();
    if (settings.lockdown) return fetch;

    Future<void> catchUp(
      String site,
      Future<List<RawFeedItem>> Function(int page) readPage,
      Future<List<RawFeedItem>> Function() public,
    ) async {
      final read = await readBack(
        sites[site] ?? const SiteCatchUp(),
        readPage: readPage,
        onRows: onRows,
        now: DateTime.now(),
      );
      if (read != null) {
        fetch.sites[site] = read;
        if (read.stoppedEarly) fetch.problems[site] = 'behind';
        return;
      }
      final rows = await public();
      onRows(rows);
      fetch.problems[site] = rows.isEmpty ? 'failed' : 'public';
    }

    await Future.wait([
      // F95Zone — SAM JSON API (requires login cookies via ScrapingService)
      if (settings.feedSourceF95)
        catchUp('f95zone', (page) => _fetchF95ZoneJson(scraping, page), () => _f95ZonePublic(scraping)),
      if (settings.feedSourceLC)
        catchUp('lewdcorner', (page) => _fetchLewdCornerPage(scraping, page), () => _lewdCornerPublic(scraping)),
      // Azkosel's Corner — XenForo forum with two relevant categories:
      //   Node 13: regular games   /forums/games.13/index.rss
      //   Node 32: forbidden games /forums/forbidden-haven-games.32/index.rss
      // Both are fetched and merged under the single 'azc' source key.
      // Tried via plain HTTP first; falls back to ScrapingService if blocked.
      if (settings.feedSourceAzc) _fetchAzc(scraping, fetch, onRows),
    ]);
    return fetch;
  }

  /// JS returning a thread's first post dates as JSON, or nothing if the page
  /// isn't a readable thread.
  static const _threadDatesJs = '''
(() => {
  const first = document.querySelector('article.message');
  if (!first) return '';
  const posted = first.querySelector('.message-attribution time, header time');
  const edited = first.querySelector('.message-lastEdit time');
  return JSON.stringify({
    posted: posted ? posted.getAttribute('datetime') : null,
    edited: edited ? edited.getAttribute('datetime') : null,
  });
})()''';

  /// When a thread's first post went up and was last edited, or null if the
  /// thread can't be read.
  static Future<ThreadDates?> readThreadDates(ScrapingService scraping, String url) async {
    try {
      final raw = await scraping.evalOnPage(url, _threadDatesJs);
      return parseThreadDates(raw is String ? raw : '');
    } catch (e) {
      debugPrint('FeedService thread dates failed: $e');
      return null;
    }
  }

  static ThreadDates? parseThreadDates(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final posted = DateTime.tryParse('${json['posted']}');
    if (posted == null) return null;
    return ThreadDates(posted, DateTime.tryParse('${json['edited']}'));
  }

  static Future<void> _fetchAzc(
    ScrapingService scraping,
    FeedFetch fetch,
    void Function(List<RawFeedItem>) onRows,
  ) async {
    final forums = await Future.wait([
      for (final forum in ['games.13', 'forbidden-haven-games.32'])
        _fetchRss(
          scraping,
          'https://azkoselscorner.com/index.php?forums/$forum/index.rss',
          source: 'azc',
          label: 'AzC',
          requiresAuth: false,
        ),
    ]);
    final items = forums.expand((i) => i).toList();
    if (items.isEmpty) fetch.problems['azc'] = 'failed';
    onRows(items);
  }

  // ── F95Zone JSON API ─────────────────────────────────────────────────────

  /// F95Zone's public forum feed, for when its Latest Updates data fails.
  static Future<List<RawFeedItem>> _f95ZonePublic(ScrapingService scraping) => _fetchRss(
        scraping,
        'https://f95zone.to/forums/games.2/index.rss',
        source: 'f95zone',
        label: 'F95Zone',
        requiresAuth: false,
      );

  static Future<List<RawFeedItem>> _fetchF95ZoneJson(
    ScrapingService scraping,
    int page,
  ) async {
    final apiUrl =
        'https://f95zone.to/sam/latest_alpha/latest_data.php'
        '?cmd=list&cat=games&page=$page&sort=date&rows=60';
    try {
      // Use evalOnPage + document.body.innerText so we get the raw JSON string
      // rather than outerHTML (which wraps the JSON in <html><body><pre>…</pre></body></html>
      // when Chrome renders a bare JSON response).
      final raw = await scraping.evalOnPage(apiUrl, 'document.body.innerText');
      final body = raw is String ? raw.trim() : '';
      debugPrint('FeedService F95Zone raw length: ${body.length}, preview: ${body.length > 200 ? body.substring(0, 200) : body}');
      if (body.isEmpty) {
        debugPrint('FeedService F95Zone: empty response — session may have expired');
        return [];
      }

      return parseF95List(body);
    } catch (e) {
      debugPrint('FeedService F95Zone JSON failed: $e');
      return [];
    }
  }

  /// Items from F95Zone's Latest Updates data. The site sends a field as a
  /// number when it looks like one (a version of 1.5), so nothing here assumes
  /// a type: one odd row must not cost the rest of the page.
  static List<RawFeedItem> parseF95List(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return [];
    }
    if (json is! Map || json['status'] != 'ok') {
      debugPrint('FeedService F95Zone JSON status: ${json is Map ? json['status'] : 'not an object'}');
      return [];
    }
    final msg = json['msg'];
    final rows = msg is Map ? msg['data'] : null;
    if (rows is! List) return [];

    return rows.whereType<Map>().map((m) {
      final threadId = m['thread_id'];
      final title = '${m['title'] ?? ''}'.trim();
      final creator = '${m['creator'] ?? ''}'.trim();
      final version = '${m['version'] ?? ''}'.trim();
      final cover = '${m['cover'] ?? ''}'.trim();
      final ts = m['ts'];
      final rating = m['rating'];

      // Resolve tag IDs → names (skip meta/engine/status prefixes)
      final tagIds = (m['tags'] is List ? m['tags'] as List : const []).whereType<int>();
      final tagNames = tagIds
          .map((id) => _f95Tags[id])
          .whereType<String>()
          .toList();

      // Build a readable body for the raw card
      final parts = <String>[];
      if (version.isNotEmpty) parts.add('Version: $version');
      if (creator.isNotEmpty) parts.add('Developer: $creator');
      if (tagNames.isNotEmpty) parts.add('Tags: ${tagNames.join(', ')}');
      if (rating is num) parts.add('Rating: ${rating.toStringAsFixed(2)} / 5');
      if (m['new'] == true) parts.add('Kind: new');
      if (m['prefixes'] is List && (m['prefixes'] as List).contains(_f95Completed)) parts.add('Kind: complete');
      if (cover.isNotEmpty) parts.add('[cover] $cover');

      final threadUrl = 'https://f95zone.to/threads/$threadId/';
      final publishedAt = ts is num && ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000, isUtc: true)
          : null;

      return RawFeedItem(
        id: 'f95zone::$threadId',
        source: 'f95zone',
        sourceLabel: 'F95Zone',
        title: title,
        rawBody: parts.join('\n'),
        url: threadUrl,
        publishedAt: publishedAt,
        author: creator,
        channelName: 'Latest Updates',
      );
    }).toList();
  }

  // ── RSS ───────────────────────────────────────────────────────────────────

  /// LewdCorner's Latest Updates data is the best source (version, developer,
  /// tags, tier) but needs a login: logged out it answers 403 "Invalid API
  /// key".
  static Future<List<RawFeedItem>> _fetchLewdCornerPage(ScrapingService scraping, int page) async {
    try {
      final raw = await scraping.evalOnPage(
        'https://lewdcorner.com/latest-updates.php?api=1&action=list&perPage=60&page=$page',
        _documentSourceJs,
      );
      return parseLewdCornerList(raw is String ? raw : '');
    } catch (e) {
      debugPrint('FeedService LewdCorner list failed: $e');
      return [];
    }
  }

  /// The public feeds of the open forums are the fallback, with versions in
  /// their titles. Games+ also has a public feed, but it's left out: those
  /// games need a forum role, so a logged-out reader couldn't use them.
  static Future<List<RawFeedItem>> _lewdCornerPublic(ScrapingService scraping) async {
    final forums = await Future.wait([
      for (final forum in ['games.6', 'ai-games.212'])
        _fetchRss(
          scraping,
          'https://lewdcorner.com/forums/$forum/index.rss',
          source: 'lewdcorner',
          label: 'LewdCorner',
          requiresAuth: false,
        ),
    ]);
    return forums.expand((items) => items).toList();
  }

  /// Items from LewdCorner's Latest Updates data, written as the same plain
  /// lines as F95Zone's. Plus and AI+ games need a forum role, which the site
  /// doesn't report, so they're labelled for anyone who can't open them.
  static List<RawFeedItem> parseLewdCornerList(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return [];
    }
    final payload = json is Map ? (json['data'] ?? json) : null;
    final rows = payload is Map ? payload['items'] : null;
    if (rows is! List) return [];

    final items = <RawFeedItem>[];
    for (final r in rows.whereType<Map>()) {
      final title = _cleanFeedTitle('${r['title'] ?? ''}');
      var link = '${r['link'] ?? ''}'.trim();
      if (link.startsWith('/')) link = 'https://lewdcorner.com$link';
      if (title.isEmpty || !link.startsWith('http')) continue;

      final version = '${r['version'] ?? ''}'.trim();
      final developer = '${r['developer'] ?? ''}'.trim();
      final platforms = (r['platforms'] as List?)?.join(', ') ?? '';
      final tags = (r['tags'] as List?)?.join(', ') ?? '';
      final rating = r['rating'];
      final timestamp = r['timestamp'];
      final posted = r['posted_ts'];
      var cover = '${r['image'] ?? ''}'.trim();
      if (cover.startsWith('/')) cover = 'https://lewdcorner.com$cover';
      final completed = (r['badges'] as List?)?.any((b) => b is Map && '${b['name']}'.toLowerCase() == 'completed') ?? false;
      items.add(RawFeedItem(
        id: 'lewdcorner::$link',
        source: 'lewdcorner',
        sourceLabel: r['is_premium'] == true ? 'LewdCorner Plus' : 'LewdCorner',
        title: title,
        rawBody: [
          if (version.isNotEmpty) 'Version: $version',
          if (developer.isNotEmpty) 'Developer: $developer',
          if (platforms.isNotEmpty) 'Platforms: $platforms',
          if (tags.isNotEmpty) 'Tags: $tags',
          if (rating is num && rating > 0) 'Rating: ${rating.toStringAsFixed(2)} / 5',
          // is_new_game was false on all 60 rows sampled; is_new is what the
          // site itself shows as NEW.
          if (r['is_new'] == true || r['is_new_game'] == true) 'Kind: new',
          if (completed) 'Kind: complete',
          if (posted is int && posted > 0) 'Posted: $posted',
          if (cover.startsWith('http')) '[cover] $cover',
        ].join('\n'),
        url: link,
        publishedAt: timestamp is int
            ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
            : null,
        author: developer,
        channelName: 'Latest Updates - LewdCorner',
      ));
    }
    return items;
  }

  static Future<List<RawFeedItem>> _fetchRss(
    ScrapingService scraping,
    String feedUrl, {
    required String source,
    required String label,
    bool requiresAuth = true,
  }) async {
    try {
      String body = '';

      if (!requiresAuth) {
        // Try plain HTTP first (no cookies needed) — faster and avoids
        // burning a WebView page load for public endpoints.
        try {
          final resp = await http
              .get(Uri.parse(feedUrl), headers: {'User-Agent': _ua})
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.body.isNotEmpty) {
            body = resp.body;
          }
        } catch (_) {}
      }

      // Fall back to ScrapingService if plain HTTP failed or auth is required.
      // Read the document's source text, not its outerHTML: Chromium renders
      // a feed as plain text inside <html><body><pre>, which isn't valid XML.
      if (body.isEmpty) {
        final raw = await scraping.evalOnPage(feedUrl, _documentSourceJs);
        body = raw is String ? raw : '';
      }

      if (body.isEmpty) return [];
      return parseRss(body, source: source, label: label, feedUrl: feedUrl);
    } catch (e) {
      debugPrint('FeedService RSS ($source) failed: $e');
      return [];
    }
  }

  static List<RawFeedItem> parseRss(
    String xmlBody, {
    required String source,
    required String label,
    required String feedUrl,
  }) {
    try {
      final doc = XmlDocument.parse(xmlBody);
      final channelEl = doc.findAllElements('channel').firstOrNull;
      final feedTitle = channelEl?.findElements('title').firstOrNull?.innerText ?? label;

      final items = doc.findAllElements('item');
      return items.map((el) {
        // Standard RSS fields — clean XenForo prefix labels and bracket tags
        final rawTitle = el.findElements('title').firstOrNull?.innerText.trim() ?? '';
        // Extract version from bracket tags BEFORE cleaning the title so the
        // badge can still be rendered even after [v1.5] is stripped from display.
        final titleVersion = _extractTitleVersion(rawTitle);
        final title = _cleanFeedTitle(rawTitle);
        final link = el.findElements('link').firstOrNull?.innerText.trim() ?? '';
        // XenForo sends the post in content:encoded, and no description.
        final rawDesc = (el.findAllElements('encoded', namespace: '*').firstOrNull?.innerText ??
                el.findElements('description').firstOrNull?.innerText ??
                '')
            .trim();
        // Prepend "Version: X" to rawBody if found in title brackets and not
        // already present — this lets the version badge logic work for RSS
        // sources (AzC, LewdCorner) the same way it does for F95Zone.
        final titleDeveloper = _titleDeveloper(rawTitle);
        final desc = [
          if (titleVersion != null && !rawDesc.contains('Version:')) 'Version: $titleVersion',
          if (titleDeveloper.isNotEmpty) 'Developer: $titleDeveloper',
          rawDesc,
        ].join('\n');
        final pubDateRaw = el.findElements('pubDate').firstOrNull?.innerText.trim() ?? '';

        // dc:creator (XenForo uses this for the poster name)
        // <author> is "invalid@example.com (Name)" when it's there at all.
        final creator = el.findAllElements('creator', namespace: '*').firstOrNull?.innerText.trim() ??
            RegExp(r'\((.+)\)\s*$').firstMatch(el.findElements('author').firstOrNull?.innerText ?? '')?.group(1) ??
            '';

        final published = _parseRssDate(pubDateRaw);
        final id = '$source::${link.isNotEmpty ? link : title}';

        return RawFeedItem(
          id: id,
          source: source,
          sourceLabel: label,
          title: title,
          rawBody: desc,
          url: link,
          publishedAt: published,
          author: creator,
          channelName: feedTitle,
        );
      }).toList();
    } catch (e) {
      debugPrint('FeedService RSS parse ($source) failed: $e');
      return [];
    }
  }

  // ── Title cleaning ────────────────────────────────────────────────────────

  /// Extract a version string from XenForo title bracket tags.
  /// Returns the first bracket content that looks like a version number:
  ///   [v1.5] → "v1.5"   [v0.4.8a] → "v0.4.8a"   [v1.0 Final] → "v1.0 Final"
  ///   [Ch. 5] → "Ch. 5"   [Episode 3] → "Episode 3"
  /// Returns null if no version-like bracket is found.
  static String? _extractTitleVersion(String rawTitle) {
    final m = RegExp(
      r'\[(v[\d.]+[^\]]*|\d+(?:\.\d+)+[^\]]*|ch(?:apter)?\.?\s*\d+[^\]]*|episode\s*\d+[^\]]*)\]',
      caseSensitive: false,
    ).firstMatch(rawTitle);
    return m?.group(1)?.trim();
  }

  /// Forum threads are titled "Game [v0.1] [Studio]", so the last bracket is
  /// the developer unless it's the version. Mod threads can name the modder
  /// there, which is still closer than the poster.
  static String _titleDeveloper(String rawTitle) {
    final brackets = RegExp(r'\[([^\]]*)\]').allMatches(rawTitle).map((m) => m.group(1)!.trim()).toList();
    if (brackets.length < 2) return '';
    final last = brackets.last;
    if (last == _extractTitleVersion(rawTitle)) return '';
    if (RegExp(r'^(?:v|ver|ch|chapter|ep|episode|season|part|final|demo|completed?)?[\s.]*\d', caseSensitive: false).hasMatch(last)) {
      return '';
    }
    return cleanDeveloperName(last);
  }

  /// Strip XenForo thread-prefix labels and bracket tags from an RSS title.
  ///
  /// XenForo RSS feeds include the full thread title, which contains:
  ///   - Bracket tags: [v1.5], [DeveloperName], [Ren'Py]
  ///   - Plain-text prefix labels: "Ren'Py AI VN " prepended to the real title
  ///
  /// Two passes — strip brackets first, then strip leading known prefix words.
  static String _cleanFeedTitle(String raw) {
    // Pass 1: strip [bracketed] content
    var t = raw.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();
    // Pass 2: strip known XenForo thread-prefix words from the front
    const prefixes = <String>[
      'rpg maker', 'unreal engine', 'wolf rpg', 'on hold', 'tyranobuilder',
      "ren'py", 'renpy', 'rpgm', 'unity', 'html', 'unreal', 'flash',
      'godot', 'java', 'twine', 'construct', 'webgl', '3dcg', '2dcg',
      'vn', 'ai', 'completed', 'abandoned', 'onhold', 'paused', 'demo',
    ];
    bool changed = true;
    while (changed && t.isNotEmpty) {
      changed = false;
      for (final prefix in prefixes) {
        if (t.toLowerCase().startsWith('$prefix ')) {
          t = t.substring(prefix.length).trim();
          changed = true;
          break;
        }
      }
    }
    return t;
  }

  // ── Cross-source deduplication ───────────────────────────────────────────

  /// One row per release. When several sites post the same version of a game,
  /// the one published FIRST wins: a fair race, no platform bias. A different
  /// version is a different release, so it keeps its own row.
  static List<RawFeedItem> deduplicate(List<RawFeedItem> items) {
    final winners = <String, RawFeedItem>{};
    for (final item in items) {
      final key = releaseKey(item);
      if (key.isEmpty) continue;
      final current = winners[key];
      if (current == null) {
        winners[key] = item;
      } else {
        final ct = current.publishedAt;
        final it = item.publishedAt;
        // Prefer whichever has an earlier timestamp; if one is null, keep the
        // other (a dated post is more authoritative than an undated one).
        if (ct == null || (it != null && it.isBefore(ct))) {
          winners[key] = item;
        }
      }
    }
    return items.where((item) {
      final key = releaseKey(item);
      return key.isEmpty || identical(winners[key], item);
    }).toList();
  }

  /// Identifies a release across sites: the game's title plus its version.
  static String releaseKey(RawFeedItem item) {
    final title = feedTitleKey(item.title);
    if (title.isEmpty) return '';
    return '$title|${feedVersionKey(item)}';
  }

  // ── Date parsing ──────────────────────────────────────────────────────────

  /// Parse an RSS pubDate string (RFC 2822) into a UTC DateTime.
  /// e.g. "Mon, 01 Jan 2024 12:34:56 +0000"
  static DateTime? _parseRssDate(String raw) {
    if (raw.isEmpty) return null;
    // Try ISO 8601 first (some feeds use it)
    try {
      return DateTime.parse(raw);
    } catch (_) {}

    // RFC 2822 manual parse
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final m = RegExp(
      r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (m == null) return null;
    final month = months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
