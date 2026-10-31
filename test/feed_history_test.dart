import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/providers/feed_provider.dart' show SavedFeed, mergeFeedItems;
import 'package:vn_pathfinder/services/feed_history.dart';
import 'package:vn_pathfinder/services/feed_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 31, 12);
  DateTime ago(int hours) => now.subtract(Duration(hours: hours));
  int seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  RawFeedItem lewd(String version, {required int edited, int? posted, bool isNew = false}) => RawFeedItem(
        id: 'lewdcorner::$version',
        source: 'lewdcorner',
        sourceLabel: 'LewdCorner',
        title: 'Some Game',
        rawBody: [
          if (version.isNotEmpty) 'Version: $version',
          if (isNew) 'Kind: new',
          if (posted != null) 'Posted: ${seconds(ago(posted))}',
        ].join('\n'),
        url: 'https://lewdcorner.com/threads/some-game-$version.77/',
        publishedAt: ago(edited),
        channelName: 'Latest Updates - LewdCorner',
      );

  RawFeedItem f95(String version, {required int hours}) => RawFeedItem(
        id: 'f95zone::12',
        source: 'f95zone',
        sourceLabel: 'F95Zone',
        title: 'Some Game',
        rawBody: 'Version: $version',
        url: 'https://f95zone.to/threads/12/',
        publishedAt: ago(hours),
        channelName: 'Latest Updates',
      );

  RawFeedItem forum(String version, {String source = 'azc', int hours = 0}) => RawFeedItem(
        id: '$source::https://example.test/threads/some-game-$version.9/',
        source: source,
        sourceLabel: source,
        title: 'Some Game',
        rawBody: version.isEmpty ? '' : 'Version: $version',
        url: 'https://example.test/threads/some-game-$version.9/',
        publishedAt: ago(hours),
        channelName: 'Games',
      );

  group('thread identity', () {
    test('a new version in the link is still the same thread', () {
      expect(threadKey(lewd('v0.2', edited: 1)), threadKey(lewd('v0.1', edited: 9)));
      expect(threadKey(forum('v0.2')), threadKey(forum('v0.1')));
    });

    test('the Feed keeps one row per thread when its link changes', () {
      final kept = mergeFeedItems([lewd('v0.1', edited: 9)], [lewd('v0.2', edited: 1)], now);
      expect(kept.map((i) => extractFeedVersion(i)), ['v0.2']);
    });
  });

  group('a public feed standing in', () {
    RawFeedItem saved() => f95('v0.1', hours: 5);
    RawFeedItem public() => RawFeedItem(
          id: 'f95zone::https://f95zone.to/threads/some-game.12/',
          source: 'f95zone',
          sourceLabel: 'F95Zone',
          title: 'Some Game',
          rawBody: 'Version: v0.1',
          url: 'https://f95zone.to/threads/some-game.12/',
          publishedAt: ago(1),
          channelName: 'Games',
        );

    test('is the same thread as the list row', () => expect(threadKey(public()), threadKey(saved())));

    test('never replaces what the site list said', () {
      final kept = mergeFeedItems([saved()], [public()], now);
      expect(kept.single.fromSiteList, isTrue);
      expect(kept.single.publishedAt, ago(5));
    });
  });

  group('LewdCorner', () {
    test('an edit without a new version keeps the release date', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30), now);
      final row = record.settle(lewd('v0.1', edited: 2), now);
      expect(row.publishedAt, ago(30));
    });

    test('a new version takes the date of the edit that brought it', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30), now);
      final row = record.settle(lewd('v0.2', edited: 2), now);
      expect(row.publishedAt, ago(2));
    });

    test('v0.1 and 0.1 are the same version', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30), now);
      expect(record.settle(lewd('0.1', edited: 2), now).publishedAt, ago(30));
    });

    test('a new thread keeps its post date and stays New after its first edit', () {
      final record = ReleaseRecord();
      final row = record.settle(lewd('v0.1', edited: 2, posted: 10), now);
      expect(row.publishedAt, ago(10));
      expect(row.isNewGame, isTrue);
      final later = record.settle(lewd('v0.1', edited: 1), now);
      expect(later.publishedAt, ago(10));
      expect(later.isNewGame, isTrue);
    });

    test('an old thread seen for the first time takes the site date, not New', () {
      final row = ReleaseRecord().settle(lewd('v0.4', edited: 2, posted: 24 * 40), now);
      expect(row.publishedAt, ago(2));
      expect(row.isNewGame, isFalse);
    });

    test('a version changed only in the title is dated when it was noticed', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30), now);
      expect(record.settle(lewd('v0.2', edited: 30), now).publishedAt, now);
    });

    test('a thread with no version keeps its first date', () {
      final record = ReleaseRecord();
      record.settle(lewd('', edited: 30), now);
      expect(record.settle(lewd('', edited: 2), now).publishedAt, ago(30));
    });

    test('a row that loses its version is not a release', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30), now);
      expect(record.settle(lewd('', edited: 2), now).publishedAt, ago(30));
      expect(record.settle(lewd('v0.1', edited: 1), now).publishedAt, ago(30));
    });
  });

  test('F95Zone keeps its own dates, even for the same version', () {
    final record = ReleaseRecord();
    record.settle(f95('v0.1', hours: 30), now);
    expect(record.settle(f95('v0.1', hours: 2), now).publishedAt, ago(2));
  });

  group('forum threads', () {
    test('a row needs its thread read once per version', () {
      final record = ReleaseRecord();
      expect(record.needsThread(forum('v0.1')), isTrue);
      record.settle(forum('v0.1'), now, thread: ThreadDates(ago(24 * 200), null));
      expect(record.needsThread(forum('v0.1')), isFalse);
      expect(record.needsThread(forum('v0.2')), isTrue);
    });

    test('the first post gives the date, not the latest reply', () {
      final row = ReleaseRecord().settle(forum('v0.1'), now, thread: ThreadDates(ago(200), ago(50)));
      expect(row.publishedAt, ago(50));
    });

    test('a post with no edit uses its post date', () {
      final row = ReleaseRecord().settle(forum('v0.1'), now, thread: ThreadDates(ago(200), null));
      expect(row.publishedAt, ago(200));
    });

    test('a new thread says New, and still does on later refreshes', () {
      final record = ReleaseRecord();
      final row = record.settle(forum('v0.1'), now, thread: ThreadDates(ago(10), ago(2)));
      expect(row.publishedAt, ago(10));
      expect(row.isNewGame, isTrue);
      expect(record.settle(forum('v0.1'), now).isNewGame, isTrue);
    });

    test('replies on an old release never bring it back', () {
      final record = ReleaseRecord();
      final first = record.settle(forum('v0.1'), now, thread: ThreadDates(ago(24 * 200), null));
      expect(mergeFeedItems([], [first], now), isEmpty);
      final again = record.settle(forum('v0.1'), now);
      expect(again.publishedAt, ago(24 * 200));
      expect(mergeFeedItems([], [again], now), isEmpty);
    });

    test('a new version whose post was never edited is dated when noticed', () {
      final record = ReleaseRecord();
      record.settle(forum('v0.1'), now, thread: ThreadDates(ago(200), null));
      final row = record.settle(forum('v0.2'), now, thread: ThreadDates(ago(200), null));
      expect(row.publishedAt, now);
    });

    test('a public feed standing in for a site with a list opens no threads', () {
      expect(ReleaseRecord().needsThread(forum('v0.1', source: 'f95zone')), isFalse);
      expect(ReleaseRecord().needsThread(forum('v0.1', source: 'lewdcorner')), isFalse);
    });
  });

  group('the saved record', () {
    test('survives a save and load', () {
      final record = ReleaseRecord();
      record.settle(lewd('v0.1', edited: 30, posted: 40), now);
      final back = ReleaseRecord.fromJson(jsonDecode(jsonEncode(record.toJson())));
      final row = back.settle(lewd('v0.1', edited: 2), now);
      expect(row.publishedAt, ago(40));
      expect(row.isNewGame, isTrue);
    });

    test('keeps the newest threads of each site, so one busy site cannot push out another', () {
      RawFeedItem numbered(String source, int n) => RawFeedItem(
            id: '$source::$n',
            source: source,
            sourceLabel: source,
            title: 'Game $n',
            rawBody: 'Version: 1',
            url: 'https://example.test/threads/$n/',
            publishedAt: now.subtract(Duration(minutes: n)),
          );
      final record = ReleaseRecord();
      for (var n = 0; n < 5010; n++) {
        record.settle(numbered('f95zone', n), now);
      }
      record.settle(numbered('lewdcorner', 1), now);
      final saved = record.toJson();
      expect(saved.keys.where((k) => k.startsWith('f95zone')).length, 5000);
      expect(saved, contains('f95zone::0'));
      expect(saved, isNot(contains('f95zone::5009')));
      expect(saved, contains('lewdcorner::1'));
    });

    test('a saved list from before the record gives it a start, without Azkosel dates', () {
      final saved = SavedFeed.read(jsonDecode(jsonEncode({
        'format': 2,
        'last_refreshed': ago(1).toIso8601String(),
        'items': [lewd('v0.1', edited: 30).toJson(), forum('v0.1').toJson()],
      })) as Map<String, dynamic>);
      expect(saved.outdated, isTrue);
      expect(saved.items.map((i) => i.source), ['lewdcorner']);
      expect(saved.releases.settle(lewd('v0.1', edited: 2), now).publishedAt.toString(), ago(30).toString());
      expect(saved.releases.needsThread(forum('v0.1')), isTrue);
    });

    test('the current format loads as it was saved', () {
      final record = ReleaseRecord();
      record.settle(forum('v0.1'), now, thread: ThreadDates(ago(20), null));
      final saved = SavedFeed.read(jsonDecode(jsonEncode({
        'format': 3,
        'last_refreshed': ago(1).toIso8601String(),
        'items': [forum('v0.1', hours: 20).toJson()],
        'releases': record.toJson(),
        'sites': {'f95zone': SiteCatchUp(caughtUpTo: ago(3)).toJson()},
      })) as Map<String, dynamic>);
      expect(saved.outdated, isFalse);
      expect(saved.items, hasLength(1));
      expect(saved.releases.needsThread(forum('v0.1')), isFalse);
      expect(saved.sites['f95zone']?.caughtUpTo, ago(3));
    });
  });

  group('catching up', () {
    RawFeedItem at(int hours) => f95('v$hours', hours: hours);
    final fiveHoursAPage = [
      for (var page = 0; page < 60; page++) [at(page * 5 + 1), at(page * 5 + 5)],
    ];

    /// Runs [readBack], and returns what it read and asked for.
    Future<({SiteCatchUp? result, List<int> pages, List<RawFeedItem> rows})> run(
      SiteCatchUp from,
      List<List<RawFeedItem>> list, {
      int? refuseFrom,
    }) async {
      final pages = <int>[];
      final rows = <RawFeedItem>[];
      final result = await readBack(
        from,
        readPage: (page) async {
          pages.add(page);
          if (refuseFrom != null && pages.length >= refuseFrom) return [];
          return page <= list.length ? list[page - 1] : [];
        },
        onRows: rows.addAll,
        now: now,
        gap: Duration.zero,
      );
      return (result: result, pages: pages, rows: rows);
    }

    test('stops at the page that reaches the caught-up date', () async {
      final r = await run(SiteCatchUp(caughtUpTo: ago(12)), fiveHoursAPage);
      expect(r.pages, [1, 2, 3]);
      expect(r.result?.caughtUpTo, ago(1));
      expect(r.result?.stoppedEarly, isFalse);
    });

    test('a short gap reads one page', () async {
      final r = await run(SiteCatchUp(caughtUpTo: ago(3)), fiveHoursAPage);
      expect(r.pages, [1]);
    });

    test('with nothing to go on, it reads back ten days and stops', () async {
      final r = await run(const SiteCatchUp(), fiveHoursAPage);
      expect(r.pages.length, maxListPages);
      expect(r.result?.stoppedEarly, isTrue, reason: 'that is more pages than one run reads');
      final tenDays = await run(
        const SiteCatchUp(),
        [for (var page = 0; page < 60; page++) [at(page * 12 + 1), at(page * 12 + 12)]],
      );
      expect(tenDays.pages.length, 20);
      expect(tenDays.result?.caughtUpTo, ago(1));
    });

    test('a date older than ten days counts as ten days', () async {
      final list = [for (var page = 0; page < 60; page++) [at(page * 12 + 1), at(page * 12 + 12)]];
      final r = await run(SiteCatchUp(caughtUpTo: ago(24 * 30)), list);
      expect(r.pages.length, 20);
    });

    test('a refusal keeps what it got and leaves the caught-up date alone', () async {
      final from = SiteCatchUp(caughtUpTo: ago(100));
      final r = await run(from, fiveHoursAPage, refuseFrom: 4);
      expect(r.rows, hasLength(6));
      expect(r.result?.caughtUpTo, from.caughtUpTo);
      expect(r.result?.stoppedEarly, isTrue);
      expect(r.result?.resumeFrom, ago(1));
      expect(r.result?.resumePage, 4);
    });

    test('the next run skips what the last one read', () async {
      final first = await run(SiteCatchUp(caughtUpTo: ago(100)), fiveHoursAPage, refuseFrom: 4);
      // Three pages of new releases have arrived since, so everything moved
      // down. Page 4 is the first the last run already read.
      final moved = [
        [at(-20), at(-16)],
        [at(-15), at(-11)],
        [at(-10), at(0)],
        ...fiveHoursAPage,
      ];
      final next = await run(first.result!, moved);
      expect(next.pages.take(5), [1, 2, 3, 4, 7]);
      expect(next.rows.any((r) => r.publishedAt == ago(16)), isTrue, reason: 'the page it stopped at');
      expect(next.result?.caughtUpTo, ago(-20));
      expect(next.result?.stoppedEarly, isFalse);
    });

    test('a resumed run that is refused again keeps its place', () async {
      final first = await run(SiteCatchUp(caughtUpTo: ago(100)), fiveHoursAPage, refuseFrom: 4);
      final moved = [
        [at(-10), at(0)],
        ...fiveHoursAPage,
      ];
      final second = await run(first.result!, moved, refuseFrom: 3);
      expect(second.pages, [1, 2, 5]);
      expect(second.result?.resumeFrom, ago(-10));
      expect(second.result?.resumePage, 5);
      expect(second.result?.caughtUpTo, ago(100));
    });

    test('nothing at all answers: null, so the public feed can stand in', () async {
      final r = await run(SiteCatchUp(caughtUpTo: ago(100)), fiveHoursAPage, refuseFrom: 1);
      expect(r.result, isNull);
      expect(r.rows, isEmpty);
    });

    test('dates survive a save and load', () {
      final read = SiteCatchUp(caughtUpTo: ago(5), resumeFrom: ago(2), resumePage: 7);
      final back = SiteCatchUp.fromJson(jsonDecode(jsonEncode(read.toJson())));
      expect(back.caughtUpTo, ago(5));
      expect(back.resumeFrom, ago(2));
      expect(back.resumePage, 7);
    });
  });

  group('reading a site', () {
    String page(String row) => '{"status":"ok","msg":{"data":[$row,{"thread_id":2,"title":"Other","version":"v2","ts":1761900000}]}}';

    test('a version sent as a number keeps the rest of the F95Zone page', () {
      final rows = FeedService.parseF95List(page('{"thread_id":1,"title":"Game","creator":"Studio","version":1.5,"ts":1761900000}'));
      expect(rows, hasLength(2));
      expect(extractFeedVersion(rows.first), '1.5');
      expect(rows.first.developer, 'Studio');
      expect(rows.first.publishedAt, DateTime.fromMillisecondsSinceEpoch(1761900000 * 1000, isUtc: true));
    });

    test('titles, developers and ratings of the wrong type do too', () {
      final rows = FeedService.parseF95List(page('{"thread_id":1,"title":2077,"creator":404,"version":null,"rating":"none","tags":null,"prefixes":"x","ts":"soon"}'));
      expect(rows, hasLength(2));
      expect(rows.first.title, '2077');
      expect(rows.first.developer, '404');
      expect(rows.first.publishedAt, isNull);
      expect(rows.first.rating, 0);
    });

    test('an F95Zone page that is not the list gives nothing', () {
      expect(FeedService.parseF95List('<html>Just a moment</html>'), isEmpty);
      expect(FeedService.parseF95List('{"status":"error","msg":"nope"}'), isEmpty);
      expect(FeedService.parseF95List(''), isEmpty);
    });

    test('LewdCorner rows carry when the thread went up, without showing it', () {
      final row = FeedService.parseLewdCornerList(
        '{"data":{"items":[{"title":"Some Game","link":"/threads/1/","timestamp":1761900000,"posted_ts":1761800000}]}}',
      ).single;
      expect(row.postedAt, DateTime.fromMillisecondsSinceEpoch(1761800000 * 1000, isUtc: true));
      expect(row.overview, isEmpty);
    });

    test('a thread gives its first post dates, offset included', () {
      final dates = FeedService.parseThreadDates('{"posted":"2026-10-30T12:00:00-0400","edited":"2026-10-31T08:30:00-0400"}');
      expect(dates?.posted, DateTime.utc(2026, 10, 30, 16));
      expect(dates?.edited, DateTime.utc(2026, 10, 31, 12, 30));
    });

    test('a page that is not a thread gives nothing', () {
      expect(FeedService.parseThreadDates(''), isNull);
      expect(FeedService.parseThreadDates('{"posted":null,"edited":null}'), isNull);
      expect(FeedService.parseThreadDates('<html>'), isNull);
    });
  });
}
