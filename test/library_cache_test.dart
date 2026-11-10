import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/library_cache.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

Directory _game(String rel) {
  final d = Directory(p.normalize(p.join(root.path, rel)));
  Directory(p.join(d.path, 'game', 'saves')).createSync(recursive: true);
  File(p.join(d.path, 'game', 'archive.rpa')).writeAsStringSync('');
  File(p.join(d.path, '${p.basename(rel).split('-').first}.exe')).writeAsStringSync('');
  return d;
}

/// What Ren'Py does when it saves: write <name>.new, rename it into place.
void _renpySave(Directory game, String name) {
  final saves = p.join(game.path, 'game', 'saves');
  File(p.join(saves, '$name.new')).writeAsStringSync('save');
  final target = File(p.join(saves, name));
  if (target.existsSync()) target.deleteSync();
  File(p.join(saves, '$name.new')).renameSync(target.path);
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_cache'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a full scan returns a cache entry per game, with its engine and save info', () async {
    final g = _game('Cat/Game-1.0-pc');
    _renpySave(g, '1-1-LT1.save');
    final r = await ScannerService.scanLibrary([root]);
    final entry = r.cache[g.path] as Map;
    expect(entry['engine'], 'renpy');
    expect((entry['saves'] as Map)['manual'], 1);
  });

  test('the quick pass reuses save info while the save folder is unchanged, and rereads after a save', () async {
    final g = _game('Game-1.0-pc');
    _renpySave(g, '1-1-LT1.save');
    final first = await ScannerService.scanLibrary([root]);

    // Mark the cached entry so reuse is visible.
    final cache = Map<String, dynamic>.from(first.cache);
    final entry = Map<String, dynamic>.from(cache[g.path] as Map);
    entry['saves'] = {...(entry['saves'] as Map), 'manual': 99};
    cache[g.path] = entry;

    final quick = await ScannerService.scanCached([root], cache);
    expect(quick.groups.single.versions.single.saves.manualSaves, 99, reason: 'unchanged: cached info used');

    await Future.delayed(const Duration(milliseconds: 1100));
    _renpySave(g, '2-1-LT1.save');
    final after = await ScannerService.scanCached([root], cache);
    expect(after.groups.single.versions.single.saves.manualSaves, 2, reason: 'a new save changes the folder time');
  });

  test('the quick pass skips games outside the library folders and ones that are gone', () async {
    final g = _game('Game-1.0-pc');
    final r = await ScannerService.scanLibrary([root]);
    final cache = {...r.cache, p.join(root.parent.path, 'Elsewhere-1.0'): r.cache[g.path]};
    g.deleteSync(recursive: true);
    final quick = await ScannerService.scanCached([root], cache);
    expect(quick.groups, isEmpty);
  });

  test('the cache file round-trips and ignores a damaged file', () {
    final f = File(p.join(root.path, 'library_cache.json'));
    LibraryCache.fileForTesting = f;
    addTearDown(() => LibraryCache.fileForTesting = null);
    LibraryCache.save({'X': {'engine': 'unity'}});
    expect((LibraryCache.load()['X'] as Map)['engine'], 'unity');
    f.writeAsStringSync('{not json');
    expect(LibraryCache.load(), isEmpty);
  });
}
