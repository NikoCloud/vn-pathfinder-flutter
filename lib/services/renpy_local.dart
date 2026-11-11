import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Local fetch for Ren'Py (#25): a game's name, version and menu art read
/// from its own files, with nothing sent anywhere. Scripts are read the way
/// Ren'Py saved them: source (.rpy) as text, compiled scripts (.rpyc)
/// unpickled into their statements, loose in game/ or out of its .rpa
/// archives. Everything here only reads, and fails quietly: an archive with
/// a developer's own header or encryption just yields less.
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
      } else if (RegExp(r'([0-9a-fA-F]{16}) ([0-9a-fA-F]{8})\s*$').firstMatch(line) case final m?) {
        // RPA-3.0's layout under another name ("hT4$5Hi1" and the offset
        // run together, say): some games rename the header so ordinary
        // tools pass them by.
        offset = int.parse(m[1]!, radix: 16);
        key = int.parse(m[2]!, radix: 16);
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
  /// A file's size in the archive, or null when it isn't there.
  int? sizeOf(String name) {
    final entries = _index[name];
    if (entries == null) return null;
    var total = 0;
    for (final (_, length, _) in entries) {
      total += length;
    }
    return total;
  }

  /// The first [count] bytes of a file, enough for a picture's header.
  Uint8List? head(String name, int count) {
    final entries = _index[name];
    if (entries == null || entries.isEmpty) return null;
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final out = BytesBuilder(copy: false);
      for (final (offset, length, prefix) in entries) {
        out.add(prefix);
        raf.setPositionSync(offset);
        final want = count - out.length;
        if (want <= 0) break;
        out.add(raf.readSync(want < length - prefix.length ? want : length - prefix.length));
        if (out.length >= count) break;
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  Uint8List? read(String name) {
    final entries = _index[name];
    if (entries == null || entries.isEmpty) return null;
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final out = BytesBuilder(copy: false);
      var total = 0;
      for (final (_, length, _) in entries) {
        total += length;
      }
      if (total > _maxFileBytes) return null;
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

String _stringOf(Object? v) => v is String ? v : v is Uint8List ? _decodeText(v) : '$v';
Uint8List _bytesOf(Object? v) =>
    v is Uint8List ? v : v is String ? Uint8List.fromList(latin1.encode(v)) : Uint8List(0);

// ── A minimal pickle reader ──────────────────────────────────────────────────

class _Mark {
  const _Mark();
}

class _Global {
  final String module, name;
  const _Global(this.module, this.name);
  String get qualified => '$module.$name';
}

/// An object a pickle describes: its class, the arguments it was made
/// with, and the state it was given. Nothing is run to build it.
class PickledObject {
  final String cls;
  final List<Object?> args;
  Object? state;

  /// Items added to it as to a list or a dict.
  final items = <Object?>[];
  final entries = <Object?, Object?>{};
  PickledObject(this.cls, [this.args = const []]);

  /// Its attributes: the state's dict, or with __slots__ (a pair of dicts)
  /// both merged.
  Map<Object?, Object?> get attrs {
    final s = state;
    final out = <Object?, Object?>{};
    void add(Map m) {
      // Python 2 pickles attribute names as byte strings.
      m.forEach((k, v) => out[k is Uint8List ? latin1.decode(k) : k] = v);
    }

    if (s is Map) add(s);
    if (s is List) {
      for (final x in s) {
        if (x is Map) add(x);
      }
    }
    return out;
  }
}

String _className(Object? cls) => cls is _Global ? cls.qualified : '$cls';

/// Reads pickles, protocols 0 to 5: Ren'Py's archive indexes and compiled
/// scripts. Objects become [PickledObject]s with their class name and state;
/// no code is run. The one call it carries out is _codecs.encode, which
/// Python 3 uses to pickle Python 2 byte strings.
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

  // Items can be added to an object as well as to a dict or list (a
  // defaultdict, say, or a Ren'Py class built on one); they're kept on it.
  List<Object?> _listOf(Object? o) => o is List ? o : o is PickledObject ? o.items : <Object?>[];
  Map<Object?, Object?> _mapOf(Object? o) => o is Map ? o : o is PickledObject ? o.entries : <Object?, Object?>{};

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
          _listOf(_stack.last).add(v);
        case 0x65: // APPENDS
          final items = _popMark();
          _listOf(_stack.last).addAll(items);
        case 0x73: // SETITEM
          final v = _stack.removeLast(), k = _stack.removeLast();
          _mapOf(_stack.last)[k] = v;
        case 0x75: // SETITEMS
          final items = _popMark();
          final m = _mapOf(_stack.last);
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
          final list = args is List ? args : <Object?>[args];
          if (fn is _Global && fn.name == 'encode' && list.isNotEmpty && list[0] is String) {
            _stack.add(Uint8List.fromList(latin1.encode(list[0] as String)));
          } else if (fn is _Global && fn.name == '_reconstructor' && list.isNotEmpty) {
            _stack.add(PickledObject(_className(list[0]))); // Python 2's way to pickle an object
          } else {
            _stack.add(PickledObject(_className(fn), list));
          }
        case 0x81: // NEWOBJ
          final args = _stack.removeLast(), cls = _stack.removeLast();
          _stack.add(PickledObject(_className(cls), args is List ? args : const []));
        case 0x92: // NEWOBJ_EX
          _stack.removeLast(); // keyword arguments
          final args = _stack.removeLast(), cls = _stack.removeLast();
          _stack.add(PickledObject(_className(cls), args is List ? args : const []));
        case 0x69: // INST
          final module = _line(), name = _line();
          _stack.add(PickledObject('$module.$name', _popMark()));
        case 0x6f: // OBJ
          final items = _popMark();
          _stack.add(PickledObject(items.isEmpty ? '?' : _className(items.first), items.skip(1).toList()));
        case 0x62: // BUILD
          final state = _stack.removeLast(), obj = _stack.last;
          if (obj is PickledObject) {
            obj.state = state;
          } else if (obj is Map && state is Map) {
            obj.addAll(state);
          }
        case 0x8f: // EMPTY_SET
          _stack.add(<Object?>[]);
        case 0x90: // ADDITEMS
          final items = _popMark();
          (_stack.last as List).addAll(items);
        case 0x91: // FROZENSET
          _stack.add(_popMark());
        case 0x47: // BINFLOAT
          _stack.add(ByteData.sublistView(_take(8)).getFloat64(0));
        case 0x46: // FLOAT
          _stack.add(double.tryParse(_line()));
        case 0x50: // PERSID
          _line();
          _stack.add(null);
        case 0x51: // BINPERSID
          _stack.removeLast();
          _stack.add(null);
        case 0x82: // EXT1
          _i += 1;
          _stack.add(null);
        case 0x83: // EXT2
          _i += 2;
          _stack.add(null);
        case 0x84: // EXT4
          _i += 4;
          _stack.add(null);
        case 0x96: // BYTEARRAY8
          _stack.add(Uint8List.fromList(_take(_le(8))));
        case 0x97: // NEXT_BUFFER
          _stack.add(null);
        case 0x98: // READONLY_BUFFER
          break;
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

/// A compiled script (.rpyc) unpickled: the statements Ren'Py saved. Ren'Py
/// 6, 7 and 8 all pickle the same statement classes (renpy.ast.Define and so
/// on); what changed between versions is how strings and objects are
/// pickled, which [Unpickler] reads either way.
Object? rpycTree(Uint8List bytes) {
  final raw = _rpycData(bytes);
  if (raw == null) return null;
  try {
    return Unpickler(raw).load();
  } catch (_) {
    return null;
  }
}

/// The decompressed first slot of a compiled script.
Uint8List? _rpycData(Uint8List bytes) {
  try {
    if (bytes.length < 10) return null;
    final head = latin1.decode(bytes.sublist(0, 10));
    Uint8List? data;
    if (head == 'RENPY RPC2') {
      var at = 10;
      while (at + 12 <= bytes.length) {
        final bd = ByteData.sublistView(bytes, at, at + 12);
        final slot = bd.getUint32(0, Endian.little), start = bd.getUint32(4, Endian.little);
        final length = bd.getUint32(8, Endian.little);
        if (slot == 0) break;
        if (slot == 1 && start + length <= bytes.length) {
          data = Uint8List.sublistView(bytes, start, start + length);
          break;
        }
        at += 12;
      }
    } else {
      data = bytes; // Ren'Py 6: the whole file is zlib
    }
    return data == null ? null : inflateCapped(data, _maxScriptBytes);
  } catch (_) {
    return null;
  }
}

/// A compiled script bigger than this, decompressed, isn't read.
const _maxScriptBytes = 128 << 20;

// ── What the scripts say ─────────────────────────────────────────────────────

/// What a game's scripts set: store variables (define, default, or plain
/// assignments in python blocks) as the source of their value, image
/// statements, and the contents of the main menu screen.
class _Facts {
  /// "config.name" → `_("Title")`. Store variables in the default store have
  /// no prefix.
  final vars = <String, String>{};

  /// Assignments found in python blocks, used only where no define says.
  final weakVars = <String, String>{};

  /// "bg menu" → `"images/menu.jpg"`.
  final images = <String, String>{};

  /// Source text from every `screen main_menu`: lines, or the strings of a
  /// compiled screen.
  final menuRefs = <String>[];

  /// The code of python blocks, where functions are defined.
  final python = <String>[];

  /// `# define config.name = …`: a name the developer wrote and then
  /// commented out, still better than the file-safe build name.
  final commented = <String, String>{};

  Map<String, String>? _functions;

  /// The body of `def name(…)` in the game's python, or null. Every def is
  /// indexed in one pass, the first time one is asked for.
  String? function(String name) => (_functions ??= _indexFunctions())[name];

  Map<String, String> _indexFunctions() {
    final out = <String, String>{};
    final head = RegExp(r'^([ \t]*)def\s+([A-Za-z_]\w*)\s*\(', multiLine: true);
    for (final src in python) {
      for (final m in head.allMatches(src)) {
        if (out.containsKey(m[2])) continue;
        final indent = m[1]!.length;
        final body = StringBuffer();
        var at = src.indexOf('\n', m.end);
        var lines = 0;
        while (at >= 0 && at < src.length && lines++ < 200) {
          final end = src.indexOf('\n', at + 1);
          final line = src.substring(at + 1, end < 0 ? src.length : end);
          final trimmed = line.trimLeft();
          if (trimmed.isNotEmpty && line.length - trimmed.length <= indent) break;
          body.writeln(line);
          if (end < 0) break;
          at = end;
        }
        out[m[2]!] = body.toString();
      }
    }
    return out;
  }

  void define(String key, String source) {
    final old = vars[key];
    // A real value beats an empty one (`define config.name = _("")` then
    // the title elsewhere); otherwise the first one read stays.
    if (old == null || (_isEmptyText(old) && !_isEmptyText(source))) vars[key] = source;
  }

  String? valueOf(String key) => vars[key] ?? weakVars[key];
}

bool _isEmptyText(String source) =>
    RegExp(r'''^\s*(?:_{1,2}\(\s*)?[uU]?(["'])\s*\1\s*\)?\s*(?:#.*)?$''').hasMatch(source);

String _storeKey(String store, String name) {
  final s = store.startsWith('store.') ? store.substring(6) : (store == 'store' ? '' : store);
  return s.isEmpty ? name : '$s.$name';
}

String _withoutStore(String key) => key.startsWith('store.') ? key.substring(6) : key;

/// A pickled value as text: str, bytes from Python 2, or a PyExpr (Ren'Py's
/// str subclass for source code).
String? _str(Object? v) {
  if (v is String) return v;
  if (v is Uint8List) return _decodeText(v);
  if (v is PickledObject && v.args.isNotEmpty) {
    final a = v.args.first;
    if (a is String) return a;
    if (a is Uint8List) return _decodeText(a);
  }
  return null;
}

/// The source of a PyCode: its state is (1, source, location, mode, py).
String? _codeSource(Object? code) {
  if (code is! PickledObject) return _str(code);
  final s = code.state;
  if (s is List && s.length > 1) return _str(s[1]);
  if (s is Map) return _str(s['source']);
  return null;
}

/// Text from a game file: UTF-8 (with or without a BOM), or Windows-1252
/// for the few that aren't.
String _decodeText(List<int> bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) b = b.sublist(3);
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b, allowInvalid: true);
  }
}

final _assignment = RegExp(r'^\s*([A-Za-z_][\w.]*)\s*=(?!=)\s*(.+?)\s*$');

void _readPython(String source, _Facts f) {
  f.python.add(source);
  for (final line in source.split('\n')) {
    final m = _assignment.firstMatch(line);
    if (m != null) f.weakVars.putIfAbsent(_withoutStore(m[1]!), () => m[2]!);
  }
}

/// Walks a compiled script's statements.
void _readTree(Object? tree, _Facts f) {
  final seen = HashSet<Object>.identity();
  final stack = <Object?>[tree];
  var steps = 0;
  while (stack.isNotEmpty && steps++ < 5000000) {
    final o = stack.removeLast();
    if (o == null || o is String || o is num || o is bool || o is Uint8List) continue;
    if (!seen.add(o)) continue;
    if (o is List) {
      stack.addAll(o);
    } else if (o is Map) {
      stack.addAll(o.values);
    } else if (o is PickledObject) {
      final a = o.attrs;
      switch (o.cls) {
        case 'renpy.ast.Define' || 'renpy.ast.Default':
          final name = _str(a['varname']);
          final src = _codeSource(a['code']);
          final op = _str(a['operator']) ?? '=';
          if (name != null && src != null && op == '=' && a['index'] == null) {
            f.define(_storeKey(_str(a['store']) ?? 'store', name), src);
          }
        case 'renpy.ast.Python' || 'renpy.ast.EarlyPython':
          final src = _codeSource(a['code']);
          if (src != null) _readPython(src, f);
        case 'renpy.ast.Image':
          final name = a['imgname'];
          final src = _codeSource(a['code']);
          if (name is List && src != null) {
            f.images.putIfAbsent(name.map(_str).whereType<String>().join(' ').toLowerCase(), () => src);
          }
        case 'renpy.sl2.slast.SLScreen':
          if (_str(a['name']) == 'main_menu') f.menuRefs.addAll(_stringsIn(o));
        case 'renpy.screenlang.ScreenLangScreen': // Ren'Py 6's screen language
          if (_str(a['name']) == 'main_menu') {
            final src = _codeSource(a['code']);
            if (src != null) f.menuRefs.addAll(src.split('\n'));
          }
      }
      stack
        ..addAll(o.args)
        ..add(o.state)
        ..addAll(o.items)
        ..addAll(o.entries.values);
    }
  }
}

/// Every string inside [root], for a compiled screen: its displayables keep
/// their arguments as source text (`"gui/menu.png"`, `gui.main_menu_background`).
List<String> _stringsIn(Object root) {
  final out = <String>[];
  final seen = HashSet<Object>.identity();
  final stack = <Object?>[root];
  while (stack.isNotEmpty && out.length < 20000) {
    final o = stack.removeLast();
    final s = o is String || o is Uint8List ? _str(o) : null;
    if (s != null) {
      out.add(s);
      continue;
    }
    if (o == null || o is num || o is bool || !seen.add(o)) continue;
    if (o is List) {
      stack.addAll(o);
    } else if (o is Map) {
      stack
        ..addAll(o.keys)
        ..addAll(o.values);
    } else if (o is PickledObject) {
      stack
        ..addAll(o.args)
        ..add(o.state)
        ..addAll(o.items)
        ..addAll(o.entries.keys)
        ..addAll(o.entries.values);
    }
  }
  return out;
}

final _defineLine = RegExp(r'^\s*(?:define|default)\s+(?:-?\d+\s+)?([A-Za-z_][\w.]*)\s*=\s*(.+?)\s*$');
final _imageLine = RegExp(r'^\s*image\s+([^=:]+?)\s*=\s*(.+?)\s*$');
final _screenLine = RegExp(r'^(\s*)screen\s+main_menu\b');
final _commentedDefine = RegExp(r'^\s*#\s*define\s+(config\.name|config\.version)\s*=\s*(.+?)\s*$');

/// The same from a script's source (.rpy).
void _readSource(String text, _Facts f) {
  final lines = text.split(RegExp(r'\r?\n'));
  // A value can run over several lines (`ConditionSwitch(` …); it's taken up
  // to where its brackets close.
  String joined(int i, String start) {
    var v = start;
    for (var k = i + 1; k < lines.length && k < i + 40 && _depth(v) > 0; k++) {
      v = '$v ${lines[k].trim()}';
    }
    return v;
  }

  f.python.add(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final c = _commentedDefine.firstMatch(line);
    if (c != null) {
      f.commented.putIfAbsent(c[1]!, () => c[2]!);
      continue;
    }
    var m = _defineLine.firstMatch(line);
    if (m != null) {
      f.define(_withoutStore(m[1]!), joined(i, m[2]!));
      continue;
    }
    m = _imageLine.firstMatch(line);
    if (m != null) {
      f.images.putIfAbsent(m[1]!.trim().toLowerCase(), () => joined(i, m![2]!));
      continue;
    }
    m = _screenLine.firstMatch(line);
    if (m != null) {
      final indent = m[1]!.length;
      for (var k = i + 1; k < lines.length; k++) {
        final l = lines[k];
        if (l.trim().isEmpty || l.trimLeft().startsWith('#')) continue;
        if (l.length - l.trimLeft().length <= indent) break;
        f.menuRefs.add(l);
      }
      continue;
    }
    final a = _assignment.firstMatch(line);
    if (a != null && line.startsWith(RegExp(r'\s'))) {
      f.weakVars.putIfAbsent(_withoutStore(a[1]!), () => a[2]!);
    }
  }
}

/// [s] without a trailing `# comment` (a # inside quotes stays).
String _withoutComment(String s) {
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '#') {
      return s.substring(0, i);
    }
  }
  return s;
}

