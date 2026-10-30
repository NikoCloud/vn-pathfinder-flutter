// Regression tests for the forum scrapers, using small synthetic pages that
// mimic each site's markup as of 2026-10 (no real pages or account data).
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/services/scraping_service.dart';

/// Serves canned HTML instead of driving the WebView.
class FakeScraping extends ScrapingService {
  final String html;
  FakeScraping(this.html);

  @override
  Future<String> getString(String url) async => html;
}

MetadataResult _seed(String provider) => MetadataResult(
      provider: provider,
      id: 'x',
      title: '(seed)',
      developer: '',
      sourceUrl: 'https://example.test/threads/x.1/',
    );

String _page({required String h1, required String post, bool loggedIn = true}) => '''
<html data-logged-in="$loggedIn"><body>
<h1 class="p-title-value">$h1</h1>
$post
</body></html>''';

void main() {
  group('fetchThreadDetails', () {
    test('F95-style post: synopsis keeps "z", stops at the next label, developer drops links', () async {
      final html = _page(
        h1: '<span class="label">Ren\'Py</span> Frozen Past [v0.43] [Leonave]',
        post: '''
<article class="message message--post"><div class="message-userContent">
<article class="message-body"><div class="bbWrapper">
<div class="bbImageWrapper js-lbImage" data-src="https://attachments.f95zone.to/banner.png?h=1"><img src="https://attachments.f95zone.to/thumb/banner.png"></div>
<b>Overview</b>:<br />
Frozen Past is set in the near future.<br />
But is it worth it?​<br /><b>Thread Updated</b>: 2021-09-21<br />
<b>Developer</b>: Leonave - <a href="#">Patreon</a> - <a href="#">Discord</a><br />
<a href="https://attachments.f95zone.to/shot1.jpg?h=2"><img src="https://attachments.f95zone.to/thumb/shot1.jpg"></a>
</div></article></div></article>''',
      );
      final r = await MetadataService.fetchThreadDetails(_seed('f95zone'), FakeScraping(html));
      expect(r.title, 'Frozen Past');
      expect(r.developer, 'Leonave');
      expect(r.synopsis, 'Frozen Past is set in the near future.\nBut is it worth it?');
      expect(r.coverUrl, 'https://attachments.f95zone.to/banner.png?h=1');
      expect(r.screenshotUrls, ['https://attachments.f95zone.to/shot1.jpg?h=2']);
    });

    test('LewdCorner-style post: reads the body, not the custom fields above it', () async {
      final html = _page(
        h1: '<i class="fa--xf thread_type--discussion"><svg><title>discussion</title></svg></i> '
            '<span class="label">VN</span> Thirty Seconds [v0.1.1] [ElfiEven]',
        post: '''
<article class="message message--post"><div class="message-userContent">
<div class="message-fields message-fields--before">
  <dl class="pairs pairs--customField"><dt>Developer Name</dt><dd><div class="bbWrapper">ElfieEven</div></dd></dl>
  <dl class="pairs pairs--customField"><dt>Release Date</dt><dd>Aug 29, 2025</dd></dl>
  <dl class="pairs pairs--customField"><dt>Developer Links</dt><dd><div class="bbWrapper">Discord</div></dd></dl>
</div>
<article class="message-body"><div class="bbWrapper">
Overview:<br />
It seemed like such an easy decision.<br />
<a href="https://lewdcorner.com/attachments/title3-png.864396/"><img src="https://lewdcorner.com/data/attachments/860/860843.jpg" srcset="https://lewdcorner.com/data/attachments/860/2x/860843.jpg 2x"></a>
<a href="https://lewdcorner.com/attachments/shot1-png.855056/"><img src="https://lewdcorner.com/data/attachments/851/851570.jpg"></a>
View attachment Trailer.mp4<br />
<div class="bbCodeSpoiler">
\t\t\tSpoiler: Genre:<br />3dcg, harem
</div></div></article></div></article>''',
      );
      final r = await MetadataService.fetchThreadDetails(_seed('lewdcorner'), FakeScraping(html));
      expect(r.title, 'Thirty Seconds');
      expect(r.developer, 'ElfieEven');
      expect(r.releaseDate, 'Aug 29, 2025');
      expect(r.synopsis, 'It seemed like such an easy decision.');
      expect(r.coverUrl, 'https://lewdcorner.com/attachments/title3-png.864396/');
      expect(r.screenshotUrls, ['https://lewdcorner.com/attachments/shot1-png.855056/']);
      // Attachment pages need a login, so previews use the public thumbnails.
      expect(r.previewUrls, {
        'https://lewdcorner.com/attachments/title3-png.864396/':
            'https://lewdcorner.com/data/attachments/860/2x/860843.jpg',
        'https://lewdcorner.com/attachments/shot1-png.855056/':
            'https://lewdcorner.com/data/attachments/851/851570.jpg',
      });
    });

    test("Azkosel's Corner-style article post: wrapper images and icon-drawn spoiler label", () async {
      final html = _page(
        h1: '<span class="label">Ren\'Py</span> Club Detention [v0.097] [Yorma86]',
        post: '''
<article class="message message--article"><div class="message-userContent">
<div class="message-fields message-fields--before">
  <dl class="pairs pairs--customField"><dt>Developer/Studio</dt><dd>Yorma86</dd></dl>
</div>
<article class="message-body"><div class="bbWrapper">
<div class="bbImageWrapper js-lbImage" data-src="https://img3.pixhost.cc/images/cover.jpg"><img src="https://img3.pixhost.cc/images/cover.jpg" class="bbImage"></div>
Overview:<br />
As a former disgraced teacher, you are given one last chance.<br />
​<br />
<div class="bbCodeSpoiler"><span class="bbCodeSpoiler-button-title"></span>: Genre:<br />3dcg, Corruption</div>
<div class="bbImageWrapper js-lbImage" data-src="https://img3.pixhost.cc/images/shot1.jpg"><img src="https://img3.pixhost.cc/images/shot1.jpg" class="bbImage"></div>
</div></article></div></article>''',
      );
      final r = await MetadataService.fetchThreadDetails(_seed('azc'), FakeScraping(html));
      expect(r.title, 'Club Detention');
      expect(r.developer, 'Yorma86');
      expect(r.synopsis, 'As a former disgraced teacher, you are given one last chance.');
      expect(r.coverUrl, 'https://img3.pixhost.cc/images/cover.jpg');
      expect(r.screenshotUrls, ['https://img3.pixhost.cc/images/shot1.jpg']);
    });
  });

  test('folder names split into searchable titles without changing the library key', () {
    final (baseKey, version, display) = parseFolderName('AFamilyVenture-0.5-pc');
    expect(display, 'A Family Venture');
    expect(version, '0.5');
    expect(baseKey, 'afamilyventure'); // playtime, tags etc. are keyed on this
    expect(parseFolderName('HTMLGame').$3, 'HTML Game');
  });

  group('forum search', () {
    String results(List<String> titles, {bool loggedIn = true}) => '''
<html data-logged-in="$loggedIn"><body><ol>
${titles.map((t) => '<li class="block-row"><h3 class="contentRow-title"><a href="/threads/${t.hashCode}/">$t</a></h3></li>').join('\n')}
</ol></body></html>''';

    test('game threads ([version] [developer]) rank above stray threads', () async {
      final found = await MetadataService.searchAzkosel(
        'club detention',
        FakeScraping(results(['club-detention', '<span class="label">Ren\'Py</span> Club Detention [v0.097] [Yorma86]'])),
      );
      expect(found.map((r) => r.title), ['Club Detention', 'club-detention']);
    });

    test('a logged-out members-only search reports the login problem', () async {
      expect(
        MetadataService.searchF95Zone('frozen past', FakeScraping(results([], loggedIn: false))),
        throwsA(isA<ScrapingException>()
            .having((e) => e.message, 'message', contains('Not logged in to F95Zone'))),
      );
    });

    test('LewdCorner searches work logged out, so no results is just no results', () async {
      final found = await MetadataService.searchLewdCorner(
        'nothing', FakeScraping(results([], loggedIn: false)));
      expect(found, isEmpty);
    });
  });
}
