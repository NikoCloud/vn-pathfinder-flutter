// Update alerts from F95Zone's checker and the Feed's release history: one per
// game, newest version, earliest post; title-only matches kept apart.
// Invented games and threads throughout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/services/release_history.dart';
import 'package:vn_pathfinder/services/update_check_service.dart';

GameGroup _game(String version, {Map<String, dynamic> links = const {}, String title = 'Lantern Bay', String dev = ''}) =>
    GameGroup(
      baseKey: 'lanternbay',
      displayName: title,
      versions: [
        GameVersion(
          folderName: 'LanternBay-$version',
          folderPath: Directory('LanternBay-$version'),
          baseKey: 'lanternbay',
          versionStr: version,
          displayName: title,
          localSaveDir: Directory('saves'),
          metadata: {...links, if (dev.isNotEmpty) 'developer': dev},
        ),
      ],
    );

RawFeedItem _post(String site, String url, String version, DateTime at, {double rating = 0, String title = 'Lantern Bay'}) =>
    RawFeedItem(
      id: '$site::$url',
      source: site,
      sourceLabel: site,
      title: title,
      rawBody: ['Version: $version', if (rating > 0) 'Rating: $rating / 5'].join('\n'),
      url: url,
      publishedAt: at,
    );

const _f95 = 'https://f95zone.to/threads/lantern-bay.111/';
const _lc = 'https://lewdcorner.com/threads/lantern-bay.222/';
const _azc = 'https://azkoselscorner.com/index.php?threads/lantern-bay.333/';
final _day = DateTime.utc(2026, 11, 10);

({Map<String, AvailableUpdate> confirmed, Map<String, AvailableUpdate> possible}) _find(
  GameGroup g,
  ReleaseHistory h, {
  Map<int, String> f95 = const {},
  Map<String, int> titleLinks = const {},
  bool titleConfirmed = false,
}) =>
    UpdateCheckService.findUpdates(
      groups: [g],
      f95Versions: f95,
      titleLinks: titleLinks,
      confirmedTitleLink: (_) => titleConfirmed ? titleLinks['lanternbay'] : null,
      history: h,
    );

void main() {
  test('the same version on two sites: one alert, pointing to the site that posted it first', () {
    final h = ReleaseHistory()
      ..record([
        _post('f95zone', _f95, '0.5', _day.add(const Duration(hours: 3))),
        _post('lewdcorner', _lc, '0.5', _day),
      ]);
    final u = _find(_game('0.4', links: {'f95_url': _f95, 'lc_url': _lc}), h).confirmed['lanternbay']!;
    expect(u.version, '0.5');
    expect(u.source, 'lewdcorner');
    expect(u.sites.keys, containsAll(['f95zone', 'lewdcorner']));
  });

  test('a game only on Azkosel\'s Corner still gets its alert', () {
    final h = ReleaseHistory()..record([_post('azc', _azc, '1.2', _day)]);
    final u = _find(_game('1.1', links: {'azc_url': _azc}), h).confirmed['lanternbay']!;
    expect((u.version, u.source), ('1.2', 'azc'));
  });

  test('the newest version wins across sources, whoever posted first', () {
    final h = ReleaseHistory()
      ..record([
        _post('lewdcorner', _lc, '0.5', _day),
        _post('f95zone', _f95, '0.6', _day.add(const Duration(days: 2))),
      ]);
    final u = _find(_game('0.4', links: {'f95_url': _f95, 'lc_url': _lc}), h).confirmed['lanternbay']!;
    expect(u.version, '0.6');
  });

  test("F95Zone's checker counts, and takes the Feed's earliest site when the Feed saw that version", () {
    final h = ReleaseHistory()..record([_post('lewdcorner', _lc, '0.7', _day)]);
    final g = _game('0.6', links: {'f95_url': _f95});
    // No LewdCorner link saved, but the release is known by title and version.
    final u = _find(g, h, f95: {111: '0.7'}).confirmed['lanternbay']!;
    expect(u.version, '0.7');
    expect(u.source, 'lewdcorner');
    expect(u.sites.keys, containsAll(['f95zone', 'lewdcorner']));
  });

  test('a title-only match is a possible update, never a counted one', () {
    final h = ReleaseHistory()..record([_post('f95zone', 'https://f95zone.to/threads/lantern-bay.999/', '0.9', _day)]);
    final r = _find(_game('0.4'), h);
    expect(r.confirmed, isEmpty);
    expect(r.possible['lanternbay']?.version, '0.9');
    expect(r.possible['lanternbay']?.confirmed, isFalse);
  });

  test('a title search counts only when its creator confirmed it', () {
    final h = ReleaseHistory();
    final g = _game('0.4', dev: 'Quillfen');
    expect(_find(g, h, f95: {444: '0.5'}, titleLinks: {'lanternbay': 444}).confirmed, isEmpty);
    expect(_find(g, h, f95: {444: '0.5'}, titleLinks: {'lanternbay': 444}).possible.keys, ['lanternbay']);
    expect(_find(g, h, f95: {444: '0.5'}, titleLinks: {'lanternbay': 444}, titleConfirmed: true).confirmed.keys, ['lanternbay']);
  });

  test('what a thread showed when the app read it counts, on any site', () {
    final g = _game('0.6', links: {'lc_url': _lc});
    final r = UpdateCheckService.findUpdates(
      groups: [g],
      f95Versions: const {},
      titleLinks: const {},
      confirmedTitleLink: (_) => null,
      history: ReleaseHistory(),
      threadVersions: const {'lewdcorner:222': 'v0.6.5'},
    );
    expect((r.confirmed['lanternbay']?.version, r.confirmed['lanternbay']?.source), ('v0.6.5', 'lewdcorner'));
    expect(threadVersionKey(_azc), 'azc:333');
    expect(threadVersionKey('https://example.test/threads/x.1/'), isNull);
  });

  test('nothing newer, nothing shown', () {
    final h = ReleaseHistory()..record([_post('f95zone', _f95, '0.4', _day)]);
    final r = _find(_game('0.4', links: {'f95_url': _f95}), h, f95: {111: '0.4'});
    expect(r.confirmed, isEmpty);
    expect(r.possible, isEmpty);
  });

  group('the release history', () {
    test('keeps each site once, fills a missing date later, and survives a save', () {
      final h = ReleaseHistory();
      expect(h.record([_post('lewdcorner', _lc, '0.5', _day)]), isTrue);
      expect(h.record([_post('lewdcorner', _lc, '0.5', _day)]), isFalse, reason: 'nothing new');
      h.record([RawFeedItem(id: 'a', source: 'azc', sourceLabel: 'azc', title: 'Lantern Bay', rawBody: 'Version: 0.5', url: _azc)]);
      h.record([_post('azc', _azc, '0.5', _day.add(const Duration(days: 1)))]);
      final e = h.release('Lantern Bay', 'v0.5')!;
      expect(e.sites['azc']!.postedAt, _day.add(const Duration(days: 1)));
      expect(e.earliest!.key, 'lewdcorner');

      h.save();
      final back = ReleaseHistory.load();
      expect(back.length, 1);
      expect(back.forThread('azc', 333).single.sites.keys, containsAll(['lewdcorner', 'azc']));
    });

    test('remembers a rating seen later', () {
      final h = ReleaseHistory()..record([_post('f95zone', _f95, '0.5', _day)]);
      h.record([_post('f95zone', _f95, '0.5', _day, rating: 4.4)]);
      expect(h.release('Lantern Bay', '0.5')!.rating, 4.4);
    });
  });
}