/// How many brackets are still open in [s], outside quotes.
int _depth(String s) {
  var d = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '#') {
      break;
    } else if ('([{'.contains(c)) {
      d++;
    } else if (')]}'.contains(c)) {
      d--;
    }
  }
  return d;
}

// ── Reading values ───────────────────────────────────────────────────────────

final _stringLiteral = RegExp(r'''[rRuUbBfF]{0,2}("|')((?:\\.|(?!\1).)*)\1''');
final _wholeLiteral = RegExp(r'''^[rRuU]?("|')((?:\\.|(?!\1).)*)\1$''');
final _identifier = RegExp(r'[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*');

String _unescape(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) => switch (m[1]) {
      'n' => ' ',
      't' => ' ',
      final c => c!,
    });

/// The text a value's source stands for when it's a string: "X", _("X"), a
/// variable holding one, a number, or such pieces joined with +.
String? _evalText(String? source, _Facts f, [int depth = 0]) {
  if (source == null || depth > 6) return null;
  var e = _withoutComment(source).trim();
  final call = RegExp(r'^_{1,2}\(\s*(.*?)\s*\)$', dotAll: true).firstMatch(e);
  if (call != null) e = call[1]!;
  final pieces = _splitPlus(e);
  if (pieces.length > 1) {
    final texts = pieces.map((x) => _evalText(x, f, depth + 1)).toList();
    return texts.contains(null) ? null : texts.join();
  }
  final lit = _wholeLiteral.firstMatch(e);
  if (lit != null) return _unescape(lit[2]!).replaceAll(RegExp(r'\{[^{}]*\}'), '');
  if (RegExp(r'^v?\d+(?:\.\d+)*[a-z]?$').hasMatch(e)) return e;
  final str = RegExp(r'^str\((.*)\)$').firstMatch(e);
  if (str != null) return _evalText(str[1], f, depth + 1);
  if (RegExp(r'^[A-Za-z_][\w.]*$').hasMatch(e)) return _evalText(f.valueOf(_withoutStore(e)), f, depth + 1);
  return null;
}

