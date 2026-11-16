// Update alerts compare versions as forums spell them. Cases from a real
// library.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_status.dart';

void main() {
  test('Public and platform words are the version you have', () {
    for (final (site, have) in [
      ('v0.9.5 Public', '0.9.5'),
      ('v0.18 PC', '0.18'),
      ('v0.20 pre alpha', 'v0.20_Pre'),
      ('v0.5 Beta', '0.5'),
      ('v1.0 Final', '1.0 Final'),
      ('v1.0 Final Public', '1.0 Final'),
    ]) {
      expect(isClearlyNewer(site, have), isFalse, reason: '$site vs $have');
    }
  });

  test('a word that means another build is newer', () {
    for (final (site, have) in [
      ('v2.0 Final', '2.0'),
      ('v2.0 Final Bugfix', '2.0 Final'),
      ('Final Fix', 'Final'),
      ('v0.5 VIP', '0.5 Patreon'),
      ('v0.5 Patreon', '0.5'),
      ('v0.09 v4 Fix', '0.09_V4_Alpha'),
      ('v0.5', '0.5 Beta'),
    ]) {
      expect(isClearlyNewer(site, have), isTrue, reason: '$site vs $have');
    }
  });

  test('a single letter after the same numbers is a newer build', () {
    expect(isClearlyNewer('v1.6d', '1.6c'), isTrue);
    expect(isClearlyNewer('1.0a', '1.0'), isTrue);
    expect(isClearlyNewer('1.6c', '1.6d'), isFalse);
  });

  test('higher numbers are newer, whatever words follow', () {
    expect(isClearlyNewer('v0.39.DV', '0.38.dv'), isTrue);
    expect(isClearlyNewer('v14.0 Public', '10.0'), isTrue);
    expect(isClearlyNewer('v0.5.5 Cheats', '0.4.5'), isTrue);
    expect(isClearlyNewer('v0.4 Final', '0.5'), isFalse);
  });

  test('a bare Final is newer than a numbered version, not than another Final', () {
    expect(isClearlyNewer('Final', '1.0'), isTrue);
    expect(isClearlyNewer('Final', '1.0 Final'), isFalse);
    expect(isClearlyNewer('Final', 'Final'), isFalse);
  });
}
