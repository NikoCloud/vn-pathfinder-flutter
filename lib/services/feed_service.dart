import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/feed_item.dart';
import '../providers/settings_provider.dart';
import 'scraping_service.dart';

/// Fetches raw feed items from all configured sources.
/// Returns items sorted newest-first.
///
/// F95Zone is fetched via the SAM JSON API (/sam/latest_alpha/latest_data.php)
/// which requires login cookies — routed through [ScrapingService].
///
/// LewdCorner uses a public RSS endpoint — tried via plain HTTP first.
///
/// Discord sources are polled via the REST API using the stored bot token.
class FeedService {
  static const _ua = 'VN-Pathfinder/2.0 (https://github.com/NikoCloud/vn-pathfinder-flutter)';

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

  static Future<List<RawFeedItem>> fetchAll(
    ScrapingService scraping,
    AppSettings settings,
  ) async {
    final futures = <Future<List<RawFeedItem>>>[];

    if (!settings.lockdown) {
      // F95Zone — SAM JSON API (requires login cookies via ScrapingService)
      if (settings.feedSourceF95) {
        futures.add(_fetchF95ZoneJson(scraping));
      }
      if (settings.feedSourceLC) {
        // LewdCorner's dedicated latest-updates RSS API — returns rich
        // structured descriptions including developer, version, clean tags,
        // platforms, cover image (enclosure), and screenshot URLs.
        // Does not appear to require authentication (public API endpoint).
        futures.add(_fetchRss(
          scraping,
          'https://lewdcorner.com/latest-updates.php?api=1&action=rss',
          source: 'lewdcorner',
          label: 'LewdCorner',
          requiresAuth: false, // public API endpoint, no login cookies needed
        ));
      }
      if (settings.feedSourceAzc) {
        // Azkosel's Corner — XenForo forum with two relevant categories:
        //   Node 13: regular games   /forums/games.13/index.rss
        //   Node 32: forbidden games /forums/forbidden-haven-games.32/index.rss
        // Both are fetched and merged under the single 'azc' source key.
        // Tried via plain HTTP first; falls back to ScrapingService if blocked.
        futures.add(_fetchRss(
          scraping,
          'https://azkoselscorner.com/index.php?forums/games.13/index.rss',
          source: 'azc',
          label: "AzC",
          requiresAuth: false,
        ));
        futures.add(_fetchRss(
          scraping,
          'https://azkoselscorner.com/index.php?forums/forbidden-haven-games.32/index.rss',
          source: 'azc',
          label: "AzC",
          requiresAuth: false,
        ));
      }

      // Discord sources
      final token = settings.discordBotToken;
      if (token.isNotEmpty) {
        for (final ch in settings.discordChannelIds) {
          final parts = ch.split(':'); // format: "channelId:ServerName:#channelName"
          final channelId = parts[0].trim();
          final serverName = parts.length > 1 ? parts[1].trim() : 'Discord';
          final channelName = parts.length > 2 ? parts[2].trim() : channelId;
          if (channelId.isNotEmpty) {
            futures.add(_fetchDiscord(
              channelId: channelId,
              token: token,
              serverName: serverName,
              channelName: channelName,
            ));
          }
        }
      }
    }

    final results = await Future.wait(futures, eagerError: false);
    final all = results.expand((r) => r).toList();

    // Sort newest first
    all.sort((a, b) {
      final ta = a.publishedAt;
      final tb = b.publishedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    return all;
  }

  // ── F95Zone JSON API ─────────────────────────────────────────────────────

  static Future<List<RawFeedItem>> _fetchF95ZoneJson(
    ScrapingService scraping,
  ) async {
    const apiUrl =
        'https://f95zone.to/sam/latest_alpha/latest_data.php'
        '?cmd=list&cat=games&page=1&sort=date&rows=60';
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

      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] != 'ok') {
        debugPrint('FeedService F95Zone JSON status: ${json['status']} — full: $json');
        return [];
      }

      final msgData = (json['msg'] as Map<String, dynamic>?)?['data'] as List?;
      if (msgData == null) return [];

      return msgData.map((raw) {
        final m = raw as Map<String, dynamic>;
        final threadId = m['thread_id'];
        final title = (m['title'] as String? ?? '').trim();
        final creator = (m['creator'] as String? ?? '').trim();
        final version = (m['version'] as String? ?? '').trim();
        final cover = (m['cover'] as String? ?? '').trim();
        final ts = m['ts'] as int? ?? 0;
        final dateLabel = (m['date'] as String? ?? '').trim();
        final rating = m['rating'];

        // Resolve tag IDs → names (skip meta/engine/status prefixes)
        final tagIds = (m['tags'] as List? ?? []).whereType<int>();
        final tagNames = tagIds
            .map((id) => _f95Tags[id])
            .whereType<String>()
            .toList();

        // Build a readable body for the raw card
        final parts = <String>[];
        if (version.isNotEmpty) parts.add('Version: $version');
        if (creator.isNotEmpty) parts.add('Developer: $creator');
        if (tagNames.isNotEmpty) parts.add('Tags: ${tagNames.join(', ')}');
        if (rating != null) {
          final r = (rating as num).toStringAsFixed(2);
          parts.add('Rating: $r / 5');
        }
        if (dateLabel.isNotEmpty) parts.add('Updated: $dateLabel');
        if (cover.isNotEmpty) parts.add('[cover] $cover');

        final threadUrl = 'https://f95zone.to/threads/$threadId/';
        final publishedAt = ts > 0
            ? DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
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
    } catch (e) {
      debugPrint('FeedService F95Zone JSON failed: $e');
      return [];
    }
  }

  // ── RSS ───────────────────────────────────────────────────────────────────

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
      if (body.isEmpty) {
        body = await scraping.getString(feedUrl);
      }

      if (body.isEmpty) return [];
      return _parseRss(body, source: source, label: label, feedUrl: feedUrl);
    } catch (e) {
      debugPrint('FeedService RSS ($source) failed: $e');
      return [];
    }
  }

  static List<RawFeedItem> _parseRss(
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
        final rawDesc = el.findElements('description').firstOrNull?.innerText.trim() ?? '';
        // Prepend "Version: X" to rawBody if found in title brackets and not
        // already present — this lets the version badge logic work for RSS
        // sources (AzC, LewdCorner) the same way it does for F95Zone.
        final desc = (titleVersion != null && !rawDesc.contains('Version:'))
            ? 'Version: $titleVersion\n$rawDesc'
            : rawDesc;
        final pubDateRaw = el.findElements('pubDate').firstOrNull?.innerText.trim() ?? '';

        // dc:creator (XenForo uses this for the poster name)
        final creator = el.findAllElements('creator').firstOrNull?.innerText.trim() ??
            el.findAllElements('author').firstOrNull?.innerText.trim() ??
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

  // ── Discord REST API ──────────────────────────────────────────────────────

  static Future<List<RawFeedItem>> _fetchDiscord({
    required String channelId,
    required String token,
    required String serverName,
    required String channelName,
  }) async {
    try {
      final resp = await http.get(
        Uri.parse(
            'https://discord.com/api/v10/channels/$channelId/messages?limit=50'),
        headers: {
          'Authorization': 'Bot $token',
          'User-Agent': _ua,
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('Discord channel $channelId returned ${resp.statusCode}: ${resp.body}');
        return [];
      }

      final messages = jsonDecode(resp.body) as List;
      return messages.map((m) {
        final msg = m as Map<String, dynamic>;
        final id = msg['id'] as String? ?? '';
        final content = msg['content'] as String? ?? '';
        final timestamp = msg['timestamp'] as String? ?? '';
        final authorObj = msg['author'] as Map? ?? {};
        final username = authorObj['username'] as String? ?? '';
        final globalName = authorObj['global_name'] as String? ?? username;

        // Embeds: Discord bots often post game info in embeds
        final embeds = (msg['embeds'] as List?) ?? [];
        String embedText = '';
        for (final e in embeds) {
          final em = e as Map<String, dynamic>;
          final eTitle = em['title'] as String? ?? '';
          final eDesc = em['description'] as String? ?? '';
          if (eTitle.isNotEmpty || eDesc.isNotEmpty) {
            embedText += '${eTitle.isNotEmpty ? "[$eTitle] " : ""}$eDesc\n';
          }
        }

        // Attachments: list their filenames
        final attachments = (msg['attachments'] as List?) ?? [];
        final attachText = attachments.isEmpty
            ? ''
            : '\n📎 ${attachments.map((a) => (a as Map)['filename'] ?? '').join(', ')}';

        final body = [content, embedText.trim(), attachText.trim()]
            .where((s) => s.isNotEmpty)
            .join('\n\n');

        // Title: first line of content or embed title, capped at 120 chars
        final firstLine = content.split('\n').first.trim();
        final titleText = firstLine.isNotEmpty
            ? (firstLine.length > 120 ? '${firstLine.substring(0, 117)}…' : firstLine)
            : (embeds.isNotEmpty
                ? ((embeds.first as Map)['title'] as String? ?? 'Discord post')
                : 'Discord post');

        return RawFeedItem(
          id: 'discord::$channelId::$id',
          source: 'discord',
          sourceLabel: serverName,
          title: titleText,
          rawBody: body,
          url: 'https://discord.com/channels/@me/$channelId/$id',
          publishedAt: timestamp.isNotEmpty ? DateTime.tryParse(timestamp) : null,
          author: globalName,
          channelName: channelName,
        );
      }).toList();
    } catch (e) {
      debugPrint('FeedService Discord $channelId failed: $e');
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
      r'\[(v[\d.]+[^\]]*|ch(?:apter)?\.?\s*\d+[^\]]*|episode\s*\d+[^\]]*)\]',
      caseSensitive: false,
    ).firstMatch(rawTitle);
    return m?.group(1)?.trim();
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

  /// Deduplicates non-Discord items by normalized title.
  /// When two sources cover the same game, the one published FIRST wins —
  /// fair race condition, no platform bias.
  /// Discord posts are never deduplicated (they're announcements, not indexes).
  static List<RawFeedItem> deduplicate(List<RawFeedItem> items) {
    // Pass 1: find the earliest-published item for each normalized title.
    final winners = <String, RawFeedItem>{};
    for (final item in items) {
      if (item.source == 'discord') continue;
      final key = _normalizeTitle(item.title);
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

    // Pass 2: keep winner entries + all Discord posts (preserving sort order).
    return items.where((item) {
      if (item.source == 'discord') return true;
      final key = _normalizeTitle(item.title);
      if (key.isEmpty) return true;
      return identical(winners[key], item);
    }).toList();
  }

  /// Normalize a title for dedup comparison:
  /// lowercase → strip version strings → strip punctuation → collapse spaces.
  static String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r"v?\d+[\d.]*[a-z]?(\s*(alpha|beta|rc)\s*\d*)?",
            caseSensitive: false), '')  // strip version numbers
        .replaceAll(RegExp(r"[^a-z0-9\s]"), '')   // strip punctuation
        .replaceAll(RegExp(r'\s+'), ' ')            // collapse whitespace
        .trim();
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
