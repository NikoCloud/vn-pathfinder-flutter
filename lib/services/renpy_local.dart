import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Local fetch for Ren'Py (#25): a game's name, version and menu art read
/// from its own files, with nothing sent anywhere. Files are read loose from
/// game/ or out of its .rpa archives. Everything here only reads, and fails
/// quietly: an archive with a developer's own header or encryption just
/// yields less.
class LocalGameInfo {
  final String? title;
  final String? version;

  /// The main menu background, the best cover a game ships with.
  final Uint8List? cover;
  final String coverExt;
  final Uint8List? icon;

  const LocalGameInfo({this.title, this.version, this.cover, this.coverExt = '.png', this.icon});

  bool get isEmpty => title == null && version == null && cover == null && icon == null;
}

// ── RPA archives ─────────────────────────────────────────────────────────────

/// A Ren'Py archive (RPA-2.0 and RPA-3.0/3.2). The header gives the index's
/// offset and, from 3.0, a key; the index is a zlib-compressed Python pickle
/// mapping each file to its (offset, length, prefix) entries, with offsets and
/// lengths XOR'd with the key.
class RpaArchive {
  final File file;
  final Map<String, List<(int, int, Uint8List)>> _index;
  RpaArchive._(this.file, this._index);

  Iterable<String> get names => _index.keys;

  static RpaArchive? open(File file) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final head = latin1.decode(raf.readSync(256));
      final line = head.split('\n').first;
      final parts = line.split(' ');
      int offset, key = 0;
      if (parts.first == 'RPA-3.0' && parts.length >= 3) {
        offset = int.parse(parts[1], radix: 16);
        for (final k in parts.skip(2)) {
          key ^= int.parse(k, radix: 16);
        }
      } else if (parts.first == 'RPA-3.2' && parts.length >= 4) {
        offset = int.parse(parts[1], radix: 16);
        for (final k in parts.skip(3)) {
          key ^= int.parse(k, radix: 16);
        }
      } else if (parts.first == 'RPA-2.0' && parts.length >= 2) {
        offset = int.parse(parts[1], radix: 16);
      } else {
        return null; // a developer's own format
      }
      final indexSize = raf.lengthSync() - offset;
      if (offset < 0 || indexSize <= 0 || indexSize > _maxIndexBytes) return null;
      raf.setPositionSync(offset);
      final raw = inflateCapped(raf.readSync(indexSize), _maxIndexBytes * 8);
      if (raw == null) return null;
      final obj = Unpickler(raw).load();
      if (obj is! Map) return null;
      final index = <String, List<(int, int, Uint8List)>>{};
      obj.forEach((name, entries) {
        if (entries is! List) return;
        final list = <(int, int, Uint8List)>[];
        for (final e in entries) {
          if (e is! List || e.length < 2 || e[0] is! int || e[1] is! int) continue;
          final prefix = e.length > 2 ? _bytesOf(e[2]) : Uint8List(0);
          list.add(((e[0] as int) ^ key, (e[1] as int) ^ key, prefix));
        }
        index[_stringOf(name)] = list;
      });
      return RpaArchive._(file, index);
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  /// A file's bytes, or null when it isn't in this archive.
  Uint8List? read(String name) {
    final entries = _index[name];
    if (entries == null || entries.isEmpty) return null;
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final out = BytesBuilder(copy: false);
      for (final (offset, length, prefix) in entries) {
        out.add(prefix);
        raf.setPositionSync(offset);
        out.add(raf.readSync(length - prefix.length));
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }
}

String _stringOf(Object? v) => v is String ? v : v is Uint8List ? latin1.decode(v) : '$v';
Uint8List _bytesOf(Object? v) =>
    v is Uint8List ? v : v is String ? Uint8List.fromList(latin1.encode(v)) : Uint8List(0);

// ── A minimal pickle reader ──────────────────────────────────────────────────

class _Mark {
  const _Mark();
}

class _Global {
  final String module, name;
  const _Global(this.module, this.name);
}

/// Reads the pickle subset Ren'Py's archive indexes use: dicts, lists,
/// tuples (as lists), ints, strings and bytes, protocols 0 to 5. Objects it
/// can't build become null; the one call it does run is _codecs.encode,
/// which Python 3 uses to pickle Python 2 byte strings.
class Unpickler {
  final Uint8List _b;
  int _i = 0;
  final _stack = <Object?>[];
  final _memo = <int, Object?>{};
  Unpickler(this._b);

  int _u8() => _b[_i++];
  int _le(int n) {
    var v = 0;
    for (var k = 0; k < n; k++) {
      v |= _b[_i + k] << (8 * k);
    }
    _i += n;
    return v;
  }

  Uint8List _take(int n) {
    final out = Uint8List.sublistView(_b, _i, _i + n);
    _i += n;
    return out;
  }

