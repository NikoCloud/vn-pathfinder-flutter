// How Fetch Metadata combines sources (#43): the tag key, link defaults and
// the same-game check. Invented games, developers and addresses throughout.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/fetch_merge.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scraping_service.dart';
import 'package:vn_pathfinder/utils/formatters.dart';

class _FakeScraping extends ScrapingService {
  final String html;
  _FakeScraping(this.html);

  @override
  Future<String> getString(String url) async => html;
}

MetadataResult _result(String provider, String title, String developer, {List<String> tags = const []}) =>
    MetadataResult(
      provider: provider,
      id: provider,
      title: title,
      developer: developer,
      sourceUrl: 'https://example.test/$provider',
      tags: tags,
    );

void main() {
  group('tag key', () {
    test('case, spaces and symbols are ignored', () {
      expect(tagKey('Male Protagonist'), 'maleprotagonist');
      expect(tagKey('male-protagonist'), 'maleprotagonist');
      expect(tagKey('male_protagonist'), 'maleprotagonist');
      expect(tagKey(' MALE  PROTAGONIST! '), 'maleprotagonist');
      expect(tagKey('3D Game'), '3dgame');
    });

    test('letters in any script are kept', () {
      expect(tagKey('寝取られ'), '寝取られ');
      expect(tagKey('Romance — Español'), 'romanceespañol');
      expect(tagKey('Ménage à trois'), 'ménageàtrois');
      expect(tagKey('★ ♥ !!'), isEmpty);
    });

    test('tags from several sources combine, spelled as the first source spells them', () {
      final merged = mergeTags([
        ('VNDB', ['Male Protagonist', 'Romance', '★']),
        ('F95Zone', ['male protagonist', 'Sandbox', 'romance']),
        ('LewdCorner', ['寝取られ', 'Sand-box']),
      ]);
      expect(merged.map((t) => t.tag), ['Male Protagonist', 'Romance', 'Sandbox', '寝取られ']);
      expect(merged.first.sources, ['VNDB', 'F95Zone']);
      expect(merged[2].sources, ['F95Zone', 'LewdCorner']);
    });
  });

  group('creator links', () {
    test("a post with other people's links next to the developer's saves only the developer's", () async {
      const html = '''
<html data-logged-in="true"><body>
<h1 class="p-title-value">Lantern Row [v0.3] [Tidewater Games]</h1>
<article class="message message--post"><div class="message-userContent">
<article class="message-body"><div class="bbWrapper">
<b>Overview</b>: A quiet game about a lighthouse.<br />
<b>Developer</b>: Tidewater Games - <a href="https://www.patreon.com/tidewatergames">Patreon</a><br />
<b>Mod</b>: walkthrough mod by Pebblesmith - support him on <a href="https://ko-fi.com/pebblesmith">Ko-fi</a><br />
Uploaded by Gullwing, come chat on <a href="https://discord.gg/gullwing">my Discord</a><br />
Translated by Seafoam: <a href="https://subscribestar.adult/seafoam">SubscribeStar</a><br />
</div></article></div></article>
</body></html>''';
      final seed = _result('f95zone', '(seed)', '');
      final r = await MetadataService.fetchThreadDetails(seed, _FakeScraping(html));

      expect(r.supportLinks, ['https://www.patreon.com/tidewatergames']);
      final rows = linkRowsFor('F95Zone', r.foundLinks);
      // The modder's line is skipped as a mod line; the uploader's and the
      // translator's links are shown, unticked.
      expect({for (final row in rows) row.url: row.where}, {
        'https://www.patreon.com/tidewatergames': LinkWhere.developerLine,
        'https://discord.gg/gullwing': LinkWhere.elsewhere,
        'https://subscribestar.adult/seafoam': LinkWhere.elsewhere,
      });
      final ticked = rows.where((row) => linkStartsTicked(row, sourceMatches: true)).toList();
      expect(ticked.map((row) => row.url), ['https://www.patreon.com/tidewatergames']);
      expect(ticked.single.where, LinkWhere.developerLine);

      final saved = chosenLinks(rows, (row) => linkStartsTicked(row, sourceMatches: true));
      expect(saved, [(label: 'Patreon', url: 'https://www.patreon.com/tidewatergames')]);
      expect(saved.any((l) => l.label == 'Discord'), isFalse, reason: "the uploader's Discord isn't discord_url");
    });

    test('nothing starts ticked from a source that is another game', () {
      final rows = linkRowsFor('VNDB', [(url: 'https://www.patreon.com/elsewhere', where: LinkWhere.creatorRecord)]);
      expect(linkStartsTicked(rows.single, sourceMatches: false), isFalse);
      expect(linkStartsTicked(rows.single, sourceMatches: true), isTrue);
    });

    test('one link per platform, the higher-priority ticked row winning', () {
      final rows = [
        ...linkRowsFor('VNDB', [(url: 'https://www.patreon.com/first', where: LinkWhere.creatorRecord)]),
        ...linkRowsFor('F95Zone', [
          (url: 'https://www.patreon.com/second', where: LinkWhere.developerLine),
          (url: 'https://discord.gg/team', where: LinkWhere.developerLinks),
        ]),
      ];
      final saved = chosenLinks(rows, (_) => true);
      expect(saved, [
        (label: 'Patreon', url: 'https://www.patreon.com/first'),
        (label: 'Discord', url: 'https://discord.gg/team'),
      ]);
      // Unticking the first lets the next one on that platform in.
      final next = chosenLinks(rows, (row) => row.url != 'https://www.patreon.com/first');
      expect(next.first.url, 'https://www.patreon.com/second');
    });
  });

  group('same-game check', () {
    test('the anchor is the highest-priority result that is this game', () {
      final vndbOther = _result('vndb', 'Lantern Row Remastered', 'Someone Else');
      final f95 = _result('f95zone', 'Lantern Row', 'Tidewater Games');
      final anchor = anchorResult([vndbOther, f95], title: 'LanternRow');
      expect(anchor, same(f95), reason: 'a folder name squashed together still matches');
      expect(passesSameGame(vndbOther, anchor), isFalse);
      expect(passesSameGame(f95, anchor), isTrue);
    });

    test("a known developer has to match too, and the search text counts as the game's name", () {
      final r = _result('f95zone', 'Lantern Row', 'Tidewater Games Studio');
      expect(matchesLocalGame(r, title: 'LR', query: 'Lantern Row', developer: 'Tidewater Games'), isTrue);
      expect(matchesLocalGame(r, title: 'Lantern Row', developer: 'Harbour Lights'), isFalse);
      expect(matchesLocalGame(r, title: 'Different Game'), isFalse);
    });

    test('a source that picked a different game adds no tags by default', () {
      final vndb = _result('vndb', 'Lantern Row', 'Tidewater Games', tags: ['Romance']);
      final lc = _result('lewdcorner', 'Lantern Row', 'Night Owl Studio', tags: ['Horror']);
      final anchor = anchorResult([vndb, lc], title: 'Lantern Row');
      final merged = mergeTags([
        for (final (label, r) in [('VNDB', vndb), ('LewdCorner', lc)])
          if (passesSameGame(r, anchor)) (label, r.tags),
      ]);
      expect(merged.map((t) => t.tag), ['Romance']);
    });

    test('with nothing clearly this game, nothing starts ticked', () {
      final a = _result('vndb', 'Another Title', 'Tidewater Games');
      expect(anchorResult([a], title: 'Lantern Row'), isNull);
      expect(passesSameGame(a, null), isFalse);
    });
  });
}
