// #44: version records and what changed between versions. An invented game,
// written to a temp folder; nothing touches the app's real data.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/renpy_local.dart';
import 'package:vn_pathfinder/services/version_records.dart';

late Directory root;

/// A tiny Ren'Py game: [script] as game/script.rpy, and pictures by name and
/// byte count.
Directory _game(String name, String script, Map<String, int> pictures) {
  final dir = Directory(p.join(root.path, name));
  final game = Directory(p.join(dir.path, 'game'))..createSync(recursive: true);
  File(p.join(game.path, 'script.rpy')).writeAsStringSync(script);
  for (final e in pictures.entries) {
    final f = File(p.join(game.path, e.key))..parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(e.value, 1));
  }
  return dir;
}

VersionRecord _record(Directory game, String version) {
  final path = p.join(root.path, 'records', '$version.json.gz');
  countRenpyVersion(game, recordPath: path, version: version);
  return VersionRecord.read(path)!;
}

const _v1 = '''
define m = Character("Mara")
label start:
    scene bg harbour
    "The lanterns were already lit."
    m "You came back."
    m "I kept your room."
    menu:
        "Stay the night":
            m "Good."
        "Leave":
            m "Then go."
label cellar:
    m "Don't open that door."
    "It was locked anyway."
''';

const _v2 = '''
define m = Character("Mara")
label start:
    scene bg harbour
    "The lanterns were already lit."
    m "You came back at last."
    m "I kept your room."
    menu:
        "Stay the night":
            m "Good."
label garden:
    "Roses, everywhere."
''';

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnpf_records_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a record keeps lines by scene, menu choices, and every picture with its size', () {
    final r = _record(_game('Harbour-1', _v1, {'images/bg harbour.png': 10, 'gui/button.png': 3}), '1');
    expect(r.media, {'images/bg harbour.png': 10, 'gui/button.png': 3});
    expect([for (final l in r.lines) if (l.scene == 'start' && !l.isChoice) l.what],
        ['The lanterns were already lit.', 'You came back.', 'I kept your room.', 'Good.', 'Then go.']);
    expect([for (final l in r.lines) if (l.isChoice) l.what], ['Stay the night', 'Leave']);
    expect(r.lines.where((l) => l.scene == 'cellar').length, 2);
  });

  test('between two versions: removed, rewritten and added lines, gone scenes, and pictures', () {
    final a = _record(
        _game('Harbour-1', _v1, {
          'images/bg harbour.png': 10,
          'images/cellar door.png': 20,
          'images/mara smile.png': 30,
          'images/roses.jpg': 5,
          'gui/frame.png': 3,
        }),
        '1');
    final b = _record(
        _game('Harbour-2', _v2, {
          'images/bg harbour.png': 10, // same
          'images/mara smile.png': 31, // redrawn
          'images/roses.webp': 4, // re-encoded, not removed
          'images/garden.png': 40, // new
          'gui/frame.png': 9, // interface art: never reported
        }),
        '2');
    final d = diffRecords(a, b);
    expect(d.removedMedia, ['images/cellar door.png']);
    expect(d.changedMedia, ['images/mara smile.png']);
    expect(d.convertedMedia, {'images/roses.jpg': 'images/roses.webp'});
    expect(d.addedMedia, ['images/garden.png']);

    expect([for (final r in d.rewrittenLines) (r.before.what, r.after.what)], [('You came back.', 'You came back at last.')]);
    expect(d.removedLines.map((l) => l.what), containsAll(['Leave', 'Then go.', "Don't open that door.", 'It was locked anyway.']));
    expect(d.addedLines.map((l) => l.what), ['Roses, everywhere.']);
    expect(d.removedScenes, ['cellar']);
    expect(d.addedScenes, ['garden']);
  });

  test('no longer in the game: what earlier versions had, with the last version that had it', () {
    final one = _record(_game('Harbour-1', _v1, {'images/cellar door.png': 20, 'images/bg harbour.png': 10}), '1');
    // 1.5 still has the cellar scene and its picture; 2 drops both.
    final half = _record(_game('Harbour-15', _v1, {'images/cellar door.png': 21, 'images/bg harbour.png': 10}), '1.5');
    final two = _record(_game('Harbour-2', _v2, {'images/bg harbour.png': 10}), '2');
    final g = goneSince([one, half, two]);
    expect([for (final x in g.media) (x.item, x.lastVersion)], [('images/cellar door.png', '1.5')]);
    final cellar = g.lines.firstWhere((x) => x.item.what == "Don't open that door.");
    expect(cellar.lastVersion, '1.5');
  });

  test('a version compared with itself has no differences', () {
    final a = _record(_game('Harbour-1', _v1, {'images/bg harbour.png': 10}), '1');
    expect(diffRecords(a, a).empty, isTrue);
  });

  test('record paths are safe file names and differ by version', () {
    expect(p.basename(recordPath('lanternbay', '0.4 "Final"/b')), isNot(contains('/')));
    expect(recordPath('lanternbay', '0.4'), isNot(recordPath('lanternbay', '0.5')));
  });
}
