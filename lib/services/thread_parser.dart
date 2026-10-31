import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// A download link in a game's thread.
class ThreadLink {
  /// The file host as the thread labels it ("MEGA"), or "Download page" for a
  /// link that leads to the site's own page of hosts.
  final String host;
  final String url;

  /// "Windows", "Mac", "Android", "Extras" and so on. Empty when the thread
  /// doesn't say.
  final String platform;

  const ThreadLink({required this.host, required this.url, this.platform = ''});
}

/// One version's notes from a thread's changelog.
class ThreadChange {
  final String version;
  final List<String> notes;
  const ThreadChange(this.version, this.notes);
}

/// What the game page reads out of a thread, beyond what Fetch Metadata saves.
class ThreadDownloads {
  final List<ThreadLink> links;
  final List<ThreadChange> changes;
  const ThreadDownloads({this.links = const [], this.changes = const []});

  List<String> get platforms {
    final seen = <String>[];
    for (final link in links) {
      if (!seen.contains(link.platform)) seen.add(link.platform);
    }
    return seen;
  }
}

class ThreadParser {
  static const _hosts = [
    'mega.nz', 'mega.co.nz', 'pixeldrain.com', 'mediafire.com', 'drive.google.com',
    'datanodes.to', 'buzzheavier.com', 'mixdrop', 'gofile.io', 'workupload.com',
    'vikingfile.com', 'katfile.com', 'rapidgator.net', '1fichier.com', 'uploadhaven.com',
    'krakenfiles.com', 'trashbytes.net', 'send.cm', 'qiwi.gg', 'nopy.to', 'filemirage.com',
    'anonfiles', 'bowfile.com', 'racaty', 'ranoz.gg', 'akirabox.com',
  ];

  /// The sites' own gateways to a file host.
  static final _gateway = RegExp(r'/(?:dl|masked)/', caseSensitive: false);

  static final _platform = RegExp(
    r'(win(?:dows)?(?:\s*/\s*linux)?|pc|linux|mac(?:\s*os)?|osx|android|ios|extras?|walkthrough|mods?|patch(?:es)?)\s*(?:\(.*?\))?\s*[:\-–]\s*$',
    caseSensitive: false,
  );

  static ThreadDownloads parse(String html, String pageUrl) {
    final doc = html_parser.parse(html);
    final article = doc.querySelector('article.message--post, article.message--article') ??
        doc.querySelector('article.message');
    final post = article?.querySelector('.message-body .bbWrapper') ??
        article?.querySelector('div.bbWrapper') ??
        doc.querySelector('div.bbWrapper');
    if (post == null) return const ThreadDownloads();
    return ThreadDownloads(links: _links(post, pageUrl), changes: _changes(post));
  }

  static List<ThreadLink> _links(Element post, String pageUrl) {
    final base = Uri.tryParse(pageUrl);
    final links = <ThreadLink>[];
    final seen = <String>{};
    var text = '';
    var platform = '';

    void walk(Node node) {
      if (node is Text) {
        text = '$text${node.text}';
        if (text.length > 200) text = text.substring(text.length - 200);
        final m = _platform.firstMatch(text.trimRight());
        if (m != null) platform = _platformName(m.group(1)!);
        return;
      }
      if (node is Element) {
        final name = node.localName;
        if (name == 'br' || name == 'div' || name == 'p') text = '$text\n';
        if (name == 'a') {
          final href = (node.attributes['href'] ?? '').trim();
          final url = href.isEmpty ? '' : (base?.resolve(href).toString() ?? href);
          final label = node.text.trim();
          if (_isDownload(url) && seen.add(url)) {
            links.add(ThreadLink(host: _hostLabel(label, url), url: url, platform: platform));
          }
          text = '$text ';
          return;
        }
      }
      node.nodes.forEach(walk);
    }

    walk(post);
    return links;
  }

  static bool _isDownload(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    if (_gateway.hasMatch(uri.path)) return true;
    final host = uri.host.toLowerCase();
    return _hosts.any(host.contains);
  }

  static String _hostLabel(String label, String url) {
    final tidy = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (tidy.isNotEmpty && tidy.length <= 24 && !tidy.startsWith('http')) return tidy.toUpperCase();
    final uri = Uri.tryParse(url);
    if (uri != null && _hosts.any(uri.host.toLowerCase().contains)) {
      return uri.host.replaceFirst('www.', '').split('.').first.toUpperCase();
    }
    return 'Download page';
  }

  static String _platformName(String raw) {
    final p = raw.toLowerCase();
    if (p.startsWith('win') || p == 'pc') return 'Windows';
    if (p.startsWith('mac') || p == 'osx') return 'Mac';
    if (p.startsWith('linux')) return 'Linux';
    if (p.startsWith('android')) return 'Android';
    if (p.startsWith('ios')) return 'iOS';
    return 'Extras';
  }

  static final _changelogTitle = RegExp(r"change\s*-?log|what'?s new|update\s*notes", caseSensitive: false);
  static final _versionLine = RegExp(
    r'^[\s\-–•*\[(]*(?:version|ver\.?|v\.?|build|episode|ep\.?|chapter|ch\.?|part|season)?\s*\.?\s*(\d+(?:[._]\d+)*[a-z]?)\b[\])\s:–\-]*$',
    caseSensitive: false,
  );

  static List<ThreadChange> _changes(Element post) {
    for (final spoiler in post.querySelectorAll('.bbCodeSpoiler')) {
      final title = spoiler.querySelector('.bbCodeSpoiler-button')?.text ?? '';
      if (!_changelogTitle.hasMatch(title)) continue;
      final body = spoiler.querySelector('.bbCodeSpoiler-content');
      if (body != null) return _splitChanges(_lines(body));
    }
    return const [];
  }

  static List<String> _lines(Element body) {
    final buffer = StringBuffer();
    void walk(Node node) {
      if (node is Text) {
        buffer.write(node.text);
      } else if (node is Element) {
        final name = node.localName;
        if (name == 'br' || name == 'li' || name == 'p' || name == 'div') buffer.write('\n');
        node.nodes.forEach(walk);
        if (name == 'li' || name == 'p' || name == 'div') buffer.write('\n');
      }
    }

    walk(body);
    return buffer.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  /// Newest first, the way threads write them. Notes before the first version
  /// heading have no version to belong to, so they're kept under ''.
  static List<ThreadChange> _splitChanges(List<String> lines) {
    final changes = <ThreadChange>[];
    var version = '';
    var notes = <String>[];
    void flush() {
      if (notes.isNotEmpty || version.isNotEmpty) changes.add(ThreadChange(version, notes));
    }

    for (final line in lines) {
      final m = _versionLine.firstMatch(line);
      if (m != null) {
        flush();
        version = m.group(1)!;
        notes = [];
      } else {
        notes.add(line.replaceFirst(RegExp(r'^[\-–•*]+\s*'), ''));
      }
    }
    flush();
    return changes;
  }
}
