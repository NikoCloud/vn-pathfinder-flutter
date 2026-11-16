// #47: the download browser stays on the file host. Invented hosts.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/redirect_guard.dart';

void main() {
  test('sites ignore subdomains and know two-part country endings', () {
    expect(siteOf('https://dl3.filebarn.example/x'), 'filebarn.example');
    expect(siteOf('https://www.filebarn.example'), 'filebarn.example');
    expect(siteOf('https://files.hoard.co.uk/a'), 'hoard.co.uk');
    expect(siteOf('about:blank'), '');
    expect(siteOf('blob:https://mega.nz/1234'), '');
  });

  test('a jump to an ad from the host page goes back to the host page', () {
    final g = RedirectGuard()..reset('https://filebarn.example/f/abc');
    expect(g.onUrl('https://filebarn.example/f/abc'), isNull);
    expect(g.onUrl('https://cdn2.filebarn.example/f/abc?ready=1'), isNull, reason: 'same site');
    expect(g.onUrl('https://win-a-prize.example/landing'), 'https://cdn2.filebarn.example/f/abc?ready=1');
    expect(g.blocked, 'https://win-a-prize.example/landing');
    // Back on the host clears the notice.
    expect(g.onUrl('https://cdn2.filebarn.example/f/abc?ready=1'), isNull);
    expect(g.blocked, isNull);
  });

  test("a forum's masked link hands on to whatever host it leads to", () {
    final g = RedirectGuard()..reset('https://f95zone.to/masked/abc');
    expect(g.onUrl('https://f95zone.to/masked/abc'), isNull);
    expect(g.onUrl('https://filebarn.example/f/abc'), isNull);
    expect(g.onUrl('https://win-a-prize.example/'), 'https://filebarn.example/f/abc');
  });

  test('a page that keeps sending you away is left alone after three tries', () {
    final g = RedirectGuard()..reset('https://filebarn.example/f/abc');
    final t = DateTime(2026, 11, 15, 12);
    for (var i = 0; i < 3; i++) {
      expect(g.onUrl('https://win-a-prize.example/', now: t), isNotNull);
    }
    expect(g.onUrl('https://win-a-prize.example/', now: t), isNull);
    expect(g.blocked, isNotNull, reason: 'the notice stays so the person can go back');
    // Ten seconds later it tries again.
    expect(g.onUrl('https://win-a-prize.example/', now: t.add(const Duration(seconds: 11))), isNotNull);
  });

  test('"Go there anyway" makes that site the one to stay on', () {
    final g = RedirectGuard()..reset('https://filebarn.example/f/abc');
    g.onUrl('https://other-host.example/d/abc');
    g.allow('https://other-host.example/d/abc');
    expect(g.blocked, isNull);
    expect(g.onUrl('https://other-host.example/d/abc'), isNull);
    expect(g.onUrl('https://filebarn.example/f/abc'), 'https://other-host.example/d/abc');
  });

  test('Mega is recognised for the folder watch', () {
    expect(isMegaSite(siteOf('https://mega.nz/file/abc#key')), isTrue);
    expect(isMegaSite(siteOf('https://filebarn.example')), isFalse);
  });
}
