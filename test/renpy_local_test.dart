import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/renpy_local.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';

late Directory root;

/// A pickle (protocol 2) of {name: [(offset, length, b'')]}, as Ren'Py writes
/// an RPA-3.0 index.
Uint8List _pickleIndex(Map<String, (int, int)> entries) {
  final b = BytesBuilder()..add([0x80, 2, 0x7d, 0x28]);
  for (final e in entries.entries) {
    final name = utf8.encode(e.key);
    b
      ..add([0x58])
      ..add((ByteData(4)..setUint32(0, name.length, Endian.little)).buffer.asUint8List())
      ..add(name)
      ..add([0x5d, 0x4a])
      ..add((ByteData(4)..setInt32(0, e.value.$1, Endian.little)).buffer.asUint8List())
      ..add([0x4a])
      ..add((ByteData(4)..setInt32(0, e.value.$2, Endian.little)).buffer.asUint8List())
      ..add([0x55, 0, 0x87, 0x61]); // SHORT_BINSTRING '', TUPLE3, APPEND
  }
  b.add([0x75, 0x2e]); // SETITEMS, STOP
  return b.takeBytes();
}

/// Writes an RPA-3.0 archive holding [files], with [key] scrambling offsets.
File _rpa(String path, Map<String, List<int>> files, {int key = 0x42424242}) {
  final body = BytesBuilder();
  const headerLen = 51;
  final spots = <String, (int, int)>{};
  var at = headerLen;
  for (final f in files.entries) {
    spots[f.key] = (at ^ key, f.value.length ^ key);
    body.add(f.value);
    at += f.value.length;
  }
  final index = zlib.encode(_pickleIndex(spots));
  final header = 'RPA-3.0 ${at.toRadixString(16).padLeft(16, '0')} ${key.toRadixString(16).padLeft(8, '0')}\n';
  final out = BytesBuilder()
    ..add(latin1.encode(header.padRight(headerLen - 1)).sublist(0, headerLen - 1))
    ..add([0x0a])
    ..add(body.takeBytes())
    ..add(index);
  return File(path)..writeAsBytesSync(out.takeBytes());
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('vnp_local'));
  tearDown(() => root.deleteSync(recursive: true));

  test('reads the index of an RPA-3.0 archive and its files back out', () {
    final f = _rpa(p.join(root.path, 'archive.rpa'), {
      'gui/main_menu.png': [1, 2, 3, 4],
      'options.rpy': utf8.encode('define config.name = _("Packed Game")\ndefine config.version = "0.7"\n'),
    });
    final a = RpaArchive.open(f)!;
    expect(a.names, containsAll(['gui/main_menu.png', 'options.rpy']));
    expect(a.read('gui/main_menu.png'), [1, 2, 3, 4]);
    expect(a.read('missing.png'), isNull);
  });

  test("a developer's own archive header is skipped quietly", () {
    final f = File(p.join(root.path, 'x.rpa'))..writeAsStringSync('hT4\$5Hi1 0000000000000010\nrubbish');
    expect(RpaArchive.open(f), isNull);
  });

  test('local fetch reads name, version and menu art, loose or from an archive', () {
    final game = Directory(p.join(root.path, 'Game', 'game'))..createSync(recursive: true);
    _rpa(p.join(game.path, 'archive.rpa'), {
      'gui/main_menu.png': [9, 9, 9],
      'scripts/options.rpy': utf8.encode('define config.name = _("Packed Game")\ndefine config.version = "0.7"\n'),
      'tl/russian/options.rpy': utf8.encode('define config.name = _("Wrong")\n'),
    });
    File(p.join(game.path, 'gui', 'window_icon.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([5]);
    final info = localFetch(Directory(p.join(root.path, 'Game')));
    expect(info.title, 'Packed Game');
    expect(info.version, '0.7');
    expect(info.cover, [9, 9, 9]);
    expect(info.icon, [5]);
  });

  test('a folder without a version takes the one local fetch saved; a folder version wins', () {
    for (final (name, expected) in [('Harbor Lights', '0.6'), ('Harbor Lights-0.5', '0.5')]) {
      final d = Directory(p.join(root.path, name));
      Directory(p.join(d.path, 'game')).createSync(recursive: true);
      File(p.join(d.path, 'game', 'script.rpy')).writeAsStringSync('');
      Directory(p.join(d.path, '.vnpf')).createSync();
      File(p.join(d.path, '.vnpf', 'metadata.json')).writeAsStringSync(jsonEncode({'local_version': '0.6'}));
      expect(scanGameVersion(d)!.versionStr, expected, reason: name);
    }
  });
}