/// [e] split at the `+` signs outside quotes and brackets.
List<String> _splitPlus(String e) {
  final out = <String>[];
  var d = 0, start = 0;
  String? quote;
  for (var i = 0; i < e.length; i++) {
    final c = e[i];
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if ('([{'.contains(c)) {
      d++;
    } else if (')]}'.contains(c)) {
      d--;
    } else if (c == '+' && d == 0) {
      out.add(e.substring(start, i));
      start = i + 1;
    }
  }
  out.add(e.substring(start));
  return out;
}

// ── Files ────────────────────────────────────────────────────────────────────

const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.avif'};

/// Every file under game/, loose or in an archive, by lower-case path. Ren'Py
/// looks up files without regard to case, and a loose file beats an archived
/// one.
class _Files {
  final _byPath = <String, (File?, RpaArchive?, String)>{};
  final _byStem = <String, List<String>>{};

  _Files(Directory game, List<RpaArchive> archives) {
    for (final a in archives) {
      for (final n in a.names) {
        _add(n, (null, a, n));
      }
    }
    try {
      for (final e in game.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: game.path).replaceAll('\\', '/');
        _add(rel, (e, null, rel));
      }
    } catch (_) {}
  }

  void _add(String rel, (File?, RpaArchive?, String) src) {
    final key = rel.toLowerCase();
    if (key.startsWith('tl/') || key.startsWith('cache/') || key.startsWith('saves/')) return;
    _byPath[key] = src;
    if (_imageExts.contains(p.extension(key))) {
      _byStem.putIfAbsent(p.basenameWithoutExtension(key), () => []).add(key);
    }
  }

  Iterable<String> get paths => _byPath.keys;

  /// The key for [rel] as a script or image refers to it: relative to game/,
  /// or for an image, inside images/.
  String? find(String rel) {
    final key = rel.replaceAll('\\', '/').toLowerCase();
    for (final k in [key, 'images/$key']) {
      if (_byPath.containsKey(k)) return k;
    }
    return null;
  }

  /// Image files Ren'Py names automatically: `images/bg menu.png` is the
  /// image "bg menu".
  List<String> byImageName(String name) => _byStem[name.toLowerCase()] ?? const [];

  Uint8List? read(String key) {
    final src = _byPath[key];
    if (src == null) return null;
    final (file, archive, name) = src;
    try {
      return file != null ? file.readAsBytesSync() : archive!.read(name);
    } catch (_) {
      return null;
    }
  }

  int? sizeOf(String key) {
    final src = _byPath[key];
    if (src == null) return null;
    final (file, archive, name) = src;
    try {
      return file != null ? file.lengthSync() : archive!.sizeOf(name);
    } catch (_) {
      return null;
    }
  }

  /// The first bytes of a file: a picture's size is in its header, so
  /// candidates are judged without reading them whole.
  Uint8List? head(String key, [int count = 64 * 1024]) {
    final src = _byPath[key];
    if (src == null) return null;
    final (file, archive, name) = src;
    try {
      if (file == null) return archive!.head(name, count);
      final raf = file.openSync();
      try {
        return raf.readSync(count);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }
}

// ── Images ───────────────────────────────────────────────────────────────────

/// Width and height from a PNG, JPEG or WebP header, or null.
(int, int)? imageSize(Uint8List b) {
  try {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
      final d = ByteData.sublistView(b);
      return (d.getUint32(16), d.getUint32(20));
    }
    if (b.length > 4 && b[0] == 0xff && b[1] == 0xd8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xff) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xd8 || marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7) || marker == 0xff) {
          i += marker == 0xff ? 1 : 2;
          continue;
        }
        final len = (b[i + 2] << 8) | b[i + 3];
        if (marker >= 0xc0 && marker <= 0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc) {
          return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
        }
        i += 2 + len;
      }
      return null;
    }
    if (b.length > 30 && latin1.decode(b.sublist(0, 4)) == 'RIFF' && latin1.decode(b.sublist(8, 12)) == 'WEBP') {
      final chunk = latin1.decode(b.sublist(12, 16));
      if (chunk == 'VP8 ') return ((b[26] | b[27] << 8) & 0x3fff, (b[28] | b[29] << 8) & 0x3fff);
      if (chunk == 'VP8L') {
        return (1 + (b[21] | (b[22] & 0x3f) << 8), 1 + ((b[22] >> 6) | b[23] << 2 | (b[24] & 0x0f) << 10));
      }
      if (chunk == 'VP8X') {
        return (1 + (b[24] | b[25] << 8 | b[26] << 16), 1 + (b[27] | b[28] << 8 | b[29] << 16));
      }
    }
  } catch (_) {}
  return null;
}

