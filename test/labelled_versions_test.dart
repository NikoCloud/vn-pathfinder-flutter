import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_status.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

void main() {
  group('isClearlyNewer with chapter-style versions', () {
    test('the same kind of label compares by number, however it is written', () {
      expect(isClearlyNewer('Ch.3.6.5', 'Chapter-3.6'), isTrue);
      expect(isClearlyNewer('Chapter 3.6.5 Public', 'Chapter-3.6'), isTrue);
      expect(isClearlyNewer('Chapter 4', 'Chapter3.6'), isTrue);
      expect(isClearlyNewer('Ep. 5', 'Episode 4'), isTrue);
      expect(isClearlyNewer('Part 2', 'Pt 1'), isTrue);
    });

    test('equal or lower numbers are never newer, whatever words follow', () {
      expect(isClearlyNewer('Chapter 3.6', 'Chapter-3.6'), isFalse);
      expect(isClearlyNewer('Chapter 3.6 Public', 'Chapter-3.6'), isFalse);
      expect(isClearlyNewer('Ch.3.5', 'Chapter-3.6'), isFalse);
    });

    test('different kinds, or a label against a plain number, never compare', () {
      expect(isClearlyNewer('Episode 4', 'Chapter 3'), isFalse);
      expect(isClearlyNewer('0.4', 'Chapter-3'), isFalse);
      expect(isClearlyNewer('Chapter 4', '0.3'), isFalse);
    });

    test('a "v" version inside a label still wins', () {
      expect(isClearlyNewer('Part 8 v0.115', 'Part 8 v0.114'), isTrue);
      expect(isClearlyNewer('Chapter 2 v0.4', 'v0.3'), isTrue);
    });
  });

  test('a folder named Chapter-3.6 sees Ch.3.6.5 on the Feed as an update', () {
    final installed = parseFolderName('SinfulSummer-Chapter-3.6').$2;
    expect(isClearlyNewer('Ch.3.6.5', installed), isTrue, reason: 'installed=$installed');
    expect(isClearlyNewer('Chapter 3.6.5 Public', installed), isTrue);
    expect(isClearlyNewer('Chapter 3.6', installed), isFalse);
  });
}
