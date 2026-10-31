// Developer names without the links and page text scraped along with them.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scraping_service.dart';
import 'package:vn_pathfinder/utils/formatters.dart';

class FakeScraping extends ScrapingService {
  final String html;
  FakeScraping(this.html);

  @override
  Future<String> getString(String url) async => html;
}

Future<String> developerFrom({required String h1, required String line}) =>
    developerFromPost(h1: h1, post: '<b>Developer</b>: $line<br />');

Future<String> developerFromPost({required String h1, required String post}) async {
  final html = '''
<html data-logged-in="true"><body>
<h1 class="p-title-value">$h1</h1>
<article class="message message--post"><div class="message-userContent">
<article class="message-body"><div class="bbWrapper">
<b>Overview</b>:<br />A game.<br />
$post
<b>Censored</b>: No<br />
</div></article></div></article>
</body></html>''';
  final seed = const MetadataResult(
      provider: 'f95zone', id: 'x', title: '(seed)', developer: '', sourceUrl: 'https://example.test/');
  return (await MetadataService.fetchThreadDetails(seed, FakeScraping(html))).developer;
}

void main() {
  group('cleanDeveloperName', () {
    const cases = {
      // Link labels run straight into the name
      'Quonix Patreon': 'Quonix',
      'Vixwood Games Patreon': 'Vixwood Games',
      'Fallen Angel Productions Subscribestar': 'Fallen Angel Productions',
      'Ivory Shade Steam': 'Ivory Shade',
      'Sweet Home Alabama Inc. Patreon': 'Sweet Home Alabama Inc.',
      'B7 Patreon': 'B7',
      'Quonix Patreon itch.io': 'Quonix',
      'Quonix (Patreon)': 'Quonix',
      // Separated links
      'Leonave - Patreon - Discord': 'Leonave',
      'Quonix Patreon - Itch.io - Discord': 'Quonix',
      'Quonix | Patreon': 'Quonix',
      'Patreon - Quonix': 'Quonix',
      // Forum search-row text saved by older versions
      'PPanGames\n\t\t\t\t\tThread\n\t\t\t\t\tSep 12, 2020\n\t\t\t\t\tReplies: 2,739': 'PPanGames',
      // Already clean, and must stay that way
      'Dream Cloud Entertainment': 'Dream Cloud Entertainment',
      'JD-NaughtyAtticGaming': 'JD-NaughtyAtticGaming',
      'Some Studio': 'Some Studio',
      // Nothing left to keep, so don't blank it
      'Steam': 'Steam',
      '': '',
      // Web addresses aren't names
      'website: https://www.patreon.com/posts/some-game-v0-113797098': '',
      'https://www.patreon.com/SomeStudio': '',
      'www.somestudio.com': '',
      'Some Studio https://www.patreon.com/SomeStudio': 'Some Studio',
      'Some Studio - https://www.patreon.com/SomeStudio': 'Some Studio',
    };
    cases.forEach((raw, clean) {
      test(raw.split('\n').first, () => expect(cleanDeveloperName(raw), clean));
    });
  });

  group('F95Zone developer line', () {
    test('a link right after the name is dropped', () async {
      expect(
        await developerFrom(
            h1: 'Guilty Pleasure [v0.65] [Quonix]', line: 'Quonix <a href="#">Patreon</a>'),
        'Quonix',
      );
    });

    test('several links are dropped', () async {
      expect(
        await developerFrom(
            h1: 'Game [v1] [Vixwood Games]',
            line: 'Vixwood Games <a href="#">Patreon</a> - <a href="#">Itch.io</a>'),
        'Vixwood Games',
      );
    });

    test('a link nobody has listed yet is dropped too, using the thread title', () async {
      expect(
        await developerFrom(
            h1: 'Game [v1] [Quonix]', line: 'Quonix <a href="#">SomeNewSite</a>'),
        'Quonix',
      );
    });

    test('a name that only starts like the title developer is kept', () async {
      expect(
        await developerFrom(h1: 'Game [v1] [Quo]', line: 'Quonix'),
        'Quonix',
      );
    });

    test('a "Developer website" line is not a developer', () async {
      const post = '<b>Developer website</b>: https://www.patreon.com/SomeStudio<br />';
      expect(await developerFromPost(h1: 'Game [v1] [Quonix]', post: post), 'Quonix');
      expect(await developerFromPost(h1: 'Game', post: post), '');
    });

    test('a "Developer Notes" heading is not a developer', () async {
      expect(
        await developerFromPost(h1: 'Game [v1] [Quonix]', post: '<b>Developer Notes</b>:<br />Hello<br />'),
        'Quonix',
      );
    });

    test('the real line is found after a website line', () async {
      expect(
        await developerFromPost(
            h1: 'Game',
            post: '<b>Developer website</b>: https://example.test/<br /><b>Developer</b>: Quonix<br />'),
        'Quonix',
      );
    });

    test('an empty Developer label does not take the next line', () async {
      expect(await developerFromPost(h1: 'Game [v1] [Quonix]', post: '<b>Developer</b>:<br />'), 'Quonix');
    });

    test('a Developer/Publisher label works', () async {
      expect(
        await developerFromPost(h1: 'Game', post: '<b>Developer/Publisher</b>: Quonix Patreon<br />'),
        'Quonix',
      );
    });
  });
}