/// How good [bytes] is as a cover, or 0 when it isn't one: too small, or
/// Ren'Py's stock menu art, a flat picture that compresses to a few bytes
/// per hundred pixels. Wide pictures, like a menu background, score highest.
double _coverScore(Uint8List head, int fileSize) {
  final size = imageSize(head);
  if (size == null) return fileSize >= 50000 ? 1 : 0;
  final (w, h) = size;
  final area = w * h;
  if (w < 640 || h < 360) return 0;
  if (fileSize / area < 0.04) return 0;
  final aspect = w / h;
  return area * (aspect >= 1.25 && aspect <= 2.4 ? 1.0 : 0.3);
}

/// Image files [source] may show: quoted paths, image names (from image
/// statements or images/ file names), and variables followed to their value.
///
/// Each variable, function and image name is followed once ([seen]): a
/// menu that names the same ones on many lines, or names that refer to each
/// other, would otherwise be followed again and again.
void _imageRefs(String source, _Facts f, _Files files, Set<String> out, {Set<String>? seen, int depth = 0}) {
  if (depth > 5) return;
  final followed = seen ?? <String>{};
  void follow(String tag, String? text) {
    if (text != null && followed.add(tag)) _imageRefs(text, f, files, out, seen: followed, depth: depth + 1);
  }

  for (final m in _stringLiteral.allMatches(source)) {
    final s = _unescape(m[2]!).trim();
    if (s.isEmpty || s.length > 200) continue;
    if (_imageExts.contains(p.extension(s).toLowerCase())) {
      final key = files.find(s);
      if (key != null) out.add(key);
      continue;
    }
    final name = s.toLowerCase();
    final defined = f.images[name];
    if (defined != null) {
      follow('image $name', defined);
    } else {
      out.addAll(files.byImageName(name));
    }
  }
  final bare = source.replaceAll(_stringLiteral, ' ');
  for (final m in _identifier.allMatches(bare)) {
    final id = m[0]!;
    follow('var $id', f.valueOf(_withoutStore(id)));
    // `get_random_background()`: the pictures that function picks from.
    var next = m.end;
    while (next < bare.length && (bare.codeUnitAt(next) == 0x20 || bare.codeUnitAt(next) == 0x09)) {
      next++;
    }
    if (next < bare.length && bare.codeUnitAt(next) == 0x28) {
      final name = id.split('.').last;
      if (!followed.contains('def $name')) follow('def $name', f.function(name));
    }
    // `add main_bg` style: an image named without quotes.
    follow('image ${id.toLowerCase()}', f.images[id.toLowerCase()]);
  }
}

