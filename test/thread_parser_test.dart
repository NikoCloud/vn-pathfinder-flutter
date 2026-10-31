import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/thread_parser.dart';

String thread(String post) => '<article class="message message--post"><div class="message-body">'
    '<div class="bbWrapper">$post</div></div></article>';

void main() {
  const page = 'https://example.test/threads/some-game.1/';

  group('download links', () {
    test('keeps the host labels under their platform', () {
      final parsed = ThreadParser.parse(
        thread('<b>DOWNLOAD</b><br />Win/Linux: <a href="/dl/1">MEGA</a> - <a href="/dl/2">PIXELDRAIN</a><br />'
            'Mac: <a href="/dl/3">MEGA</a><br />Android: <a href="/dl/4">GOFILE</a>'),
        page,
      );
      expect(parsed.links.map((l) => '${l.platform} ${l.host}'), [
        'Windows MEGA',
        'Windows PIXELDRAIN',
        'Mac MEGA',
        'Android GOFILE',
      ]);
      expect(parsed.links.first.url, 'https://example.test/dl/1');
      expect(parsed.platforms, ['Windows', 'Mac', 'Android']);
    });

    test('finds direct links to known hosts', () {
      final parsed = ThreadParser.parse(thread('Windows: <a href="https://mega.nz/file/abc">Mega</a>'), page);
      expect(parsed.links.single.host, 'MEGA');
      expect(parsed.links.single.platform, 'Windows');
    });

    test('ignores everything that is not a download', () {
      final parsed = ThreadParser.parse(
        thread('Developer: <a href="https://www.patreon.com/x">Patreon</a> <a href="/threads/other.2/">Other game</a>'),
        page,
      );
      expect(parsed.links, isEmpty);
    });

    test('names a bare gateway link after what it is', () {
      final parsed = ThreadParser.parse(
        thread('<a href="/masked/abc">https://example.test/masked/abc</a>'),
        page,
      );
      expect(parsed.links.single.host, 'Download page');
    });

    test('a page with no post gives nothing', () {
      expect(ThreadParser.parse('<html></html>', page).links, isEmpty);
    });
  });

  group('changelog', () {
    String spoiler(String title, String body) => '<div class="bbCodeSpoiler"><button class="bbCodeSpoiler-button">'
        '$title</button><div class="bbCodeSpoiler-content">$body</div></div>';

    test('splits a changelog spoiler by version', () {
      final parsed = ThreadParser.parse(
        thread(spoiler('Changelog', 'v0.6<br />- New route<br />- Fixed a crash<br />Version 0.5.1:<br />Added a gallery')),
        page,
      );
      expect(parsed.changes.map((c) => c.version), ['0.6', '0.5.1']);
      expect(parsed.changes.first.notes, ['New route', 'Fixed a crash']);
      expect(parsed.changes.last.notes, ['Added a gallery']);
    });

    test('leaves other spoilers alone', () {
      final parsed = ThreadParser.parse(thread(spoiler('Screenshots', 'v0.6<br />nothing')), page);
      expect(parsed.changes, isEmpty);
    });

    test('a note that mentions a version is still a note', () {
      final parsed = ThreadParser.parse(
        thread(spoiler('Change-Log', 'v0.6<br />Saves from v0.5 still work')),
        page,
      );
      expect(parsed.changes.single.notes, ['Saves from v0.5 still work']);
    });
  });
}
