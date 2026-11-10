import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

void main() {
  group('download labels become folders the scanner reads back', () {
    test('a label with words around the number keeps the game and its number', () {
      final name = readableFolderName('Sinful Summer', 'Chapter 3.6.5 Patched')!;
      final (key, version, _) = parseFolderName(name);
      expect(key, 'sinfulsummer');
      expect(version, contains('3.6.5'));
    });

    test('"Ch." labels no longer swallow the version into the title', () {
      final (key, version, _) = parseFolderName(readableFolderName('Sinful Summer', 'Ch.3.6.5')!);
      expect(key, 'sinfulsummer');
      expect(version, contains('3.6.5'));
    });

    test('the new version sorts above the one already installed', () {
      final (_, v, _) = parseFolderName(readableFolderName('Sinful Summer', 'Chapter 3.6.5 Patched')!);
      expect(compareVersionStrings(v, 'Chapter-3.6'), greaterThan(0));
    });

    test('two sources labelling one version differently land in the same folder', () {
      expect(readableFolderName('Sinful Summer', 'Ch.3.6.5'),
          readableFolderName('Sinful Summer', 'Chapter 3.6.5 Patched'));
    });

    test('plain versions are kept as they are', () {
      expect(readableFolderName('Harbor Lights', '0.6'), 'Harbor Lights-0.6');
    });

    test('a pre-release word is kept so it sorts below the release', () {
      final (_, beta, _) = parseFolderName(readableFolderName('Game', '0.5 Beta')!);
      final (_, release, _) = parseFolderName(readableFolderName('Game', 'v0.5')!);
      expect(compareVersionStrings(beta, release), lessThan(0));
    });

    test('labels without a number are kept when they read back', () {
      final (key, version, _) = parseFolderName(readableFolderName('The Assistant', 'Final')!);
      expect(key, 'theassistant');
      expect(version, 'Final');
    });

    test('nothing readable gives null so the planner names it', () {
      expect(readableFolderName('', '0.6'), isNull);
    });
  });
}
