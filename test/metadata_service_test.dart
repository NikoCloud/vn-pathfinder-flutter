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
  test('an exact title outranks a chat thread that shares its tags', () async {
    const html = '''
<html data-logged-in="true"><body><ol>
<li class="block-row"><h3 class="contentRow-title"><a href="/threads/chat.1/">The Official Off-Topic Thread [Plus] [Studio]</a></h3></li>
<li class="block-row"><h3 class="contentRow-title"><a href="/threads/game.2/">Game Name [v1.0] [Studio]</a></h3></li>
</ol></body></html>''';
    final results = await MetadataService.searchLewdCorner('game name', FakeScraping(html));
    expect(results.first.sourceUrl, endsWith('/threads/game.2/'));
    expect(results.length, 2);
  });

  test('images hidden from the account are reported', () async {
    String page(String body) => _page(h1: 'Game [v1] [Studio]', post: '''
<article class="message message--post"><div class="message-userContent">
<article class="message-body"><div class="bbWrapper">$body<b>Overview</b>: A game.<br />
</div></article></div></article>''');
    const hidden = '<div class="messageHide messageHide--attach">You must be registered to see attachments</div>';

    final locked = await MetadataService.fetchThreadDetails(_seed('lewdcorner'), FakeScraping(page(hidden)));
    expect(locked.imagesLocked, isTrue);
    final open = await MetadataService.fetchThreadDetails(_seed('lewdcorner'), FakeScraping(page('')));
    expect(open.imagesLocked, isFalse);
  });

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
<b>Developer</b>: Leonave - <a href="https://www.patreon.com/leonave">Patreon</a> - <a href="https://discord.gg/abc">Discord</a><br />
<b>Other Games</b>: <a href="https://f95zone.to/threads/tale-of-eros-ch-4-alorth.25093/">Tale of Eros</a> - <a href="https://f95zone.to/sam/latest_alpha/#/cat=games/page=1/creator=Leonave">Link</a><br />
<a href="https://attachments.f95zone.to/shot1.jpg?h=2"><img src="https://attachments.f95zone.to/thumb/shot1.jpg"></a>
</div></article></div></article>''',
      );
      final r = await MetadataService.fetchThreadDetails(_seed('f95zone'), FakeScraping(html));
      expect(r.title, 'Frozen Past');
      expect(r.developer, 'Leonave');
      expect(r.version, 'v0.43');
      expect(r.synopsis, 'Frozen Past is set in the near future.\nBut is it worth it?');
      expect(r.coverUrl, 'https://attachments.f95zone.to/banner.png?h=1');
      expect(r.screenshotUrls, ['https://attachments.f95zone.to/shot1.jpg?h=2']);
      expect(r.supportLinks, ['https://www.patreon.com/leonave', 'https://discord.gg/abc']);
      expect(r.otherGames, [
        (title: 'Tale of Eros', url: 'https://f95zone.to/threads/tale-of-eros-ch-4-alorth.25093/'),
      ]);
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
  <dl class="pairs pairs--customField"><dt>Developer Links</dt><dd><div class="bbWrapper"><a href="https://subscribestar.adult/elfieeven">SubscribeStar</a> - <a href="https://discord.gg/abc">Discord</a></div></dd></dl>
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
      expect(r.supportLinks, ['https://subscribestar.adult/elfieeven', 'https://discord.gg/abc']);
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

  group('itch.io ranking, relevance, and page parsing', () {
    test('cleanItchTitle strips (NSFW), [18+], and trailing author suffixes', () {
      expect(MetadataService.cleanItchTitle('Neko Paradise (NSFW) by Alorth'), 'Neko Paradise');
      expect(MetadataService.cleanItchTitle('Tale of Eros(NSFW)'), 'Tale of Eros');
      expect(MetadataService.cleanItchTitle('Some Game [18+] [v0.2.1]'), 'Some Game');
    });

    test('rankItchResults and isRelevantItchMatch prefer matching creator/title and reject unrelated jam games', () {
      const jamWrongTitle = MetadataResult(
        provider: 'itchio',
        id: '1',
        title: 'Neko No Sentouki',
        developer: 'skredjun',
        sourceUrl: 'https://skredjun.itch.io/neko-no-sentouki',
      );
      const jamSameTitleWrongDev = MetadataResult(
        provider: 'itchio',
        id: '2',
        title: 'Light Of My Life',
        developer: 'LightOfMyLife, ATRS',
        sourceUrl: 'https://lightofmylife.itch.io/light-of-my-life',
      );
      const translationMod = MetadataResult(
        provider: 'itchio',
        id: '3',
        title: 'ETERNUM — Tradução PT-BR',
        developer: 'ushinyu',
        sourceUrl: 'https://ushinyu.itch.io/eternum-ptbr',
      );
      const realNeko = MetadataResult(
        provider: 'itchio',
        id: '4',
        title: 'Neko Paradise',
        developer: 'Alorth',
        sourceUrl: 'https://alorth.itch.io/neko-paradise',
      );

      expect(
        MetadataService.isRelevantItchMatch(
          jamWrongTitle,
          query: 'Neko Paradise',
          developer: 'Alorth',
        ),
        isFalse,
      );
      expect(
        MetadataService.isRelevantItchMatch(
          jamSameTitleWrongDev,
          query: 'Light of My Life',
          developer: 'Naughty Road Productions',
        ),
        isFalse,
      );
      expect(
        MetadataService.isRelevantItchMatch(
          translationMod,
          query: 'Eternum',
          developer: 'Caribdis',
        ),
        isFalse,
      );
      expect(
        MetadataService.isRelevantItchMatch(
          realNeko,
          query: 'Neko Paradise',
          developer: 'Alorth',
        ),
        isTrue,
      );

      final ranked = MetadataService.rankItchResults(
        [jamWrongTitle, realNeko],
        query: 'Neko Paradise',
        developer: 'Alorth',
      );
      expect(ranked.first.sourceUrl, 'https://alorth.itch.io/neko-paradise');
    });

    test('parseItchGamePage extracts Plot synopsis, og:image cover, screenshots, rating, tags, and support links', () {
      const html = '''
