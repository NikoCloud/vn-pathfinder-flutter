import 'dart:convert'; // jsonDecode, jsonEncode, base64Decode
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'scraping_service.dart';

// ── Result Model ──────────────────────────────────────────────────────────────

/// A single search result from any metadata provider.
class MetadataResult {
  final String provider; // 'vndb' | 'f95zone' | 'lewdcorner' | 'itchio'
  final String id;
  final String title;
  final String developer;
  final String synopsis;
  final String coverUrl;
  final List<String> screenshotUrls;
  final String sourceUrl;
  final List<String> tags;
  final String releaseDate;

  const MetadataResult({
    required this.provider,
    required this.id,
    required this.title,
    required this.developer,
    this.synopsis = '',
    this.coverUrl = '',
    this.screenshotUrls = const [],
    required this.sourceUrl,
    this.tags = const [],
    this.releaseDate = '',
  });

  /// Converts this result to the .vnpf/metadata.json schema.
  Map<String, dynamic> toMetadataJson({Map<String, dynamic>? existing}) {
    final base = Map<String, dynamic>.from(existing ?? {});
    if (title.isNotEmpty) base['title'] = title;
    if (developer.isNotEmpty) base['developer'] = developer;
    if (synopsis.isNotEmpty) base['synopsis'] = synopsis;
    if (releaseDate.isNotEmpty) base['release_date'] = releaseDate;
    if (tags.isNotEmpty) base['tags_fetched'] = tags;
    base['source_url'] = sourceUrl;
    if (provider == 'vndb') base['vndb_url'] = sourceUrl;
    if (provider == 'f95zone') base['f95_url'] = sourceUrl;
    if (provider == 'lewdcorner') base['lc_url'] = sourceUrl;
    if (provider == 'itchio') base['itch_url'] = sourceUrl;
    return base;
  }
}

// ── MetadataService ───────────────────────────────────────────────────────────

class MetadataService {
  static const _ua =
      'VN-Pathfinder/2.0 (https://github.com/NikoCloud/vn-pathfinder-flutter)';
  static const _baseHeaders = {'User-Agent': _ua};

  // ── VNDB ───────────────────────────────────────────────────────────────────

