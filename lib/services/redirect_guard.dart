/// Keeps the download browser on the file host (#47). Most hosts' Download
/// button also fires an ad, which takes over the page; once a host page is
/// showing, a jump to an unrelated site is sent back to the last host page.
/// The forums' own pages (a masked link, say) pass you on to whatever host
/// they lead to. Kept free of the browser so it can be tested on its own.
class RedirectGuard {
  String _home = '';
  String _lastGood = '';
  final _returns = <DateTime>[];

  /// The page last stopped, for "Go there anyway". Null when nothing was.
  String? blocked;

  /// A new start: [address] is the page the Get sheet opened.
  void reset(String address) {
    _home = siteOf(address);
    _lastGood = address;
    _returns.clear();
    blocked = null;
  }

  /// Called with each page the browser shows. Returns the address to go back
  /// to when [url] is a jump away from the host, otherwise null.
  String? onUrl(String url, {DateTime? now}) {
    final site = siteOf(url);
    if (site.isEmpty) return null; // about:blank and the like
    if (_home.isEmpty || site == _home || isForumSite(_home) || isForumSite(site)) {
      _home = site;
      _lastGood = url;
      blocked = null;
      return null;
    }
    blocked = url;
    // A page that sends you away every time it loads would loop: after three
    // returns in ten seconds, stop and leave it to the person.
    final t = now ?? DateTime.now();
    _returns.removeWhere((r) => t.difference(r) > const Duration(seconds: 10));
    if (_returns.length >= 3) return null;
    _returns.add(t);
    return _lastGood;
  }

  /// "Go there anyway": [url]'s site becomes the one to stay on.
  void allow(String url) {
    _home = siteOf(url);
    _lastGood = url;
    _returns.clear();
    blocked = null;
  }
}

/// The site an address belongs to, without subdomains: "dl3.example.com" and
/// "www.example.com" are both "example.com"; "files.example.co.uk" is
/// "example.co.uk". Empty for anything that isn't a web page.
String siteOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return '';
  final host = uri.host.toLowerCase();
  if (host.isEmpty || RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':')) return host;
  final labels = host.split('.');
  if (labels.length <= 2) return host;
  final second = labels[labels.length - 2];
  final countryPair = labels.last.length == 2 && const {'co', 'com', 'net', 'org', 'ac', 'gov', 'edu'}.contains(second);
  return labels.sublist(labels.length - (countryPair ? 3 : 2)).join('.');
}

/// The forums whose pages hand you on to a file host.
bool isForumSite(String site) => site == 'f95zone.to' || site == 'lewdcorner.com' || site.contains('azkosel');

/// Mega's site saves files from inside the page, so the browser never reports
/// them as downloads; the download folder is watched instead.
bool isMegaSite(String site) => site == 'mega.nz' || site == 'mega.io' || site == 'mega.co.nz';