// ── Putting it together ──────────────────────────────────────────────────────

/// Script files that usually hold the name, version, GUI and main menu.
final _likelyScript = RegExp(r'options|gui|screen|menu|title|define|config|var|init|setting|version|splash|main|custom');

final _menuArtName = RegExp(
    r'(^|/)(main_?menu|mainmenu|menu_?(bg|background)|title_?(screen|bg|background)?|main_?(bg|background))[^/]*$');

/// Reads [gameFolder]'s own files: its scripts, compiled or not, loose in
/// game/ or in its archives, and the pictures they name. Null fields where
/// nothing was found. Reads everything it needs, so a big game can take a
/// few seconds; it only runs when asked, for one game.
LocalGameInfo localFetch(Directory gameFolder, {void Function(String)? trace}) {
  final game = Directory(p.join(gameFolder.path, 'game'));
  if (!game.existsSync()) return const LocalGameInfo();

  final clock = Stopwatch()..start();
  final archives = <RpaArchive>[];
  try {
    final rpas = game.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.rpa')).toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final f in rpas) {
      final a = RpaArchive.open(f);
      if (a != null) archives.add(a);
    }
  } catch (_) {}
  trace?.call('${clock.elapsedMilliseconds} ms: archives opened');
  final files = _Files(game, archives);
  trace?.call('${clock.elapsedMilliseconds} ms: files listed');

  // One entry per script: the source when it's there, else the compiled one.
  final scripts = <String, String>{};
  for (final key in files.paths) {
    final ext = p.extension(key);
    if (ext != '.rpy' && ext != '.rpyc') continue;
    final stem = p.withoutExtension(key);
    if (ext == '.rpy' || !scripts.containsKey(stem)) scripts[stem] = key;
  }
  final facts = _Facts();
  void read(String key, {bool skim = false}) {
    final bytes = files.read(key);
    if (bytes == null) return;
    if (key.endsWith('.rpy')) {
      final text = _decodeText(bytes);
      if (skim && !text.contains('config.') && !text.contains('main_menu') && !text.contains('build.')) return;
      _readSource(text, facts);
    } else {
      final raw = _rpycData(bytes);
      if (raw == null) return;
      if (skim && !_containsAny(raw, const ['main_menu', 'store.config', 'store.build', 'store.gui'])) return;
      try {
        _readTree(Unpickler(raw).load(), facts);
      } catch (e) {
        trace?.call('could not read $key: $e');
      }
    }
  }

  // options first, so its define wins a tie; then the other likely files;
  // then, only if something is still missing, every other script.
  final ordered = scripts.values.toList()
    ..sort((a, b) {
      int rank(String k) => p.basenameWithoutExtension(k) == 'options' ? 0 : 1;
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.length.compareTo(b.length);
    });
  final likely = ordered.where((k) => _likelyScript.hasMatch(p.basenameWithoutExtension(k))).toList();
  for (final k in likely) {
    final t = clock.elapsedMilliseconds;
    read(k);
    trace?.call('${clock.elapsedMilliseconds - t} ms: read $k');
  }
  String? title() {
    String? text(String? source) {
      final v = _evalText(source, facts)?.trim();
      return v == null || v.isEmpty || v.contains('[') ? null : v;
    }

    final build = text(facts.valueOf('build.name'));
    // The window title only when it names the game: some games put a
    // Patreon line there.
    final window = text(facts.valueOf('config.window_title'));
    String squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final windowNamesGame = window != null &&
        (build == null || squash(window).contains(squash(build)) || squash(build).contains(squash(window)));
    return text(facts.valueOf('config.name')) ??
        text(facts.valueOf('build.display_name')) ??
        text(facts.commented['config.name']) ??
        (windowNamesGame ? window : null) ??
        (build == null ? null : _prettyBuildName(build));
  }

  if (_evalText(facts.valueOf('config.name'), facts)?.trim().isNotEmpty != true ||
      facts.menuRefs.isEmpty ||
      facts.valueOf('config.version') == null) {
    for (final k in ordered.where((k) => !likely.contains(k))) {
      read(k, skim: true);
    }
  }

  final version = _evalText(facts.valueOf('config.version'), facts)?.trim();
  trace?.call('${clock.elapsedMilliseconds} ms: scripts read');
  if (trace != null) {
    trace('archives: ${archives.length} opened; scripts: ${scripts.length} (${likely.length} likely)');
    for (final k in const ['config.name', 'config.window_title', 'build.name', 'config.version', 'gui.main_menu_background']) {
      trace('$k = ${facts.vars[k]} | weak ${facts.weakVars[k]}');
    }
    trace('menu screen lines: ${facts.menuRefs.length}; images: ${facts.images.length}');
  }

  // The cover: the biggest real picture the main menu screen shows, then
  // the GUI's menu background, then gui/main_menu, then a file named like
  // menu art. Ren'Py's stock menu art is skipped: no cover beats a blank one.
  Uint8List? cover;
  var coverExt = '.png';
  final groups = <Set<String>>[];
  final fromScreen = <String>{};
  final followed = <String>{};
  for (final line in facts.menuRefs.toSet()) {
    _imageRefs(line, facts, files, fromScreen, seen: followed);
  }
  groups.add(fromScreen);
  trace?.call('${clock.elapsedMilliseconds} ms: menu screen pictures (${fromScreen.length})');
  final background = <String>{};
  final bg = facts.valueOf('gui.main_menu_background');
  if (bg != null) _imageRefs(bg, facts, files, background);
  groups.add(background);
  groups.add({
    for (final ext in _imageExts)
      if (files.find('gui/main_menu$ext') != null) files.find('gui/main_menu$ext')!
  });
  groups.add({for (final k in files.paths) if (_imageExts.contains(p.extension(k)) && _menuArtName.hasMatch(k)) k});
  // A menu that's a video has no picture to take: the splash shown at
  // launch, or the game menu's background, often carry the game's art.
  groups.add({
    for (final k in files.paths)
      if (_imageExts.contains(p.extension(k)) &&
          RegExp(r'^(presplash|presplash_background|gui/game_menu)\.[a-z]+$').hasMatch(k))
        k
  });
  trace?.call('${clock.elapsedMilliseconds} ms: candidates gathered');
  for (final group in groups) {
    var best = 0.0;
    String? bestKey;
    for (final key in group.take(200)) {
      final head = files.head(key), size = files.sizeOf(key);
      if (head == null || size == null) continue;
      final score = _coverScore(head, size);
      trace?.call('cover group ${groups.indexOf(group)}: $key ${imageSize(head)} $size → $score');
      if (score > best) {
        best = score;
        bestKey = key;
      }
    }
    if (bestKey != null) {
      cover = files.read(bestKey);
      coverExt = p.extension(bestKey);
    }
    if (cover != null) break;
  }

  trace?.call('${clock.elapsedMilliseconds} ms: cover chosen');
  Uint8List? icon;
  final iconRefs = <String>{};
  final iconSource = facts.valueOf('config.window_icon');
  if (iconSource != null) _imageRefs(iconSource, facts, files, iconRefs);
  for (final key in [...iconRefs, if (files.find('gui/window_icon.png') != null) files.find('gui/window_icon.png')!]) {
    icon = files.read(key);
    if (icon != null) break;
  }

  return LocalGameInfo(
    title: title(),
    version: version == null || version.isEmpty ? null : version,
    cover: cover,
    coverExt: coverExt == '.jpeg' ? '.jpg' : coverExt,
    icon: icon,
  );
}

/// `build.name` is the file-safe name ("30YearOldVirgin", "lost_freedom");
/// spaced out, it's a fair title when the game sets no other.
String _prettyBuildName(String s) => s
    .replaceAll(RegExp(r'[_\-]+'), ' ')
    .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whether any of [needles] (ASCII) occurs in [haystack].
bool _containsAny(Uint8List haystack, List<String> needles) {
  for (final n in needles) {
    final b = latin1.encode(n);
    outer:
    for (var i = 0; i + b.length <= haystack.length; i++) {
      for (var k = 0; k < b.length; k++) {
        if (haystack[i + k] != b[k]) continue outer;
      }
      return true;
    }
  }
  return false;
}

/// An archive index bigger than this isn't a real game's.
const _maxIndexBytes = 32 << 20;

/// A file read out of an archive bigger than this isn't a cover or a script.
const _maxFileBytes = 256 << 20;

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
