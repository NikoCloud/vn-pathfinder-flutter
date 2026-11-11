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
File _rpa(String path, Map<String, List<int>> files, {int key = 0x42424242, String magic = 'RPA-3.0 '}) {
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
  final header = '$magic${at.toRadixString(16).padLeft(16, '0')} ${key.toRadixString(16).padLeft(8, '0')}\n';
  final out = BytesBuilder()
    ..add(latin1.encode(header.padRight(headerLen - 1)).sublist(0, headerLen - 1))
    ..add([0x0a])
    ..add(body.takeBytes())
    ..add(index);
  return File(path)..writeAsBytesSync(out.takeBytes());
}

/// A PNG of [w]×[h]: noisy like real art, or one flat colour like Ren'Py's
/// stock menu background, which compresses to almost nothing.
Uint8List _png(int w, int h, {bool flat = false, int seed = 7}) {
  final raw = BytesBuilder();
  var r = seed;
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w * 3; x++) {
      r = (r * 1103515245 + 12345) & 0x7fffffff;
      raw.addByte(flat ? 40 : (r >> 16) & 0xff);
    }
  }
  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> data) {
    var c = 0xffffffff;
    for (final b in data) {
      c = crcTable[(c ^ b) & 0xff] ^ (c >> 8);
    }
    return c ^ 0xffffffff;
  }

  final out = BytesBuilder()..add([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  void chunk(String type, List<int> data) {
    final body = [...latin1.encode(type), ...data];
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(body)
      ..add((ByteData(4)..setUint32(0, crc(body))).buffer.asUint8List());
  }

  chunk('IHDR', (ByteData(13)
        ..setUint32(0, w)
        ..setUint32(4, h)
        ..setUint8(8, 8)
        ..setUint8(9, 2))
      .buffer
      .asUint8List());
  chunk('IDAT', zlib.encode(raw.takeBytes()));
  chunk('IEND', []);
  return out.takeBytes();
}

File _put(Directory game, String rel, List<int> bytes) =>
    File(p.joinAll([game.path, ...rel.split('/')]))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

List<int> _fixture(String name) => File(p.join('test', 'fixtures', 'local_fetch', name)).readAsBytesSync();

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
    final art = _png(640, 360);
    _rpa(p.join(game.path, 'archive.rpa'), {
      'gui/main_menu.png': art,
      'scripts/options.rpy': utf8.encode('define config.name = _("Packed Game")\ndefine config.version = "0.7"\n'),
      'tl/russian/options.rpy': utf8.encode('define config.name = _("Wrong")\n'),
    });
    File(p.join(game.path, 'gui', 'window_icon.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([5]);
    final info = localFetch(Directory(p.join(root.path, 'Game')));
    expect(info.title, 'Packed Game');
    expect(info.version, '0.7');
    expect(info.cover, art);
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

  test('compiled scripts: the name from build.name when config.name is empty, a version from a variable, '
      "and the main menu screen's own art over the stock background", () {
    final game = Directory(p.join(root.path, 'Packed', 'game'))..createSync(recursive: true);
    final art = _png(800, 450);
    _put(game, 'options.rpyc', _fixture('options.rpyc'));
    _rpa(p.join(game.path, 'scripts.rpa'), {'screens.rpyc': _fixture('screens.rpyc')});
    _put(game, 'gui/main_menu.png', _png(1280, 720, flat: true));
    _put(game, 'gui/Real Menu.png', art); // the screen says "gui/real menu.png"
    _put(game, 'gui/patreon.png', _png(200, 100, seed: 3));
    final info = localFetch(Directory(p.join(root.path, 'Packed')));
    expect(info.title, 'My Test Game');
    expect(info.version, '0.4b');
    expect(info.cover, art);
  });

  test('source scripts: accents, comments, image names and a menu screen in another file', () {
    final game = Directory(p.join(root.path, 'Diario', 'game'))..createSync(recursive: true);
    final bg = _png(960, 540, seed: 11);
    _put(game, 'options.rpy', [
      0xef, 0xbb, 0xbf, // a BOM, as some editors save
      ...utf8.encode('define config.name = _("Diario de mi perversión")\n'
          'define config.version = "0.7" # the demo\n'),
    ]);
    _put(game, 'my_screens.rpy', utf8.encode('image menu bg = "images/menu/bg_final.png"\n'
        'screen main_menu():\n'
        '    tag menu\n'
        '    add "menu bg"\n'
        '    textbutton _("Start") action Start()\n'
        'screen other():\n'
        '    add "gui/elsewhere.png"\n'));
    _put(game, 'images/menu/bg_final.png', bg);
    _put(game, 'gui/elsewhere.png', _png(1920, 1080, seed: 5));
    final info = localFetch(Directory(p.join(root.path, 'Diario')));
    expect(info.title, 'Diario de mi perversión');
    expect(info.version, '0.7');
    expect(info.cover, bg, reason: 'only what the main menu screen shows');
  });

  test("an image Ren'Py names from its file, and a background set by a ConditionSwitch", () {
    final game = Directory(p.join(root.path, 'Auto', 'game'))..createSync(recursive: true);
    final art = _png(1280, 720, seed: 9);
    _put(game, 'gui.rpy', utf8.encode('define gui.main_menu_background = ConditionSwitch(\n'
        '    "persistent.ending", "title screen",\n'
        '    "True", "gui/main_menu.png")\n'));
    _put(game, 'images/title screen.png', art);
    _put(game, 'gui/main_menu.png', _png(1280, 720, flat: true));
    expect(localFetch(Directory(p.join(root.path, 'Auto'))).cover, art);
  });

  test("only Ren'Py's stock menu art: no cover rather than a blank one", () {
    final game = Directory(p.join(root.path, 'Plain', 'game'))..createSync(recursive: true);
    _put(game, 'options.rpy', utf8.encode('define config.name = _("Plain")\n'));
    _put(game, 'gui/main_menu.png', _png(1920, 1080, flat: true));
    final info = localFetch(Directory(p.join(root.path, 'Plain')));
    expect(info.title, 'Plain');
    expect(info.cover, isNull);
  });

  test('picture sizes are read from PNG headers', () {
    expect(imageSize(_png(64, 32)), (64, 32));
    expect(imageSize(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test("an archive with a disguised header but RPA-3.0's layout still opens", () {
    final game = Directory(p.join(root.path, 'Hidden', 'game'))..createSync(recursive: true);
    _rpa(p.join(game.path, 'scripts.rpa'),
        {'options.rpy': utf8.encode('define config.name = _("Hidden")\n')},
        magic: r'hT4$5Hi1'); // no space before the offset, as one game ships it
    expect(localFetch(Directory(p.join(root.path, 'Hidden'))).title, 'Hidden');
  });

  test('a Python 2 compiled script: byte-string attribute names, items added to a defaultdict', () {
    final game = Directory(p.join(root.path, 'Old', 'game'))..createSync(recursive: true);
    _put(game, 'options.rpyc', _fixture('options_py2.rpyc'));
    final info = localFetch(Directory(p.join(root.path, 'Old')));
    expect(info.title, 'Old Engine Game');
    expect(info.version, '0.9');
  });

  test('a menu background picked by a function: the best of the pictures it picks from', () {
    final game = Directory(p.join(root.path, 'Random', 'game'))..createSync(recursive: true);
    final best = _png(1600, 900, seed: 21);
    _put(game, 'gui.rpy', utf8.encode('init python:\n'
        '    def get_random_background():\n'
        '        backgrounds = [\n'
        '            "gui/main menu/one.png",\n'
        '            "gui/main menu/two.png",\n'
        '        ]\n'
        '        return renpy.random.choice(backgrounds)\n'
        'define gui.main_menu_background = get_random_background()\n'));
    _put(game, 'gui/main menu/one.png', _png(800, 450, seed: 4));
    _put(game, 'gui/main menu/two.png', best);
    expect(localFetch(Directory(p.join(root.path, 'Random'))).cover, best);
  });

  test('the window title is used only when it names the game; a commented-out name beats the build name', () {
    final a = Directory(p.join(root.path, 'Promo', 'game'))..createSync(recursive: true);
    _put(a, 'options.rpy', utf8.encode('define config.name = _("   ")\n'
        'define config.window_title = _("SomeDev is creating Adult Games")\n'
        'define build.name = "MiUnicaHija"\n'));
    expect(localFetch(Directory(p.join(root.path, 'Promo'))).title, 'Mi Unica Hija');

    final b = Directory(p.join(root.path, 'Commented', 'game'))..createSync(recursive: true);
    _put(b, 'options.rpy', utf8.encode('# define config.name = _("The world beyond")\n'
        'define build.name = "theworldbeyond"\n'
        'define config.version = "{font=x.otf}Ch7{/font}"\n'));
    final info = localFetch(Directory(p.join(root.path, 'Commented')));
    expect(info.title, 'The world beyond');
    expect(info.version, 'Ch7', reason: 'text tags are not part of the version');
  });
}
