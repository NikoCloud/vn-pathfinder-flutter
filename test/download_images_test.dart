// Fetch Metadata's image download, against a real local web server.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

void main() {
  late HttpServer server;
  late Directory game;
  late String base;

  setUp(() async {
    game = Directory.systemTemp.createTempSync('vnp_images');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    // /ok/… serves an image; anything else refuses it, like a login-only forum file.
    server.listen((req) async {
      if (req.uri.path.startsWith('/ok/')) {
        req.response.headers.contentType = ContentType('image', 'jpeg');
        req.response.add([1, 2, 3]);
      } else {
        req.response.statusCode = 403;
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    game.deleteSync(recursive: true);
  });

  File vnpf(String name) => File(p.join(game.path, '.vnpf', name));
  List<String> saved() => (Directory(p.join(game.path, '.vnpf')).listSync().map((f) => p.basename(f.path)).toList()..sort());

  test('a missing cover does not stop the screenshots', () async {
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/refused/cover.jpg',
      screenshotUrls: ['$base/ok/one.jpg', '$base/ok/two.jpg'],
    );
    expect(saved(), ['screenshot_1.jpg', 'screenshot_2.jpg']);
  });

  test('a failed screenshot leaves no gap in the numbering', () async {
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/ok/cover.jpg',
      screenshotUrls: ['$base/refused/one.jpg', '$base/ok/two.jpg'],
    );
    expect(saved(), ['cover.jpg', 'screenshot_1.jpg']);
  });

  test('a re-fetch without a cover keeps the old cover and replaces the screenshots', () async {
    vnpf('cover.jpg').createSync(recursive: true);
    vnpf('cover.jpg').writeAsBytesSync([9]);
    vnpf('screenshot_1.png').writeAsBytesSync([9]);
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/refused/cover.jpg',
      screenshotUrls: ['$base/ok/one.jpg'],
    );
    expect(saved(), ['cover.jpg', 'screenshot_1.jpg']);
    expect(vnpf('cover.jpg').readAsBytesSync(), [9]);
    expect(vnpf('screenshot_1.jpg').readAsBytesSync(), [1, 2, 3]);
  });

  test('a re-fetch that only gets a cover keeps the old screenshots', () async {
    vnpf('screenshot_1.png').createSync(recursive: true);
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/ok/cover.jpg',
      screenshotUrls: ['$base/refused/one.jpg'],
    );
    expect(saved(), ['cover.jpg', 'screenshot_1.png']);
  });

  test('a refused full-size image falls back to its public thumbnail', () async {
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/refused/cover.jpg',
      screenshotUrls: ['$base/refused/full-one.jpg', '$base/refused/full-two.jpg'],
      previewUrls: {
        '$base/refused/full-one.jpg': '$base/ok/thumb-one.jpg',
        '$base/refused/full-two.jpg': '$base/refused/thumb-two.jpg',
      },
    );
    expect(saved(), ['screenshot_1.jpg']);
  });

  test('a logged-out page gives the thumbnail for an image embedded at full size', () {
    const page = '''
<article class="message-body"><div class="bbWrapper">
<a href="https://lewdcorner.com/attachments/cover-png.402350/" target="_blank"><img src="https://lewdcorner.com/data/attachments/400/400789-abc.jpg?hash=2-r" srcset="" class="bbImage" /></a>
<a href="https://lewdcorner.com/threads/other.1/">not an attachment</a>
</div></article>''';
    expect(MetadataService.guestPreviews(page), {
      'https://lewdcorner.com/attachments/cover-png.402350/':
          'https://lewdcorner.com/data/attachments/400/400789-abc.jpg?hash=2-r',
    });
  });

  group('downloadBestImages', () {
    MetadataResult source(String cover, List<String> shots,
            [Map<String, String> previews = const {}, String title = 'Game', String developer = 'Studio']) =>
        MetadataResult(
          provider: 'x',
          id: 'x',
          title: title,
          developer: developer,
          sourceUrl: '',
          coverUrl: cover,
          screenshotUrls: shots,
          previewUrls: previews,
        );

    test('another source replaces thumbnails with full-size images', () async {
      final result = await MetadataService.downloadBestImages(gameFolder: game, sources: [
        source('$base/gone/cover.jpg', ['$base/gone/one.jpg'],
            {'$base/gone/cover.jpg': '$base/ok/thumb-cover.jpg', '$base/gone/one.jpg': '$base/ok/thumb-one.jpg'}),
        source('$base/ok/cover.png', ['$base/ok/one.png', '$base/ok/two.png']),
      ]);
      expect(result, (saved: 3, thumbnails: 0));
      expect(saved(), ['cover.png', 'screenshot_1.png', 'screenshot_2.png']);
    });

    test("another game's images are never used, however good they are", () async {
      final thumbs = {'$base/gone/one.jpg': '$base/ok/thumb-one.jpg'};
      // Lost Daughter's saved F95Zone link leads to Long Lost Daughter.
      final longLost = source('$base/ok/cover.png', ['$base/ok/one.png'], const {}, 'Long Lost Daughter', 'Tawny Fairquim Frolics');
      // Two different games are called Guilty Pleasure.
      final sameTitle = source('$base/ok/cover.png', ['$base/ok/one.png'], const {}, 'Game', 'Someone Else');
      // Nothing says who made it, so it can't be trusted.
      final unknown = source('$base/ok/cover.png', ['$base/ok/one.png'], const {}, 'Game', '');
      final result = await MetadataService.downloadBestImages(gameFolder: game, sources: [
        source('$base/gone/cover.jpg', ['$base/gone/one.jpg'], thumbs),
        longLost,
        sameTitle,
        unknown,
      ]);
      expect(result, (saved: 1, thumbnails: 1));
      expect(saved(), ['screenshot_1.jpg']);
    });

    test('names that differ slightly still count as the same game', () {
      final a = source('', [], const {}, 'Long Road Home', 'Some Studio');
      final b = source('', [], const {}, 'Long road home!', 'Some Studio Productions');
      expect(MetadataService.sameGame(a, b), isTrue);
    });

    test('thumbnails are kept when no other source has anything', () async {
      final result = await MetadataService.downloadBestImages(gameFolder: game, sources: [
        source('$base/gone/cover.jpg', [], {'$base/gone/cover.jpg': '$base/ok/thumb-cover.jpg'}),
        source('$base/gone/cover2.png', ['$base/gone/one.png']),
      ]);
      expect(result, (saved: 1, thumbnails: 1));
      expect(saved(), ['cover.jpg']);
    });

    test('the chosen source is left alone when it works', () async {
      final result = await MetadataService.downloadBestImages(gameFolder: game, sources: [
        source('$base/ok/cover.jpg', ['$base/ok/one.jpg']),
        source('$base/ok/cover.png', ['$base/ok/one.png']),
      ]);
      expect(result, (saved: 2, thumbnails: 0));
      expect(saved(), ['cover.jpg', 'screenshot_1.jpg']);
    });

    test('nothing available from anywhere', () async {
      final result = await MetadataService.downloadBestImages(gameFolder: game, sources: [
        source('$base/gone/cover.jpg', []),
      ]);
      expect(result, (saved: 0, thumbnails: 0));
    });
  });

  test('when nothing downloads, the existing images stay', () async {
    vnpf('cover.jpg').createSync(recursive: true);
    vnpf('screenshot_1.jpg').createSync();
    await MetadataService.downloadImages(
      gameFolder: game,
      coverUrl: '$base/refused/cover.jpg',
      screenshotUrls: ['$base/refused/one.jpg'],
    );
    expect(saved(), ['cover.jpg', 'screenshot_1.jpg']);
  });

  test('a .webp cover is found', () {
    vnpf('cover.webp').createSync(recursive: true);
    final group = GameGroup(baseKey: 'game', displayName: 'Game', versions: [
      GameVersion(
        folderName: 'Game-1.0',
        folderPath: game,
        baseKey: 'game',
        versionStr: '1.0',
        displayName: 'Game',
        localSaveDir: Directory('saves'),
      ),
    ]);
    expect(p.basename(groupCarouselPaths(group, null).first.path), 'cover.webp');
  });
}
