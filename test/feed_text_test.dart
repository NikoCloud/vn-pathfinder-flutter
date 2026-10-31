// Reading feed bodies: LewdCorner's are HTML, F95Zone's are plain text.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/providers/feed_provider.dart' show mergeFeedItems;
import 'package:vn_pathfinder/services/feed_service.dart';
import 'package:vn_pathfinder/services/update_check_service.dart';
import 'dart:io';

const lewdCornerBody = '''
<img src="https://lewdcorner.com/attachments/6649368_cover-jpg.875737/" style="max-width:400px;display:block;margin-bottom:10px;" />
                        <p>
                             <strong>Developer:</strong> Hangover Cat<br>
                             <strong>Version:</strong> Chapter 1 &amp; 2 v0.13A<br>
                            <strong>Platforms:</strong> Windows<br>
                                                 <strong>NEW   8 hours ago</strong>
                        </p>
                        <p>
                            <strong>Tags:</strong>
                            fantasy, 2dcg<br>
                        </p>''';

const f95Body = 'Version: v0.4.8\nDeveloper: SRT\nTags: rpg\n[cover] https://f95zone.to/cover.jpg';

RawFeedItem item(String source, String body, {String url = 'https://lewdcorner.com/threads/game.10473/'}) =>
    RawFeedItem(id: 'x', source: source, sourceLabel: source, title: 'Game', rawBody: body, url: url);

GameGroup game(String lcUrl, String version) => GameGroup(
      baseKey: 'game',
      displayName: 'Game',
      versions: [
        GameVersion(
          folderName: 'Game-$version',
          folderPath: Directory('Game'),
          baseKey: 'game',
          versionStr: version,
          displayName: 'Game',
          localSaveDir: Directory('saves'),
          metadata: {'lc_url': lcUrl},
        ),
      ],
    );