  /// Search VNDB for visual novels matching [query].
  /// No authentication required. Works in lockdown=OFF.
  static Future<List<MetadataResult>> searchVndb(String query) async {
    try {
      final body = jsonEncode({
        'filters': ['search', '=', query],
        'fields':
            'title, alttitle, developers.name, description, image.url, '
            'screenshots.url, released, tags.name',
        'results': 15,
        'sort': 'searchrank',
      });
      final resp = await http
          .post(
            Uri.parse('https://api.vndb.org/kana/vn'),
            headers: {..._baseHeaders, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        debugPrint('VNDB API error ${resp.statusCode}: ${resp.body}');
        return [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      return results
          .map((r) => _parseVndbResult(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('VNDB search failed: $e');
      return [];
    }
  }

  static MetadataResult _parseVndbResult(Map<String, dynamic> r) {
    final id = (r['id'] as String?) ?? '';
    final title = (r['title'] as String?) ?? '';
    final devs = (r['developers'] as List?)
            ?.map((d) => ((d as Map)['name'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];
    final developer = devs.join(', ');

    // Strip VNDB BBCode markup
    var synopsis = (r['description'] as String?) ?? '';
    synopsis = synopsis
        .replaceAll(RegExp(r'\[/?[^\]]+\]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    final image = r['image'] as Map?;
    final coverUrl = (image?['url'] as String?) ?? '';

    final screenshotUrls = ((r['screenshots'] as List?) ?? [])
        .map((s) => ((s as Map)['url'] as String?) ?? '')
        .where((u) => u.isNotEmpty)
        .take(9)
        .toList();

    final tags = ((r['tags'] as List?) ?? [])
        .map((t) => ((t as Map)['name'] as String?) ?? '')
        .where((t) => t.isNotEmpty)
        .take(20)
        .toList();

    return MetadataResult(
      provider: 'vndb',
      id: id,
      title: title,
      developer: developer,
      synopsis: synopsis,
      coverUrl: coverUrl,
      screenshotUrls: screenshotUrls,
      sourceUrl: 'https://vndb.org/$id',
      tags: tags,
      releaseDate: (r['released'] as String?) ?? '',
    );
  }

  // ── F95Zone ────────────────────────────────────────────────────────────────

  /// Search F95Zone for games.
  /// Uses [scrapingService] to bypass Cloudflare. 
  static Future<List<MetadataResult>> searchF95Zone(
    String query,
    ScrapingService scrapingService,
  ) async {
    try {
      // Build URL manually — Uri.https percent-encodes [] brackets which XenForo doesn't decode.
      // c[title_only]=1 is critical: without it XenForo searches post bodies and returns
      // discussion threads instead of game listings.
      final encodedKeywords = Uri.encodeQueryComponent(query);
      final url = 'https://f95zone.to/search/search'
          '?keywords=$encodedKeywords'
          '&t=post'
          '&o=relevance'
          '&c[nodes][0]=2'   // Adult Games forum node
          '&c[child_nodes]=1'
          '&c[title_only]=1';

      final html = await scrapingService.getString(url);
      if (html.isEmpty) return [];
      
      // Simple login detection
      if (html.contains('id="ctrl_auth_login"') || html.contains('login--container')) {
        debugPrint('F95Zone search redirected to login page. Session may have expired.');
        return [];
      }
      
      return _parseF95SearchHtml(html, query);
    } catch (e) {
      debugPrint('F95Zone search failed: $e');
      return [];
    }
  }

  /// Strip XenForo bracket tags from a raw thread title.
  /// e.g. "Acting Lessons [v1.0] [DarkSilver] [Ren'Py]" → "Acting Lessons"
  static String _cleanXenforoTitle(String raw) {
    return raw.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();
  }

  static List<MetadataResult> _parseF95SearchHtml(String body, String query) {
    final doc = html_parser.parse(body);
    final results = <MetadataResult>[];

    // XenForo 2.x Search Result Pattern (li.block-row)
    final searchRows = doc.querySelectorAll('li.block-row');
    for (final el in searchRows) {
      final titleEl = el.querySelector('h3.contentRow-title a');
      if (titleEl == null) continue;

      // Strip XenForo thread-prefix label spans rendered inline with the title
      // e.g. <span class="label label--green">VN</span><span ...>Ren'Py</span>
      for (final label in titleEl.querySelectorAll('span')) {
        label.remove();
      }
      final title = _cleanXenforoTitle(titleEl.text.trim());
      final href = titleEl.attributes['href'] ?? '';
      final url = href.startsWith('http') ? href : 'https://f95zone.to$href';
      
      // Developer is NOT reliably available in search result cards —
      // ul.listInline contains the thread poster (not the developer).
      // Leave it blank; fetchThreadDetails() will fill it from the OP body.
      results.add(MetadataResult(
        provider: 'f95zone',
        id: href,
        title: title,
        developer: '',
        sourceUrl: url,
      ));
    }

    // Fallback: Thread List Pattern (div.structItem--thread)
    if (results.isEmpty) {
      final threadItems = doc.querySelectorAll('div.structItem--thread');
      for (final el in threadItems) {
        final titleEl = el.querySelector('div.structItem-title a[data-tp-primary]') ??
                        el.querySelector('div.structItem-title a');
        if (titleEl == null) continue;

        // Strip XenForo thread-prefix label spans
        for (final label in titleEl.querySelectorAll('span')) {
          label.remove();
        }
        final title = _cleanXenforoTitle(titleEl.text.trim());
        final href = titleEl.attributes['href'] ?? '';
        final url = href.startsWith('http') ? href : 'https://f95zone.to$href';

        // Leave developer blank — structItem-metaInfo shows the poster, not the dev.
        results.add(MetadataResult(
          provider: 'f95zone',
          id: href,
          title: title,
          developer: '',
          sourceUrl: url,
        ));
      }
    }

    return results.where((r) => r.title.isNotEmpty && r.sourceUrl.isNotEmpty).toList();
  }

  // ── LewdCorner ─────────────────────────────────────────────────────────────

  /// Search LewdCorner for games.
  static Future<List<MetadataResult>> searchLewdCorner(
    String query,
    ScrapingService scrapingService,
  ) async {
    try {
      // Same manual URL construction as F95Zone — avoids bracket encoding issues.
      // c[title_only]=1 filters to game thread titles only (node 6 = master Games forum,
      // child_nodes=1 includes sub-forums like AI/Plus games).
      final encodedKeywords = Uri.encodeQueryComponent(query);
      final url = 'https://lewdcorner.com/search/search'
          '?keywords=$encodedKeywords'
          '&t=post'
          '&o=relevance'
          '&c[nodes][0]=6'   // Games forum node (master, includes sub-forums)
          '&c[child_nodes]=1'
          '&c[title_only]=1';

      final html = await scrapingService.getString(url);
      if (html.isEmpty) return [];

      if (html.contains('id="ctrl_auth_login"') || html.contains('login--container')) {
        debugPrint('LewdCorner search redirected to login page. Session may have expired.');
        return [];
      }
      
      return _parseLcSearchHtml(html, query);
    } catch (e) {
      debugPrint('LewdCorner search failed: $e');
      return [];
    }
  }

  static List<MetadataResult> _parseLcSearchHtml(String body, String query) {
    final doc = html_parser.parse(body);
    final results = <MetadataResult>[];

    // Search Result Pattern
    final searchRows = doc.querySelectorAll('li.block-row');
    for (final el in searchRows) {
      final titleEl = el.querySelector('h3.contentRow-title a');
      if (titleEl == null) continue;

      // Strip XenForo thread-prefix label spans
      for (final label in titleEl.querySelectorAll('span')) {
        label.remove();
      }
      final title = _cleanXenforoTitle(titleEl.text.trim());
      final href = titleEl.attributes['href'] ?? '';
      final url = href.startsWith('http') ? href : 'https://lewdcorner.com$href';

      results.add(MetadataResult(
        provider: 'lewdcorner',
        id: href,
        title: title,
        developer: '',
        sourceUrl: url,
      ));
    }

    // Fallback: Thread List Pattern
    if (results.isEmpty) {
      final threadItems = doc.querySelectorAll('div.structItem--thread');
      for (final el in threadItems) {
        final titleEl = el.querySelector('div.structItem-title a[data-tp-primary]') ??
                        el.querySelector('div.structItem-title a');
        if (titleEl == null) continue;

        // Strip XenForo thread-prefix label spans
        for (final label in titleEl.querySelectorAll('span')) {
          label.remove();
        }
        final title = _cleanXenforoTitle(titleEl.text.trim());
        final href = titleEl.attributes['href'] ?? '';
        final url = href.startsWith('http') ? href : 'https://lewdcorner.com$href';

        results.add(MetadataResult(
          provider: 'lewdcorner',
          id: href,
          title: title,
          developer: '',
          sourceUrl: url,
        ));
      }
    }

    return results.where((r) => r.title.isNotEmpty && r.sourceUrl.isNotEmpty).toList();
  }

  // ── itch.io ────────────────────────────────────────────────────────────────

  /// Search itch.io for games.
  static Future<List<MetadataResult>> searchItchio(
    String query,
    ScrapingService scrapingService,
  ) async {
    try {
      final uri = Uri.https('itch.io', '/search', {
        'q': query,
        'type': 'games',
      });
      final html = await scrapingService.getString(uri.toString());
      if (html.isEmpty) return [];
      
      return _parseItchSearchHtml(html, query);
    } catch (e) {
      debugPrint('itch.io search failed: $e');
      return [];
    }
  }

  static List<MetadataResult> _parseItchSearchHtml(String body, String query) {
    final doc = html_parser.parse(body);
    final cells = doc.querySelectorAll('div.game_cell');
    if (cells.isEmpty) return [];
    return cells.take(12).map((el) {
      final titleEl = el.querySelector('a.title.game_link') ??
          el.querySelector('.game_cell_data .title');
      final title = titleEl?.text.trim() ?? '';
      final href =
          titleEl?.attributes['href'] ?? el.querySelector('a')?.attributes['href'] ?? '';
      final devEl = el.querySelector('div.game_author a');
      final developer = devEl?.text.trim() ?? '';
      final imgEl = el.querySelector('img.thumb_img') ??
          el.querySelector('img.lazy_loaded') ??
          el.querySelector('img');
      final coverUrl = imgEl?.attributes['data-lazy_src'] ??
          imgEl?.attributes['src'] ??
          '';
      final url =
          href.startsWith('http') ? href : 'https://itch.io$href';
      // Tags: itch.io search cells sometimes include genre badges
      final tagEls = el.querySelectorAll(
          '.game_genre a, .tag_cloud a, .tag_container a, '
          'a.tag, span.tag_label');
      final tags = tagEls
          .map((t) => t.text.trim())
          .where((t) => t.isNotEmpty && t.length < 40)
          .take(10)
          .toList();
      return MetadataResult(
        provider: 'itchio',
        id: href,
        title: title.isEmpty ? query : title,
        developer: developer,
        coverUrl: coverUrl,
        sourceUrl: url,
        tags: tags,
      );
    }).where((r) => r.title.isNotEmpty && r.sourceUrl.isNotEmpty).toList();
  }

  /// F95Zone/XenForo meta-classification tags that should NOT be stored as
  /// genre/content tags. These duplicate the app's own engine-detection and
  /// status fields, or are too generic to be useful in a VN library context.
  static const _xfMetaTags = <String>{
    // Engine names — redundant with scanner's isRenpy / metaEngine detection
    "ren'py", 'renpy', 'rpgm', 'rpg maker', 'unity', 'html', 'unreal',
    'flash', 'others', 'godot', 'java', 'twine', 'construct', 'wolf rpg',
    'tyranobuilder', 'webgl',
    // Broad type classifiers — the whole library is VNs
    'vn', 'visual novel',
    // Status terms — duplicated by the app's own status field
    'abandoned', 'completed', 'onhold', 'on hold', 'paused',
    // F95Zone moderation/release labels
    'demo', 'patch', 'fixed',
  };

  // ── Thread Detail Enrichment (F95Zone / LewdCorner) ───────────────────────

  /// Fetch the actual game thread page and extract cover image + screenshots.
  static Future<MetadataResult> fetchThreadDetails(
    MetadataResult result,
    ScrapingService scrapingService,
  ) async {
    if (result.sourceUrl.isEmpty) return result;
    try {
      final html = await scrapingService.getString(result.sourceUrl);
      if (html.isEmpty) return result;
      return _parseThreadPage(result, html);
    } catch (e) {
      debugPrint('Thread detail fetch failed: $e');
      return result;
    }
  }

  static MetadataResult _parseThreadPage(MetadataResult result, String body) {
    final doc = html_parser.parse(body);

    // The first post in the thread contains the game description + images.
    // Strategy: grab the FIRST article.message--post (= OP), then dig into
    // its div.bbWrapper where XenForo 2.x renders bbCode content.
    final opArticle = doc.querySelector('article.message--post') ??
        doc.querySelector('article.message');
    final opEl = opArticle?.querySelector('div.bbWrapper') ??
        opArticle?.querySelector('.message-body') ??
        doc.querySelector('div.bbWrapper');
    if (opEl == null) return result;

    // ── Extract full-size images from the OP post ────────────────────────
    //
    // XenForo 2 uses thumbnails in <img src> and puts the full-res URL in:
    //   1. div.bbImageWrapper[data-lb-src]  — native attachment lightbox src
    //   2. a[href] wrapping the <img>        — lightbox anchor href
    //   3. img[data-url]                     — sometimes used for full-res
    //
    // For externally-hosted images (imgbox, postimages, etc.) the <img src>
    // IS the full-res URL because they have no wrapper lightbox mechanism.
    //
    // Strategy: prefer wrapper/anchor full-res first; fall back to img src
    // only for images that aren't wrapped in a lightbox container.

    final siteBase = result.provider == 'f95zone'
        ? 'https://f95zone.to'
        : 'https://lewdcorner.com';

    String absUrl(String url) {
      if (url.startsWith('//')) return 'https:$url';
      if (!url.startsWith('http')) return '$siteBase$url';
      return url;
    }

    final imageUrls = <String>[];

    // Pass 1 — XenForo attachment wrappers: div.bbImageWrapper[data-lb-src]
    for (final wrapper in opEl.querySelectorAll('div.bbImageWrapper[data-lb-src]')) {
      final src = absUrl(wrapper.attributes['data-lb-src']!.trim());
      if (src.isNotEmpty && !imageUrls.contains(src)) imageUrls.add(src);
    }

    // Pass 1b — LewdCorner / some XenForo installs use [data-lb-src] on <a>
    //   instead of on a div wrapper.  Also catch class="js-lbImage".
    for (final a in opEl.querySelectorAll(
        'a[data-lb-src], a.js-lbImage, a[data-fancybox]')) {
      final src = absUrl(
        (a.attributes['data-lb-src'] ??
                a.attributes['data-fancybox-src'] ??
                a.attributes['href'] ??
                '')
            .trim(),
      );
      if (src.isEmpty) { continue; }
      if (!RegExp(r'\.(jpe?g|png|webp|gif|avif)(\?|$)', caseSensitive: false)
          .hasMatch(src)) { continue; }
      if (!imageUrls.contains(src)) { imageUrls.add(src); }
    }

    // Pass 2 — lightbox anchors: <a href="…"> wrapping an <img>
    //   Covers both XenForo native attachments and externally-linked images
    //   where the poster linked to the full image.
    for (final a in opEl.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      // Only follow anchors that point directly to an image file
      if (!RegExp(r'\.(jpe?g|png|webp|gif|avif)(\?|$)', caseSensitive: false)
          .hasMatch(href)) { continue; }
      // Must contain at least one <img> child (confirm it's an image link)
      if (a.querySelector('img') == null) { continue; }
      final src = absUrl(href);
      if (!imageUrls.contains(src)) imageUrls.add(src);
    }

    // Pass 3 — fallback for imgs NOT inside a bbImageWrapper or lightbox <a>
    //   These are usually externally-hosted images already at full resolution.
    for (final img in opEl.querySelectorAll('img')) {
      // Skip if already captured via a wrapper/anchor in passes 1–2
      final parentA = img.parent;
      final inLightboxAnchor = parentA?.localName == 'a' &&
          (parentA?.attributes['href'] ?? '').isNotEmpty;
      final inWrapper = img.parent?.classes.contains('bbImageWrapper') == true ||
          img.parent?.parent?.classes.contains('bbImageWrapper') == true;
      if (inLightboxAnchor || inWrapper) continue;

      // Skip tiny images (emoji, avatars, icons)
      final w = int.tryParse(img.attributes['width'] ?? '0') ?? 0;
      final h = int.tryParse(img.attributes['height'] ?? '0') ?? 0;
      if ((w > 0 && w < 100) || (h > 0 && h < 100)) continue;

      var src = (img.attributes['data-url'] ??
              img.attributes['data-src'] ??
              img.attributes['data-lazy-src'] ??
              img.attributes['src'] ?? '')
          .trim();
      if (src.isEmpty) continue;

      // Skip obvious thumbnails by URL pattern (thumb_, _thumb., /thumb/)
      if (RegExp(r'(^|[/_-])thumb[_./]', caseSensitive: false).hasMatch(src)) continue;

      src = absUrl(src);
      if (!imageUrls.contains(src)) imageUrls.add(src);
    }

    // ── Extract developer and synopsis from labeled fields in OP text ────────
    //
    // XenForo game threads follow a structured template with bold labels:
    //   <b>Developer:</b> SomeDev<br>
    //   <b>Overview:</b><br>Synopsis text...<br>
    //
    // When we call opEl.text we get the plain-text version with labels intact.
    // Regex on that text is more reliable than DOM walking because thread
    // authors don't always use the same HTML structure.
    final opText = opEl.text;

    // Developer: look for "Developer:" label anywhere in the OP text.
    String developer = result.developer;
    if (developer.isEmpty) {
      final devMatch = RegExp(
        r'^Developer[:\s]+(.+)$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(opText);
      if (devMatch != null) {
        developer = devMatch.group(1)?.trim() ?? '';
      }
    }
    // Fallback: last bracketed segment of the h1 title (e.g. "[DevName]").
    // This is a weak signal — only use it if the OP text gave us nothing.
    if (developer.isEmpty) {
      final titleEl = doc.querySelector('h1.p-title-value');
      final rawTitle = titleEl?.text.trim() ?? '';
      final devMatch = RegExp(r'\[([^\[\]]+)\]\s*$').firstMatch(rawTitle);
      if (devMatch != null) developer = devMatch.group(1)?.trim() ?? '';
    }

    // Synopsis: look for "Overview:" or "Synopsis:" labeled section.
    // Capture everything after the label until the next "Label:" header, a
    // XenForo BBCode tag line, or end-of-string.  Trim whitespace.
    String synopsis = result.synopsis;
    if (synopsis.isEmpty) {
      final synopsisMatch = RegExp(
        r'(?:Overview|Synopsis)[:\s]*\n?([\s\S]+?)(?=\n[A-Z][^\n:]{0,30}:|\n\[|\Z)',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(opText);
      if (synopsisMatch != null) {
        synopsis = synopsisMatch.group(1)?.trim() ?? '';
        // Cap to 1 200 chars so the UI doesn't overflow
        if (synopsis.length > 1200) synopsis = synopsis.substring(0, 1200).trimRight();
      }
    }

    final cover = imageUrls.isNotEmpty ? imageUrls.first : result.coverUrl;
    final screenshots = imageUrls.length > 1
        ? imageUrls.sublist(1).take(9).toList()
        : result.screenshotUrls;

    // ── Extract XenForo tag list ──────────────────────────────────────────
    // XenForo 2.x renders tags in a <ul class="js-tagList"> or <div class="tagList">
    // Each tag is an <a class="tagItem"> element.
    final tagEls = doc.querySelectorAll(
        '.js-tagList a.tagItem, '
        '.tagList a.tagItem, '
        '.js-tagList .tagItem, '
        '.tagList a, '
        'ul.listPlain--tagList a');
    final tags = tagEls
        .map((el) => el.text.trim())
        .where((t) =>
            t.isNotEmpty &&
            t.length < 60 &&
            !_xfMetaTags.contains(t.toLowerCase()))
        .toSet()
        .take(25)
        .toList();

    return MetadataResult(
      provider: result.provider,
      id: result.id,
      title: result.title,
      developer: developer,
      synopsis: synopsis,
      coverUrl: cover,
      screenshotUrls: screenshots,
      sourceUrl: result.sourceUrl,
      tags: tags.isNotEmpty ? tags : result.tags,
      releaseDate: result.releaseDate,
    );
  }

  // ── XenForo Login (F95Zone / LewdCorner) ──────────────────────────────────

  /// Log in to a XenForo-based site and return session cookies.
  /// Returns null on failure (wrong credentials, network error, etc.)
  static Future<Map<String, String>?> xenforoLogin({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      // 1) Fetch login page to get _xfToken
      final pageResp = await http
          .get(Uri.parse('$baseUrl/login/'), headers: _baseHeaders)
          .timeout(const Duration(seconds: 10));

      final doc = html_parser.parse(pageResp.body);
      final tokenEl = doc.querySelector('input[name="_xfToken"]');
      final xfToken = tokenEl?.attributes['value'] ?? '';

      final cookies = <String, String>{};
      _parseCookies(pageResp.headers['set-cookie'] ?? '', cookies);

      // 2) POST login
      final loginResp = await http.post(
        Uri.parse('$baseUrl/login/login'),
        headers: {
          ..._baseHeaders,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie':
              cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
          'Referer': '$baseUrl/login/',
          'Origin': baseUrl,
        },
        body: {
          'login': username,
          'password': password,
          '_xfToken': xfToken,
          'remember': '1',
        },
      ).timeout(const Duration(seconds: 15));

      _parseCookies(loginResp.headers['set-cookie'] ?? '', cookies);

      // Verify success: xf_user cookie must be non-empty and not '0'
      final xfUser = cookies['xf_user'] ?? '';
      if (xfUser.isEmpty || xfUser == '0') return null;
      return cookies;
    } catch (e) {
      debugPrint('XenForo login failed for $baseUrl: $e');
      return null;
    }
  }

  static void _parseCookies(String header, Map<String, String> into) {
    // Split on comma (each Set-Cookie header) then take first key=value
    for (final chunk in header.split(RegExp(r',(?=\s*\w+=)'))) {
      final segments = chunk.trim().split(';');
      if (segments.isEmpty) continue;
      final kv = segments.first.trim().split('=');
      if (kv.length < 2) continue;
      final key = kv[0].trim();
      final value = kv.sublist(1).join('=').trim();
      const skip = {'path', 'domain', 'expires', 'max-age', 'samesite'};
      if (key.isNotEmpty && !skip.contains(key.toLowerCase())) {
        into[key] = value;
      }
    }
  }

  // ── Image Download ─────────────────────────────────────────────────────────

  /// Download and save cover image and screenshots to [gameFolder]/.vnpf/.
  /// Respects [maxScreenshots] limit (default 9 = 3×3 grid).
  /// [scrapingService] is optional — when provided, images from authenticated
  /// domains (F95Zone, LewdCorner) are fetched via the WebView cookie store.
  static Future<void> downloadImages({
    required Directory gameFolder,
    required String coverUrl,
    required List<String> screenshotUrls,
    int maxScreenshots = 9,
    ScrapingService? scrapingService,
    void Function(int done, int total)? onProgress,
  }) async {
    final vnpfDir = Directory(p.join(gameFolder.path, '.vnpf'));
    vnpfDir.createSync(recursive: true);

    final shots = screenshotUrls.take(maxScreenshots).toList();
    final total = (coverUrl.isNotEmpty ? 1 : 0) + shots.length;
    int done = 0;

    // ── Download all images, writing to temp names first ─────────────────
    // We collect what was actually written before clearing old files, so a
    // failed re-download doesn't wipe the previous pack with nothing to show.
    final written = <File>[];

    if (coverUrl.isNotEmpty) {
      try {
        final bytes = await _fetchImageBytes(coverUrl, scrapingService);
        if (bytes != null && bytes.isNotEmpty) {
          final f = File(p.join(vnpfDir.path, 'cover_new${_ext(coverUrl)}'));
          await f.writeAsBytes(bytes);
          written.add(f);
        } else {
          debugPrint('Cover download returned no bytes: $coverUrl');
        }
      } catch (e) {
        debugPrint('Cover download failed ($coverUrl): $e');
      }
      onProgress?.call(++done, total);
    }

    for (var i = 0; i < shots.length; i++) {
      try {
        final bytes = await _fetchImageBytes(shots[i], scrapingService);
        if (bytes != null && bytes.isNotEmpty) {
          final f = File(p.join(vnpfDir.path, 'screenshot_new_${i + 1}${_ext(shots[i])}'));
          await f.writeAsBytes(bytes);
          written.add(f);
        } else {
          debugPrint('Screenshot ${i + 1} returned no bytes: ${shots[i]}');
        }
      } catch (e) {
        debugPrint('Screenshot ${i + 1} download failed (${shots[i]}): $e');
      }
      onProgress?.call(++done, total);
    }

    // ── Only clear old pack if at least one new image was downloaded ──────
    if (written.isEmpty) {
      debugPrint('downloadImages: no images downloaded — keeping existing pack');
      return;
    }

    // Delete old cover + screenshots
    try {
      for (final f in vnpfDir.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if ((name.startsWith('cover.') || name.startsWith('screenshot_')) &&
            !name.contains('_new')) {
          f.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('Image cleanup failed: $e');
    }

    // Rename _new files to final names
    int shotIdx = 1;
    for (final f in written) {
      final name = p.basename(f.path);
      final ext  = p.extension(f.path);
      final finalName = name.startsWith('cover_new')
          ? 'cover$ext'
          : 'screenshot_${shotIdx++}$ext';
      try {
        await f.rename(p.join(vnpfDir.path, finalName));
      } catch (e) {
        debugPrint('Rename failed for $name: $e');
      }
    }
  }

  /// Downloads image bytes. For authenticated domains (F95Zone / LewdCorner
  /// attachment CDNs) that require session cookies, falls back to fetching
  /// via the ScrapingService WebView cookie store using a JS fetch().
  static Future<List<int>?> _fetchImageBytes(
      String url, ScrapingService? scraping) async {
    // First: try a plain HTTP request (works for public CDNs, VNDB, itch.io)
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {
            ..._baseHeaders,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            'Referer': _refererFor(url),
          })
          .timeout(const Duration(seconds: 20));
      // Only accept the response if it's actually an image — servers that require
      // auth often return 200 + HTML login page instead of 403.
      final ct = resp.headers['content-type'] ?? '';
      if (resp.statusCode == 200 &&
          resp.bodyBytes.isNotEmpty &&
          ct.contains('image/')) {
        return resp.bodyBytes;
      }
      debugPrint('Image HTTP fetch: status=${resp.statusCode} content-type=$ct url=$url');
      // Fall through to WebView if scraping is available
      if (scraping == null) return null;
    } catch (e) {
      debugPrint('Image HTTP fetch error ($url): $e');
      if (scraping == null) return null;
    }

    // Fallback: use the WebView which carries session cookies.
    // IMPORTANT: we evaluate JS on the SAME ORIGIN as the image URL so the
    // fetch is same-origin (no CORS). XenForo sets cookies on .f95zone.to
    // (with leading dot), so the subdomain attachments.f95zone.to shares them.
    try {
      if (!scraping.isInitialized) return null;
      final js = '''
(async () => {
  try {
    const r = await fetch(${_jsString(url)}, {credentials: 'include'});
    if (!r.ok) return 'ERR:' + r.status;
    const ct = r.headers.get('content-type') || '';
    if (!ct.startsWith('image/')) return 'ERR:ct:' + ct;
    const buf = await r.arrayBuffer();
    const bytes = new Uint8Array(buf);
    const chunkSize = 8192;
    let bin = '';
    for (let i = 0; i < bytes.byteLength; i += chunkSize) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return btoa(bin);
  } catch(e) { return 'ERR:' + String(e); }
})()
''';
      // Evaluate on the image's own origin so the fetch is same-origin (no CORS).
      final base = _siteBaseUrl(url);
      debugPrint('WebView image fetch: base=$base url=$url');
      final result = await scraping.evalOnPage(base, js);
      if (result is String) {
        if (result.startsWith('ERR:')) {
          debugPrint('WebView image fetch JS error ($url): $result');
          return null;
        }
        if (result.isNotEmpty) {
          return base64Decode(result);
        }
      }
      debugPrint('WebView image fetch returned no data for $url');
    } catch (e) {
      debugPrint('WebView image fetch failed ($url): $e');
    }
    return null;
  }

  static String _siteBaseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return url;
    }
  }

  static String _refererFor(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return '';
    }
  }

  static String _jsString(String s) {
    // Safely escape a string for embedding in a JS string literal.
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }

  static String _ext(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    return '.jpg';
  }
}