  String _line() {
    final start = _i;
    while (_b[_i] != 0x0a) {
      _i++;
    }
    final s = latin1.decode(_b.sublist(start, _i));
    _i++;
    return s;
  }

  int _signedLong(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    var v = BigInt.zero;
    for (var k = bytes.length - 1; k >= 0; k--) {
      v = (v << 8) | BigInt.from(bytes[k]);
    }
    if (bytes.last & 0x80 != 0) v -= BigInt.one << (8 * bytes.length);
    return v.toInt();
  }

  List<Object?> _popMark() {
    final m = _stack.lastIndexWhere((e) => e is _Mark);
    final items = _stack.sublist(m + 1);
    _stack.removeRange(m, _stack.length);
    return items;
  }

  Object? load() {
    while (_i < _b.length) {
      final op = _u8();
      switch (op) {
        case 0x80: // PROTO
          _i++;
        case 0x95: // FRAME
          _i += 8;
        case 0x2e: // STOP
          return _stack.isEmpty ? null : _stack.removeLast();
        case 0x28: // MARK
          _stack.add(const _Mark());
        case 0x7d: // EMPTY_DICT
          _stack.add(<Object?, Object?>{});
        case 0x5d: // EMPTY_LIST
          _stack.add(<Object?>[]);
        case 0x29: // EMPTY_TUPLE
          _stack.add(<Object?>[]);
        case 0x64: // DICT
          final items = _popMark();
          _stack.add({for (var k = 0; k + 1 < items.length; k += 2) items[k]: items[k + 1]});
        case 0x6c: // LIST
        case 0x74: // TUPLE
          _stack.add(_popMark());
        case 0x85: // TUPLE1
          _stack.add([_stack.removeLast()]);
        case 0x86: // TUPLE2
          final b = _stack.removeLast(), a = _stack.removeLast();
          _stack.add([a, b]);
        case 0x87: // TUPLE3
          final c = _stack.removeLast(), b = _stack.removeLast(), a = _stack.removeLast();
          _stack.add([a, b, c]);
        case 0x61: // APPEND
          final v = _stack.removeLast();
          (_stack.last as List).add(v);
        case 0x65: // APPENDS
          final items = _popMark();
          (_stack.last as List).addAll(items);
        case 0x73: // SETITEM
          final v = _stack.removeLast(), k = _stack.removeLast();
          (_stack.last as Map)[k] = v;
        case 0x75: // SETITEMS
          final items = _popMark();
          final m = _stack.last as Map;
          for (var k = 0; k + 1 < items.length; k += 2) {
            m[items[k]] = items[k + 1];
          }
        case 0x4a: // BININT
          final v = _le(4);
          _stack.add(v >= 0x80000000 ? v - 0x100000000 : v);
        case 0x4b: // BININT1
          _stack.add(_u8());
        case 0x4d: // BININT2
          _stack.add(_le(2));
        case 0x8a: // LONG1
          _stack.add(_signedLong(_take(_u8())));
        case 0x8b: // LONG4
          _stack.add(_signedLong(_take(_le(4))));
        case 0x49: // INT
          final s = _line();
          _stack.add(s == '01' ? true : s == '00' ? false : int.parse(s));
        case 0x4c: // LONG
          _stack.add(int.parse(_line().replaceAll('L', '')));
        case 0x58: // BINUNICODE
          _stack.add(utf8.decode(_take(_le(4)), allowMalformed: true));
        case 0x8c: // SHORT_BINUNICODE
          _stack.add(utf8.decode(_take(_u8()), allowMalformed: true));
        case 0x8d: // BINUNICODE8
          _stack.add(utf8.decode(_take(_le(8)), allowMalformed: true));
        case 0x56: // UNICODE
          _stack.add(_line());
        case 0x54: // BINSTRING
          _stack.add(Uint8List.fromList(_take(_le(4))));
        case 0x55: // SHORT_BINSTRING
          _stack.add(Uint8List.fromList(_take(_u8())));
        case 0x42: // BINBYTES
          _stack.add(Uint8List.fromList(_take(_le(4))));
        case 0x43: // SHORT_BINBYTES
          _stack.add(Uint8List.fromList(_take(_u8())));
        case 0x8e: // BINBYTES8
          _stack.add(Uint8List.fromList(_take(_le(8))));
        case 0x53: // STRING
          final s = _line();
          _stack.add(Uint8List.fromList(latin1.encode(s.length >= 2 ? s.substring(1, s.length - 1) : s)));
        case 0x4e: // NONE
          _stack.add(null);
        case 0x88: // NEWTRUE
          _stack.add(true);
        case 0x89: // NEWFALSE
          _stack.add(false);
        case 0x71: // BINPUT
          _memo[_u8()] = _stack.last;
        case 0x72: // LONG_BINPUT
          _memo[_le(4)] = _stack.last;
        case 0x70: // PUT
          _memo[int.parse(_line())] = _stack.last;
        case 0x94: // MEMOIZE
          _memo[_memo.length] = _stack.last;
        case 0x68: // BINGET
          _stack.add(_memo[_u8()]);
        case 0x6a: // LONG_BINGET
          _stack.add(_memo[_le(4)]);
        case 0x67: // GET
          _stack.add(_memo[int.parse(_line())]);
        case 0x63: // GLOBAL
          final module = _line();
          _stack.add(_Global(module, _line()));
        case 0x93: // STACK_GLOBAL
          final name = _stack.removeLast(), module = _stack.removeLast();
          _stack.add(_Global(_stringOf(module), _stringOf(name)));
        case 0x52: // REDUCE
          final args = _stack.removeLast(), fn = _stack.removeLast();
          if (fn is _Global && fn.name == 'encode' && args is List && args.isNotEmpty && args[0] is String) {
            _stack.add(Uint8List.fromList(latin1.encode(args[0] as String)));
          } else {
            _stack.add(null);
          }
        case 0x81: // NEWOBJ
          _stack.removeLast();
          _stack.removeLast();
          _stack.add(null);
        case 0x62: // BUILD
          _stack.removeLast();
        case 0x30: // POP
          _stack.removeLast();
        case 0x31: // POP_MARK
          _popMark();
        case 0x32: // DUP
          _stack.add(_stack.last);
        default:
          throw FormatException('pickle opcode 0x${op.toRadixString(16)} not supported');
      }
    }
    return _stack.isEmpty ? null : _stack.last;
  }
}

// ── Compiled scripts ─────────────────────────────────────────────────────────

/// The text of a compiled script (.rpyc): its first slot, decompressed. The
/// AST is a pickle; its strings are searched, not unpickled.
String? rpycText(Uint8List bytes) {
  try {
    if (bytes.length < 10) return null;
    final head = latin1.decode(bytes.sublist(0, 10));
    Uint8List data;
    if (head == 'RENPY RPC2') {
      var at = 10;
      data = Uint8List(0);
      while (at + 12 <= bytes.length) {
        final bd = ByteData.sublistView(bytes, at, at + 12);
        final slot = bd.getUint32(0, Endian.little), start = bd.getUint32(4, Endian.little);
        final length = bd.getUint32(8, Endian.little);
        if (slot == 0) break;
        if (slot == 1) {
          data = Uint8List.sublistView(bytes, start, start + length);
          break;
        }
        at += 12;
      }
      if (data.isEmpty) return null;
    } else {
      data = bytes; // the old format: the whole file is zlib
    }
    final text = inflateCapped(data, 64 << 20);
    return text == null ? null : latin1.decode(text);
  } catch (_) {
    return null;
  }
}

final _rpyDefine = RegExp(r'''define\s+config\.(name|version)\s*=\s*(?:_\(\s*)?(["'])(.*?)\2''');

/// config.name and config.version from a script's source.
(String?, String?) _fromSource(String text) {
  String? name, version;
  for (final m in _rpyDefine.allMatches(text)) {
    final v = m[3]!.trim();
    if (v.isEmpty) continue;
    if (m[1] == 'name') name ??= v;
    if (m[1] == 'version') version ??= v;
  }
  return (name, version);
}

/// The same from a compiled script. A Define node keeps the store
/// ("store.config"), the variable ("name") and the value's source
/// (`_("Title")`), in an order that differs between Ren'Py versions. So: the
/// field as a whole word with "store.config" close by, then the first quoted
/// value after it, before the next Define. "Whole word" allows a following
/// `q`, the pickle opcode that often comes right after a string ("nameq"),
/// but not `_` or other letters ("name_version", "names").
///
/// The value's source is a whole pickled string, so it's accepted only when
/// the bytes just before it are that string's length (one byte for
/// SHORT_BINUNICODE, or four for BINUNICODE). Pickle bytes that happen to be
/// a quote mark never pass that.
final _source = RegExp(r'''_\(\s*(["'])([^\r\n\x00]{1,160}?)\1\s*\)|(["'])([^\r\n\x00]{1,80}?)\3''');

String? _valueAt(String text, RegExpMatch m) {
  final len = m.end - m.start, s = m.start;
  final short = s >= 1 && text.codeUnitAt(s - 1) == len;
  final long = s >= 5 &&
      text.codeUnitAt(s - 4) == (len & 0xff) &&
      text.codeUnitAt(s - 3) == (len >> 8 & 0xff) &&
      text.codeUnitAt(s - 2) == 0 &&
      text.codeUnitAt(s - 1) == 0;
  if (!short && !long) return null;
  final raw = (m[2] ?? m[4] ?? '').trim();
  if (raw.isEmpty) return null;
  // The text was read byte for byte; the game wrote UTF-8.
  try {
    return utf8.decode(latin1.encode(raw));
  } catch (_) {
    return raw;
  }
}

(String?, String?) _fromCompiled(String text) {
  String? find(String field) {
    for (final m in RegExp('(?<![A-Za-z0-9_])$field(?![_a-pr-z0-9])').allMatches(text)) {
      final from = (m.start - 400).clamp(0, text.length), to = (m.end + 400).clamp(0, text.length);
      if (!text.substring(from, to).contains('store.config')) continue;
      var after = text.substring(m.end, (m.end + 240).clamp(0, text.length));
      final next = after.indexOf('Define');
      if (next >= 0) after = after.substring(0, next);
      for (final v in _source.allMatches(after)) {
        final found = _valueAt(after, v);
        if (found != null && found != field) return found;
      }
    }
    return null;
  }

  return (find('name'), find('version'));
}

// ── Putting it together ──────────────────────────────────────────────────────

const _coverNames = ['gui/main_menu.png', 'gui/main_menu.jpg', 'gui/main_menu.webp'];
const _iconNames = ['gui/window_icon.png'];

/// Reads [gameFolder]'s own files. Loose files in game/ first, then its
/// archives. Null fields where nothing was found.
LocalGameInfo localFetch(Directory gameFolder) {
  final game = Directory(p.join(gameFolder.path, 'game'));
  if (!game.existsSync()) return const LocalGameInfo();

  final archives = <RpaArchive>[];
  try {
    for (final f in game.listSync().whereType<File>()) {
      if (!f.path.toLowerCase().endsWith('.rpa')) continue;
      final a = RpaArchive.open(f);
      if (a != null) archives.add(a);
    }
  } catch (_) {}

  /// options.rpy or .rpyc wherever the game keeps it (some use a
  /// subfolder), skipping translations under tl/; the shortest path wins.
  Uint8List? optionsFile(String ext) {
    final want = 'options.$ext';
    final loose = File(p.join(game.path, want));
    if (loose.existsSync()) {
      try {
        return loose.readAsBytesSync();
      } catch (_) {}
    }
    for (final a in archives) {
      final names = a.names.where((n) => (n == want || n.endsWith('/$want')) && !n.startsWith('tl/')).toList()
        ..sort((x, y) => x.length.compareTo(y.length));
      for (final n in names) {
        final b = a.read(n);
        if (b != null) return b;
      }
    }
    return null;
  }

  Uint8List? fileBytes(String rel) {
    final loose = File(p.joinAll([game.path, ...rel.split('/')]));
    if (loose.existsSync()) {
      try {
        return loose.readAsBytesSync();
      } catch (_) {}
    }
    for (final a in archives) {
      final b = a.read(rel);
      if (b != null) return b;
    }
    return null;
  }

  String? title, version;
  final src = optionsFile('rpy');
  if (src != null) (title, version) = _fromSource(utf8.decode(src, allowMalformed: true));
  if (title == null || version == null) {
    final compiled = optionsFile('rpyc');
    final text = compiled == null ? null : rpycText(compiled);
    if (text != null) {
      final (n, v) = _fromCompiled(text);
      title ??= n;
      version ??= v;
    }
  }

  Uint8List? cover;
  var coverExt = '.png';
  for (final name in _coverNames) {
    cover = fileBytes(name);
    if (cover != null) {
      coverExt = p.extension(name);
      break;
    }
  }
  Uint8List? icon;
  for (final name in _iconNames) {
    icon = fileBytes(name);
    if (icon != null) break;
  }
  return LocalGameInfo(title: title, version: version, cover: cover, coverExt: coverExt, icon: icon);
}

/// An archive index bigger than this isn't a real game's.
const _maxIndexBytes = 32 << 20;

/// zlib-decompresses [data], or null when the result would pass [limit]
/// bytes, so a crafted file can't fill the memory.
Uint8List? inflateCapped(List<int> data, int limit) {
  final out = _CappedSink(limit);
  try {
    final input = zlib.decoder.startChunkedConversion(out);
    for (var at = 0; at < data.length; at += 1 << 16) {
      input.add(data.sublist(at, at + (1 << 16) > data.length ? data.length : at + (1 << 16)));
    }
    input.close();
    return out.bytes.takeBytes();
  } on _TooBig {
    return null;
  }
}

class _TooBig implements Exception {
  const _TooBig();
}

class _CappedSink implements Sink<List<int>> {
  final int limit;
  final bytes = BytesBuilder(copy: false);
  _CappedSink(this.limit);

  @override
  void add(List<int> chunk) {
    bytes.add(chunk);
    if (bytes.length > limit) throw const _TooBig();
  }

  @override
  void close() {}
}
