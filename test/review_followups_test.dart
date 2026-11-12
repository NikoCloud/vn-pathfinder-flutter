// Follow-ups from the review of support links, other games and itch.io
// discovery (#46). Invented games, developers and addresses throughout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/version_path.dart';
import 'package:vn_pathfinder/providers/update_provider.dart';
import 'package:vn_pathfinder/services/metadata_service.dart';

GameGroup _game(String key, {String developer = ''}) => GameGroup(
      baseKey: key,
      displayName: key,
      versions: [
        GameVersion(
          folderName: '$key-1.0',
          folderPath: Directory('$key-1.0'),
          baseKey: key,
          versionStr: '1.0',
          displayName: key,
          localSaveDir: Directory('saves'),
          metadata: {if (developer.isNotEmpty) 'developer': developer},
        ),
      ],
    );

void main() {
  group('a thread found by title', () {
    const check = UpdateCheckState(
      titleLinks: {'lanternrow': 42, 'harbourlights': 7},
      titleCreators: {'lanternrow': 'Tidewater Games', 'harbourlights': 'Someone Else'},
    );

    test('stands in for a saved link only when its creator is the developer', () {
      expect(matchedTitleLink(check, _game('lanternrow', developer: 'Tidewater Games Studio')), 42);
      expect(matchedTitleLink(check, _game('harbourlights', developer: 'Harbour Works')), isNull);
    });

    test('with the developer or the creator unknown, it only drives the update badge', () {
      expect(matchedTitleLink(check, _game('lanternrow')), isNull);
      const old = UpdateCheckState(titleLinks: {'lanternrow': 42});
      expect(matchedTitleLink(old, _game('lanternrow', developer: 'Tidewater Games')), isNull);
    });
  });

  group('itch.io creator pages guessed from a name', () {
    const game = MetadataResult(
      provider: 'itchio',
      id: 'https://tidewater.itch.io/lantern-row',
      title: 'Lantern Row',
      developer: '',
      sourceUrl: 'https://tidewater.itch.io/lantern-row',
    );

    test('are listed but never picked automatically', () {
      expect(MetadataService.isRelevantItchMatch(game, query: 'Lantern Row', developer: 'Tidewater'), isTrue);
      expect(
        MetadataService.isRelevantItchMatch(game.asUnverifiedCreator(), query: 'Lantern Row', developer: 'Tidewater'),
        isFalse,
      );
    });

    test('a known creator link makes the same page trusted', () {
      expect(
        MetadataService.isRelevantItchMatch(game.asUnverifiedCreator(),
            query: 'Lantern Row', developer: 'Tidewater', hintUrls: ['https://tidewater.itch.io/']),
        isTrue,
      );
    });
  });

  group('the version path', () {
    test("a forum's spelling of the installed version isn't a newer stop", () {
      final path = buildVersionPath(
        installed: ['3.6.5'],
        changelog: ['Chapter 3.6.5 Patched', 'Chapter 3.6'],
        latest: 'Chapter 3.6.5 Patched',
      );
      expect(path.map((n) => n.version), ['Chapter 3.6', '3.6.5']);
      expect(path.last.latest, isTrue);
      expect(path.last.installed, isTrue);
    });

    test('a really newer version still shows as the latest', () {
      final path = buildVersionPath(installed: ['0.4'], changelog: const [], latest: 'v0.5');
      expect(path.map((n) => n.version), ['0.4', 'v0.5']);
      expect(path.last.latest, isTrue);
    });
  });
}
