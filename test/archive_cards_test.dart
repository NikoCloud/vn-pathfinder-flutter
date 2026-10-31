import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/archive_item.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/screens/archive_screen.dart';
import 'package:vn_pathfinder/services/archive_cards.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

GameGroup game(String key, {List<String> versions = const ['1.0']}) => GameGroup(
      baseKey: key,
      displayName: key,
      versions: [
        for (final v in versions)
          GameVersion(
            folderName: '$key-$v',
            folderPath: Directory('$key-$v'),
            baseKey: key,
            versionStr: v,
            displayName: key,
            localSaveDir: Directory('saves'),
          ),
      ],
    );

ArchiveItem archive(String name, {String key = 'somegame', String version = '0.9'}) =>
    ArchiveItem(archivePath: File(name), baseKey: key, versionStr: version);

void main() {
  late Directory library;

  setUp(() => library = Directory.systemTemp.createTempSync('vnp_cards_'));
  tearDown(() => library.deleteSync(recursive: true));

  const draft = ArchiveCardDraft(
    metadata: {'title': 'Some Game', 'developer': 'Studio', 'tags_fetched': ['romance'], 'f95_url': 'https://example.test/threads/1/'},
    version: '0.9',
    nameHint: 'SomeGame',
  );

  group('guessing the game a patch is for', () {
    test('finds the game from the start of the file name', () {
      final hit = guessPatchGame('SomeGame_mod_v2', [game('othergame'), game('somegame')]);
      expect(hit?.baseKey, 'somegame');
    });

    test('finds the game anywhere in the file name', () {
      final hit = guessPatchGame('walkthrough-for-some-game', [game('somegame')]);
      expect(hit?.baseKey, 'somegame');
    });

    test('ignores spacing and punctuation in the game\'s key', () {
      expect(guessPatchGame('Paper_Cranes_Mod', [game('paper cranes')])?.baseKey, 'paper cranes');
    });

    test('takes the longest match', () {
      final hit = guessPatchGame('somegame2-mod', [game('somegame'), game('somegame2')]);
      expect(hit?.baseKey, 'somegame2');
    });

    test('a weak match guesses nothing', () {
      expect(guessPatchGame('sound-pack', [game('someone')]), isNull);
    });

    test('an entry with no installed version is never picked', () {
      expect(guessPatchGame('somegame', [const GameGroup(baseKey: 'somegame', displayName: 'x')]), isNull);
    });
  });

  group('what kind of patch an archive holds', () {
    test('patch files at the top or one folder down are loose', () {
      expect(isLoosePatchSet(['mod.rpa', 'mod.rpy']), isTrue);
      expect(isLoosePatchSet(['game/mod.rpyc', r'game\mod.py']), isTrue);
    });

    test('deeper files mean the mod has a structure of its own', () {
      expect(isLoosePatchSet(['game/mods/mod.rpy']), isFalse);
    });

    test('anything else alongside keeps it together', () {
      expect(isLoosePatchSet(['mod.rpy', 'images/art.png']), isFalse);
      expect(isLoosePatchSet(['mod.rpy', 'readme.txt']), isFalse);
    });

    test('an empty archive is not a patch', () {
      expect(isLoosePatchSet(const []), isFalse);
    });
  });

  group('storing an unpacked patch', () {
    late Directory unpacked;
    late Directory patches;

    setUp(() {
      unpacked = Directory(p.join(library.path, 'unpacked'))..createSync();
      patches = Directory(p.join(library.path, '.patches'))..createSync();
    });

    void write(String path, [String text = 'x']) {
      final file = File(p.join(unpacked.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    }

    Future<List<String>> store({Future<String?> Function(String)? choose}) => storeUnpackedPatch(
          unpacked,
          patches,
          folderName: 'Some Mod',
          chooseName: choose ?? (_) async => null,
        );

    test('loose patch files go in one by one', () async {
      write('game/mod.rpy');
      write('extra.rpa');
      final names = await store();
      expect(names, unorderedEquals(['mod.rpy', 'extra.rpa']));
      expect(File(p.join(patches.path, 'mod.rpy')).existsSync(), isTrue);
    });

    test('a loose file with a taken name gets a new one', () async {
      File(p.join(patches.path, 'mod.rpy')).writeAsStringSync('old');
      write('mod.rpy');
      expect(await store(), ['mod_2.rpy']);
    });

    test('a mod with its own structure stays whole', () async {
      write('game/mods/mod.rpy');
      write('game/images/art.png');
      expect(await store(), ['Some Mod']);
      expect(File(p.join(patches.path, 'Some Mod', 'mods', 'mod.rpy')).existsSync(), isTrue);
      expect(File(p.join(patches.path, 'Some Mod', 'images', 'art.png')).existsSync(), isTrue);
    });

    test('several top-level items are wrapped in a folder', () async {
      write('mod.rpy');
      write('readme.txt');
      expect(await store(), ['Some Mod']);
      expect(File(p.join(patches.path, 'Some Mod', 'readme.txt')).existsSync(), isTrue);
    });

    test('a taken folder name asks for another', () async {
      Directory(p.join(patches.path, 'Some Mod')).createSync();
      write('a/b/mod.rpy');
      expect(await store(choose: (_) async => 'Renamed'), ['Renamed']);
    });

    test('declining the new name stops it', () async {
      Directory(p.join(patches.path, 'Some Mod')).createSync();
      write('a/b/mod.rpy');
      expect(store(), throwsA(contains('already exists')));
    });

    test('an empty archive is an error', () {
      expect(store(), throwsA(contains('no files')));
    });
  });

  group('which game an archive belongs to', () {
    test('where it was extracted to comes first', () {
      final other = game('renamed');
      final hit = gameForArchive(archive('a.zip'), [game('somegame'), other], other.versions.first.folderPath.path);
      expect(hit, same(other));
    });

    test('otherwise the game with its name', () {
      expect(gameForArchive(archive('a.zip'), [game('somegame')], null)?.baseKey, 'somegame');
    });

    test('an archive-only entry is no game', () {
      expect(gameForArchive(archive('a.zip'), [const GameGroup(baseKey: 'somegame', displayName: 'x')], null), isNull);
    });
  });

  group('whether an archive can safely go', () {
    test('its exact version is installed', () {
      expect(archiveIsInstalled(archive('a.zip', version: '1.0'), game('somegame')), isTrue);
    });

    test('an update you have not extracted is not', () {
      expect(archiveIsInstalled(archive('a.zip', version: '2.0'), game('somegame')), isFalse);
    });

    test('an archive with no version or no game is not', () {
      expect(archiveIsInstalled(archive('a.zip', version: ''), game('somegame')), isFalse);
      expect(archiveIsInstalled(archive('a.zip'), null), isFalse);
    });
  });

  group('saving and reading', () {
    test('a card comes back with what went in', () async {
      await ArchiveCards.create(library.path, 'Some Game-0.9-pc.zip', draft);
      final card = ArchiveCards.all(library.path).single;
      expect(card.fileName, 'Some Game-0.9-pc.zip');
      expect(card.title, 'Some Game');
      expect(card.developer, 'Studio');
      expect(card.tags, ['romance']);
      expect(card.version, '0.9');
      expect(card.cover, isNull);
    });

    test('a library with no cards is fine', () {
      expect(ArchiveCards.all(library.path), isEmpty);
    });

    test('a broken folder is skipped', () async {
      await ArchiveCards.create(library.path, 'a.zip', draft);
      Directory(p.join(ArchiveCards.root(library.path).path, 'stray')).createSync();
      File(p.join(ArchiveCards.root(library.path).path, 'note.txt')).writeAsStringSync('x');
      expect(ArchiveCards.all(library.path).length, 1);
    });

    test('the cover is found by its usual names', () async {
      final card = await ArchiveCards.create(library.path, 'a.zip', draft);
      File(p.join(card.vnpf.path, 'cover.webp')).writeAsStringSync('x');
      expect(p.basename(ArchiveCard.read(card.folder)!.cover!), 'cover.webp');
    });

    test('the scanner sees the data as neither a game nor a file', () async {
      final file = File(p.join(library.path, 'a.zip'))..writeAsStringSync('x');
      await ArchiveCards.create(library.path, 'a.zip', draft);
      final groups = await ScannerService.scanAll(library);
      expect(groups.expand((g) => g.versions), isEmpty);
      expect(groups.expand((g) => g.archives).single.archivePath.path, file.path);
    });
  });

  group('assigning', () {
    test('a renamed file can be linked back', () async {
      final card = await ArchiveCards.create(library.path, 'old.zip', draft);
      card.linkTo('new name.zip');
      expect(ArchiveCards.all(library.path).single.fileName, 'new name.zip');
    });

    test('an unlinked card waits, and keeps its data', () async {
      final card = await ArchiveCards.create(library.path, 'a.zip', draft);
      card.linkTo('');
      final back = ArchiveCards.all(library.path).single;
      expect(back.fileName, isEmpty);
      expect(back.title, 'Some Game');
    });

    test('a file can take a copy of a game\'s data', () async {
      final game = Directory(p.join(library.path, 'SomeGame-0.8'))..createSync();
      await saveGameMetadata(game, {'title': 'Some Game'});
      File(p.join(game.path, '.vnpf', 'cover.png')).writeAsStringSync('art');
      final version = GameVersion(
        folderName: 'SomeGame-0.8',
        folderPath: game,
        baseKey: 'somegame',
        versionStr: '0.8',
        displayName: 'SomeGame',
        localSaveDir: Directory('saves'),
      );
      final card = await ArchiveCards.fromGame(library.path, 'download(3).zip', version, version: '0.9', nameHint: 'SomeGame');
      expect(card.title, 'Some Game');
      expect(card.cover, isNotNull);
      expect(card.extractName, 'SomeGame-0.9');
      expect(File(p.join(game.path, '.vnpf', 'cover.png')).existsSync(), isTrue);
    });
  });

  group('extracting', () {
    test('the game takes the data, and the card is gone', () async {
      final card = await ArchiveCards.create(library.path, 'a.zip', draft);
      final game = Directory(p.join(library.path, 'SomeGame-0.9'))..createSync();
      card.moveInto(game);
      expect(loadGameMetadata(game)['title'], 'Some Game');
      expect(ArchiveCards.all(library.path), isEmpty);
    });

    test('a game with its own .vnpf keeps it', () async {
      final card = await ArchiveCards.create(library.path, 'a.zip', draft);
      final game = Directory(p.join(library.path, 'SomeGame-0.9'))..createSync();
      await saveGameMetadata(game, {'title': 'Mine'});
      card.moveInto(game);
      expect(loadGameMetadata(game)['title'], 'Mine');
      expect(ArchiveCards.all(library.path), isEmpty);
    });

    test('the name comes from the game when the version is known', () {
      const named = ArchiveCard.new;
      expect(named(library, fileName: 'x', version: '0.9', nameHint: 'SomeGame').extractName, 'SomeGame-0.9');
      expect(named(library, fileName: 'x', version: '0.9', metadata: {'title': 'Some Game'}).extractName, 'Some Game-0.9');
      expect(named(library, fileName: 'x', nameHint: 'SomeGame').extractName, isNull);
    });

    test('characters Windows refuses are dropped', () {
      const named = ArchiveCard.new;
      expect(
        named(library, fileName: 'x', version: '0.13 DEMO', metadata: {'title': 'Nazaris: The "Carefree" Reborn?'}).extractName,
        'Nazaris The Carefree Reborn-0.13 DEMO',
      );
    });

    test('an update lands in the game it belongs to', () {
      for (final (folder, name) in [('PaperCranes-0.7', 'Paper Cranes'), ('paper_cranes-0.7', 'paper cranes')]) {
        final (key, _, _) = parseFolderName(folder);
        final (updated, version, _) = parseFolderName('$name-0.9');
        expect(updated, key);
        expect(version, '0.9');
      }
    });
  });

  group('a draft from a download', () {
    RawFeedItem item() => RawFeedItem(
          id: 'x',
          source: 'lewdcorner',
          sourceLabel: 'LewdCorner',
          title: 'Some Game',
          rawBody: 'Developer: Feed Studio\nTags: comedy\nRating: 4.20 / 5\n[cover] https://example.test/feed.jpg',
          url: 'https://example.test/threads/1/',
        );

    const details = MetadataResult(
      provider: 'lewdcorner',
      id: 'x',
      title: 'A Thread Title',
      developer: 'Thread Studio',
      synopsis: 'From the thread',
      coverUrl: 'https://example.test/thread.jpg',
      sourceUrl: 'https://example.test/threads/1/',
      screenshotUrls: ['https://example.test/1.jpg'],
      tags: ['romance'],
    );

    test('the thread wins where it has an answer', () {
      final d = ArchiveCardDraft.build(title: 'Some Game', version: '0.9', source: 'lewdcorner', threadUrl: details.sourceUrl, item: item(), details: details);
      expect(d.metadata['title'], 'Some Game');
      expect(d.metadata['developer'], 'Thread Studio');
      expect(d.metadata['synopsis'], 'From the thread');
      expect(d.metadata['tags_fetched'], ['romance']);
      expect(d.coverUrl, 'https://example.test/thread.jpg');
      expect(d.screenshotUrls.length, 1);
    });

    test('with no thread, the card\'s own data is used', () {
      final d = ArchiveCardDraft.build(title: 'Some Game', version: '0.9', source: 'lewdcorner', threadUrl: item().url, item: item());
      expect(d.metadata['developer'], 'Feed Studio');
      expect(d.metadata['tags_fetched'], ['comedy']);
      expect(d.metadata['rating'], 4.2);
      expect(d.coverUrl, 'https://example.test/feed.jpg');
    });

    test('the link is the thread the file came from', () {
      final d = ArchiveCardDraft.build(title: 't', version: '', source: 'azc', threadUrl: 'https://example.test/threads/9/');
      expect(d.metadata['azc_url'], 'https://example.test/threads/9/');
      expect(d.metadata['source_url'], 'https://example.test/threads/9/');
    });
  });
}