void main() {
  group('Forum RSS', () {
    const rss = '''
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel><title>Games</title>
<item><title>Some Game [v0.6]</title><link>https://example.test/threads/some-game.1/</link>
<pubDate>Mon, 01 Jan 2024 12:34:56 +0000</pubDate>
<author>invalid@example.com (Poster)</author><dc:creator>Poster</dc:creator>
<content:encoded><![CDATA[<img src="https://example.test/cover.jpg" /><br />Overview of the game]]></content:encoded>
</item></channel></rss>''';

    test('reads the post, the poster and the image', () {
      final item = FeedService.parseRss(rss, source: 'azc', label: 'AzC', feedUrl: '').single;
      expect(item.author, 'Poster');
      expect(feedPlainText(item.rawBody), contains('Overview of the game'));
      expect(extractFeedVersion(item), 'v0.6');
    });

    test('takes the name out of a bare author line', () {
      final item = FeedService.parseRss(rss.replaceFirst('<dc:creator>Poster</dc:creator>', ''),
              source: 'azc', label: 'AzC', feedUrl: '')
          .single;
      expect(item.author, 'Poster');
    });
  });

  group('forum thread titles', () {
    String feed(String title) => '''
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><title>Games</title>
<item><title>$title</title><link>https://example.test/threads/1/</link><dc:creator>Upload Bot</dc:creator></item>
</channel></rss>''';
    RawFeedItem parse(String title) => FeedService.parseRss(feed(title), source: 'azc', label: 'AzC', feedUrl: '').single;

    test('the last bracket names the developer, not the poster', () {
      final item = parse('Some Game [v0.3] [Lantern Works]');
      expect(item.developer, 'Lantern Works');
      expect(item.title, 'Some Game');
      expect(extractFeedVersion(item), 'v0.3');
    });

    test('a version with no v is still a version', () {
      final item = parse('Some Game [0.3.1] [Lantern Works]');
      expect(extractFeedVersion(item), '0.3.1');
      expect(item.developer, 'Lantern Works');
    });

    test('a version in the last bracket is not a developer', () {
      expect(parse('Some Game [Ren\'Py] [v0.3]').developer, 'Upload Bot');
      expect(parse('Some Game [Ep. 4]').developer, 'Upload Bot');
    });

    test('a link label in the bracket is cleaned off', () {
      expect(parse('Some Game [v1] [Lantern Works Patreon]').developer, 'Lantern Works');
    });
  });

  test('a row saved with RSS\'s email form shows the name', () {
    final saved = RawFeedItem(
      id: 'x',
      source: 'azc',
      sourceLabel: 'AzC',
      title: 't',
      rawBody: 'Version: 1',
      url: '',
      author: 'invalid@example.com (Poster)',
    );
    expect(saved.developer, 'Poster');
  });

  group('LewdCorner labels', () {
    String list(String fields) => '{"data":{"items":[{"title":"Some Game","link":"/threads/1/",$fields}]}}';
    RawFeedItem one(String fields) => FeedService.parseLewdCornerList(list(fields)).single;

    test('what the site marks as new is a new game', () {
      expect(one('"is_new":true,"is_new_game":false').isNewGame, isTrue);
      expect(one('"is_new":false,"is_new_game":false').isNewGame, isFalse);
    });

    test('a Completed badge means complete', () {
      expect(one('"badges":[{"id":1,"name":"Completed"}]').isComplete, isTrue);
      expect(one('"badges":[{"id":2,"name":"Ren\'Py"}]').isComplete, isFalse);
    });

    test('a new, finished game says Complete and sits on both shelves', () {
      final item = one('"is_new":true,"badges":[{"name":"Completed"}]');
      expect(item.kind, FeedKind.complete);
      expect(item.isNewGame, isTrue);
    });
  });

  group('merging a refresh into the saved list', () {
    final now = DateTime(2026, 10, 30, 12);
    RawFeedItem row(String id, String source, {int hours = 1}) => RawFeedItem(
          id: id,
          source: source,
          sourceLabel: source,
          title: id,
          rawBody: '',
          url: '',
          publishedAt: now.subtract(Duration(hours: hours)),
        );

    test('new data replaces the same row, and a site that failed keeps its rows', () {
      final kept = mergeFeedItems([row('a', 'f95zone', hours: 5), row('b', 'azc', hours: 6)], [row('a', 'f95zone')], now);
      expect(kept.map((i) => i.id), ['a', 'b']);
      expect(kept.first.publishedAt, now.subtract(const Duration(hours: 1)));
    });

    RawFeedItem listed(String id, String source) => RawFeedItem(
          id: id,
          source: source,
          sourceLabel: source,
          title: id,
          rawBody: '',
          url: '',
          publishedAt: now.subtract(const Duration(hours: 5)),
          channelName: 'Latest Updates',
        );

    test('forum activity never sits beside a site\'s real list', () {
      final kept = mergeFeedItems([listed('saved', 'f95zone')], [row('chatter', 'f95zone')], now);
      expect(kept.map((i) => i.id), ['saved']);
    });

    test('the public feed stands in for a site with nothing better', () {
      final kept = mergeFeedItems([], [row('public', 'lewdcorner')], now);
      expect(kept.map((i) => i.id), ['public']);
    });

    test('the real list takes over from the public feed', () {
      final kept = mergeFeedItems([row('public', 'f95zone')], [listed('real', 'f95zone')], now);
      expect(kept.map((i) => i.id), ['real']);
    });

    test('a site with no list of its own keeps its forum rows', () {
      final kept = mergeFeedItems([listed('a', 'f95zone')], [row('b', 'azc')], now);
      expect(kept.map((i) => i.id), containsAll(['a', 'b']));
    });

    test('anything over ten days old goes', () {
      expect(mergeFeedItems([row('old', 'azc', hours: 300)], [], now), isEmpty);
    });
  });

  group('deduplicate', () {
    RawFeedItem row(String source, String version, int day) => RawFeedItem(
          id: '$source::$version',
          source: source,
          sourceLabel: source,
          title: 'Some Game',
          rawBody: 'Version: $version',
          url: 'https://example.test/$source',
          publishedAt: DateTime.utc(2026, 10, day),
        );

    test('the same version on two sites keeps the earlier post', () {
      final kept = FeedService.deduplicate([row('f95zone', 'v0.5', 20), row('lewdcorner', '0.5', 18)]);
      expect(kept.single.source, 'lewdcorner');
    });

    test('a newer version on another site is never hidden', () {
      final kept = FeedService.deduplicate([row('f95zone', 'v0.6', 20), row('azc', 'v0.5', 12)]);
      expect(kept.map((i) => i.source), ['f95zone', 'azc']);
    });
  });

  group('feed item facts', () {
    RawFeedItem item(String body, {String author = ''}) => RawFeedItem(
          id: 'x',
          source: 'azc',
          sourceLabel: 'AzC',
          title: 'Some Game',
          rawBody: body,
          url: 'https://example.test/threads/some-game.1/',
          author: author,
        );

    test('reads the fact lines', () {
      final i = item('Version: 0.5\nDeveloper: Studio\nTags: romance, comedy\nRating: 4.25 / 5\n[cover] https://example.test/c.jpg');
      expect(i.developer, 'Studio');
      expect(i.tags, ['romance', 'comedy']);
      expect(i.rating, 4.25);
      expect(i.coverUrl, 'https://example.test/c.jpg');
      expect(i.overview, isEmpty);
    });

    test('a forum post gives its first real image and its poster', () {
      final i = item('<img src="https://example.test/styles/smilies/a.png" /><img src="https://example.test/art.png" />Hello', author: 'Poster');
      expect(i.coverUrl, 'https://example.test/art.png');
      expect(i.developer, 'Poster');
      expect(i.overview, 'Hello');
    });

    test('sorts releases into kinds', () {
      expect(item('Version: 0.5').kind, FeedKind.update);
      expect(item('Version: 0.5\nKind: new').kind, FeedKind.newGame);
      expect(item('Version: Final').kind, FeedKind.complete);
      expect(item('Kind: complete').kind, FeedKind.complete);
    });
  });

  group('ratingsDue', () {
    final now = DateTime(2026, 10, 30);
    const week = Duration(days: 7);

    test('skips threads looked up recently, and puts the longest wait first', () {
      expect(
        UpdateCheckService.ratingsDue(
          [1, 2, 3, 4],
          {
            1: now.subtract(const Duration(days: 1)),
            2: now.subtract(const Duration(days: 8)),
            3: now.subtract(const Duration(days: 30)),
          },
          now,
          week,
        ),
        [4, 3, 2],
      );
    });

    test('nothing is due when everything is recent', () {
      expect(UpdateCheckService.ratingsDue([1], {1: now}, now, week), isEmpty);
    });
  });

  group('extractFeedVersion', () {
    test('reads a LewdCorner HTML body', () {
      expect(extractFeedVersion(item('lewdcorner', lewdCornerBody)), 'Chapter 1 & 2 v0.13A');
    });

    test('reads an F95Zone plain-text body', () {
      expect(extractFeedVersion(item('f95zone', f95Body)), 'v0.4.8');
    });

    test('no version line', () {
      expect(extractFeedVersion(item('lewdcorner', '<p>Nothing here</p>')), isNull);
      expect(extractFeedVersion(item('lewdcorner', '<strong>Version:</strong> <br>')), isNull);
    });
  });

  group('feedPlainText', () {
    test('turns a LewdCorner body into clean lines', () {
      expect(
        feedPlainText(lewdCornerBody),
        'Developer: Hangover Cat\nVersion: Chapter 1 & 2 v0.13A\nPlatforms: Windows\n\nTags:\nfantasy, 2dcg',
      );
    });

    test('drops the [cover] line, so feed cards stay text-only', () {
      expect(feedPlainText(f95Body), 'Version: v0.4.8\nDeveloper: SRT\nTags: rpg');
    });

    test('keeps ordinary text that mentions new things', () {
      expect(feedPlainText('New Game Plus is here'), 'New Game Plus is here');
    });
  });

  test('a LewdCorner feed item now produces an update alert', () {
    const link = 'https://lewdcorner.com/threads/game.10473/';
    final body = lewdCornerBody.replaceFirst('Chapter 1 &amp; 2 v0.13A', 'v0.5');
    final updates = UpdateCheckService.availableUpdates(
        [game(link, '0.4')], const {}, const {}, [item('lewdcorner', body, url: link)], extractFeedVersion);
    expect(updates['game']?.version, 'v0.5');
    expect(updates['game']?.source, 'lewdcorner');
  });

  group('LewdCorner Latest Updates data', () {
    const list = '''
{"status":"ok","data":{"items":[
  {"id":21714,"title":"Standard Game","link":"https://lewdcorner.com/threads/standard-game.21714/","timestamp":1793364660,
   "is_premium":false,"version":"0.6.1","developer":"Studio","platforms":["Windows","Linux"],"tags":["2dcg","rpg"],"rating":0},
  {"id":7,"title":"Plus Game","link":"/threads/plus-game.7/","timestamp":1792800000,
   "is_premium":true,"version":"","developer":"","platforms":[],"tags":[],"rating":4.25},
  {"id":8,"title":"","link":"/threads/no-title.8/","timestamp":1792800000}
]}}''';

    test('becomes the same plain lines as F95Zone, with the version readable', () {
      final items = FeedService.parseLewdCornerList(list);
      expect(items.length, 2);
      final game = items.first;
      expect(game.title, 'Standard Game');
      expect(game.rawBody, 'Version: 0.6.1\nDeveloper: Studio\nPlatforms: Windows, Linux\nTags: 2dcg, rpg');
      expect(extractFeedVersion(game), '0.6.1');
      expect(game.publishedAt, DateTime.fromMillisecondsSinceEpoch(1793364660000, isUtc: true));
      expect(UpdateCheckService.threadId(game.url), 21714);
    });

    test('Plus games are labelled, and a real rating is kept', () {
      final items = FeedService.parseLewdCornerList(list);
      expect(items[0].sourceLabel, 'LewdCorner');
      expect(items[1].sourceLabel, 'LewdCorner Plus');
      expect(items[1].rawBody, 'Rating: 4.25 / 5');
      expect(items[1].url, 'https://lewdcorner.com/threads/plus-game.7/');
    });

    test('a logged-out answer gives nothing, so the public feeds take over', () {
      const refused = '{"status":"error","data":null,"error":{"message":"Invalid API key."}}';
      expect(FeedService.parseLewdCornerList(refused), isEmpty);
      expect(FeedService.parseLewdCornerList('<html>not json</html>'), isEmpty);
      expect(FeedService.parseLewdCornerList(''), isEmpty);
    });
  });

  test('the public forum feed keeps the version from the thread title', () {
    const rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Games</title>
<item>
  <title>Harvesting Corruption [v0.0.75] [JuicyGenieGames]</title>
  <pubDate>Wed, 28 Oct 2026 17:00:31 +0000</pubDate>
  <link>https://lewdcorner.com/threads/harvesting-corruption-v0-0-75-juicygeniegames.16188/</link>
</item>
</channel></rss>''';
    final items = FeedService.parseRss(rss, source: 'lewdcorner', label: 'LewdCorner', feedUrl: 'x');
    expect(items.single.title, 'Harvesting Corruption');
    expect(extractFeedVersion(items.single), 'v0.0.75');
  });
}