<!DOCTYPE html><html><head>
<meta property="og:image" content="https://img.itch.zone/cover/original/full.png"/>
<meta name="twitter:title" content="Eternum (NSFW) by Caribdis"/>
</head><body>
<h1 class="game_title">Eternum (NSFW)</h1>
<div class="formatted_description">
  <h2><a href="https://www.patreon.com/onceinalifetime">PATREON</a> | <a href="https://subscribestar.adult/caribdis">SUBSCRIBESTAR</a></h2>
  <h2>________________________</h2>
  <h2>Plot</h2>
  <p>You are moving with your best friend to the city of Kredon.</p>
  <p>Thousands of servers form the network of Eternum.</p>
  <h2>About me</h2>
  <p>The game currently has over 11,000 renders.</p>
</div>
<div class="screenshot_list">
  <a data-image_lightbox="true" href="https://img.itch.zone/shot1/original/1.jpg"><img data-lazy_src="https://img.itch.zone/shot1/thumb/1.jpg"/></a>
  <a data-image_lightbox="true" href="https://img.itch.zone/shot2/original/2.jpg"><img src="https://img.itch.zone/shot2/thumb/2.jpg"/></a>
</div>
<div class="info_panel_wrapper"><table><tbody>
  <tr><td>Updated</td><td><abbr title="03 November 2026 @ 12:37 UTC">8 days ago</abbr></td></tr>
  <tr><td>Rating</td><td><div class="aggregate_rating"><div itemprop="ratingValue" content="4.9"></div></div></td></tr>
  <tr><td>Author</td><td><a href="https://caribdis.itch.io">Caribdis</a></td></tr>
  <tr><td>Genre</td><td><a href="https://itch.io/games/genre-visual-novel">Visual Novel</a></td></tr>
  <tr><td>Tags</td><td><a href="#">3D</a>, <a href="#">Romance</a>, <a href="#">Ren'Py</a></td></tr>
</tbody></table></div>
</body></html>''';
      const seed = MetadataResult(
        provider: 'itchio',
        id: 'https://caribdis.itch.io/eternum',
        title: 'Eternum',
        developer: '',
        sourceUrl: 'https://caribdis.itch.io/eternum',
      );
      final parsed = MetadataService.parseItchGamePage(seed, html);
      expect(parsed.title, 'Eternum');
      expect(parsed.developer, 'Caribdis');
      expect(parsed.coverUrl, 'https://img.itch.zone/cover/original/full.png');
      expect(parsed.screenshotUrls, [
        'https://img.itch.zone/shot1/original/1.jpg',
        'https://img.itch.zone/shot2/original/2.jpg',
      ]);
      expect(parsed.previewUrls['https://img.itch.zone/shot1/original/1.jpg'],
          'https://img.itch.zone/shot1/thumb/1.jpg');
      expect(parsed.rating, 4.9);
      expect(parsed.tags, ['3D', 'Romance']);
      expect(
        parsed.synopsis,
        'You are moving with your best friend to the city of Kredon.\n\n'
        'Thousands of servers form the network of Eternum.',
      );
      expect(parsed.supportLinks, [
        'https://caribdis.itch.io',
        'https://www.patreon.com/onceinalifetime',
        'https://subscribestar.adult/caribdis',
      ]);
    });
  });
}
