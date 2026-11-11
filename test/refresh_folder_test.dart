import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
  int scans = 0;
  @override
  Future<void> scan() async => scans++;
}

Directory _game(Directory root, String name) {
  final d = Directory(p.join(root.path, name));
  Directory(p.join(d.path, 'game')).createSync(recursive: true);
  File(p.join(d.path, 'game', 'script.rpy')).writeAsStringSync('label start:\n    return\n');
  return d;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_refresh'));
  tearDown(() => root.deleteSync(recursive: true));

  // Local fetch's Apply waited for a scan of the whole library to show a
  // change to one game.
  test('one game is read again without scanning the library', () async {
    final a = _game(root, 'Anchor-0.2-pc'), b = _game(root, 'Beacon-0.4-pc');
    final groups = [
      for (final d in [a, b])
        () {
          final v = scanGameVersion(d)!;
          return GameGroup(baseKey: v.baseKey, displayName: v.displayName, versions: [v]);
        }(),
    ];
    late _Library lib;
    final c = ProviderContainer(overrides: [libraryProvider.overrideWith((ref) => lib = _Library(ref, groups))]);
    addTearDown(c.dispose);
    c.read(libraryProvider);
    final beaconBefore = c.read(libraryProvider).groups.last;

    await saveGameMetadata(a, {'title': 'Zenith Anchor'});
    expect(await lib.refreshFolder(a), isTrue);

    final after = c.read(libraryProvider).groups;
    expect(after.map((g) => g.effectiveTitle), ['Beacon', 'Zenith Anchor'], reason: 'renamed, and sorted by its new title');
    expect(identical(after.first, beaconBefore), isTrue, reason: 'the other game is untouched');
    expect(lib.scans, 0);
  });

  test("a folder that isn't in the library is left to a full scan", () async {
    final a = _game(root, 'Anchor-0.2-pc');
    late _Library lib;
    final c = ProviderContainer(overrides: [libraryProvider.overrideWith((ref) => lib = _Library(ref, const []))]);
    addTearDown(c.dispose);
    c.read(libraryProvider);
    expect(await lib.refreshFolder(a), isFalse);
  });
}
