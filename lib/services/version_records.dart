import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../utils/app_paths.dart';
import 'renpy_local.dart' show menuChoice;

/// What one version of a game held, kept so versions can be compared after
/// the folder is gone: every picture and video with its size, and every line
/// of dialogue and menu choice by scene. Written while counting (#44), kept
/// in the app's data folder, about a megabyte a version.
class VersionRecord {
  final String version;
  final DateTime? builtAt;
  final Map<String, int> media;
  final List<RecordLine> lines;

  const VersionRecord({required this.version, this.builtAt, required this.media, required this.lines});

  static VersionRecord? read(String path) {
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(File(path).readAsBytesSync()))) as Map;
      return VersionRecord(
        version: json['version'] as String? ?? '',
        builtAt: DateTime.tryParse(json['built_at'] as String? ?? ''),
        media: {for (final e in (json['media'] as Map? ?? {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0},
        lines: [
          for (final l in json['lines'] as List? ?? const [])
            if (l is List && l.length >= 3) RecordLine('${l[0]}', '${l[1]}', '${l[2]}'),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// One line: the scene (label) it's in, who says it, and what's said.
class RecordLine {
  final String scene;
  final String who;
  final String what;
  const RecordLine(this.scene, this.who, this.what);

  bool get isChoice => who == menuChoice;

  /// The same line wherever it moved within its scene.
  String get key => '$scene\u0000$who\u0000$what';

  @override
  bool operator ==(Object other) => other is RecordLine && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// Where a game's records live: one folder per game, one file per version.
String recordFolder(String baseKey) => appDataPath('version_records', _short(baseKey));

String recordPath(String baseKey, String version) {
  final safe = version.replaceAll(RegExp(r'[^\w.\-]'), '_');
  return p.join(recordFolder(baseKey), '${safe.isEmpty ? 'unversioned' : safe}-${_short(version).substring(0, 6)}.json.gz');
}

/// Where thumbnails of a game's removed and changed pictures are kept.
String thumbFolder(String baseKey) => p.join(recordFolder(baseKey), 'thumbs');

String thumbPath(String baseKey, String version, String picture) =>
    p.join(thumbFolder(baseKey), '${_short('$version\u0000$picture')}.png');

String _short(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 16);

bool hasRecord(String baseKey, String version) => File(recordPath(baseKey, version)).existsSync();

// ── Comparing ────────────────────────────────────────────────────────────────

/// Folders of interface art. Their pictures change with every redesign and
/// say nothing about the story, so the comparison leaves them out.
final _interface = RegExp(r'(^|/)(gui|ui|interface|menus?|icons?|buttons?|cursors?|fonts?|frames?)(/|$)');

bool isInterfaceArt(String key) => _interface.hasMatch(p.dirname(key));

const _pictureExts = {'.png', '.jpg', '.jpeg', '.webp', '.avif'};
bool isPicture(String key) => _pictureExts.contains(p.extension(key).toLowerCase());

/// A line that was rewritten: what it said before and after, in its scene.
class Rewrite {
  final RecordLine before;
  final RecordLine after;
  const Rewrite(this.before, this.after);
}

/// What changed between two versions.
class RecordDiff {
  final List<String> removedMedia;
  final List<String> addedMedia;

  /// Same name, different size: redrawn, edited or recompressed.
  final List<String> changedMedia;

  /// Same picture under a new file type ("a.png" → "a.webp"), from old to
  /// new. Not removed, so never mixed in with the removals.
  final Map<String, String> convertedMedia;

  final List<RecordLine> removedLines;
  final List<RecordLine> addedLines;
  final List<Rewrite> rewrittenLines;

  /// Scenes that are gone altogether, and new ones.
  final List<String> removedScenes;
  final List<String> addedScenes;

  const RecordDiff({
    required this.removedMedia,
    required this.addedMedia,
    required this.changedMedia,
    required this.convertedMedia,
    required this.removedLines,
    required this.addedLines,
    required this.rewrittenLines,
    required this.removedScenes,
    required this.addedScenes,
  });

  bool get empty =>
      removedMedia.isEmpty &&
      addedMedia.isEmpty &&
      changedMedia.isEmpty &&
      convertedMedia.isEmpty &&
      removedLines.isEmpty &&
      addedLines.isEmpty &&
      rewrittenLines.isEmpty;
}

/// Compares [before] with [after].
RecordDiff diffRecords(VersionRecord before, VersionRecord after) {
  bool story(String k) => !_interface.hasMatch(p.dirname(k));
  final oldMedia = {for (final e in before.media.entries) if (story(e.key)) e.key: e.value};
  final newMedia = {for (final e in after.media.entries) if (story(e.key)) e.key: e.value};

  final newByStem = <String, String>{for (final k in newMedia.keys) p.withoutExtension(k): k};
  final oldByStem = <String, String>{for (final k in oldMedia.keys) p.withoutExtension(k): k};
  final removed = <String>[], changed = <String>[], converted = <String, String>{};
  for (final e in oldMedia.entries) {
    final now = newMedia[e.key];
    if (now != null) {
      if (now != e.value) changed.add(e.key);
      continue;
    }
    final other = newByStem[p.withoutExtension(e.key)];
    if (other != null && !oldMedia.containsKey(other)) {
      converted[e.key] = other;
    } else {
      removed.add(e.key);
    }
  }
  final added = [
    for (final k in newMedia.keys)
      if (!oldMedia.containsKey(k) && !converted.containsValue(k) && oldByStem[p.withoutExtension(k)] == null) k,
  ];

  // Lines, scene by scene, so a scene that moved files still matches up.
  final oldScenes = _byScene(before.lines), newScenes = _byScene(after.lines);
  final removedLines = <RecordLine>[], addedLines = <RecordLine>[], rewrites = <Rewrite>[];
  for (final scene in {...oldScenes.keys, ...newScenes.keys}) {
    final a = oldScenes[scene] ?? const <RecordLine>[], b = newScenes[scene] ?? const <RecordLine>[];
    if (a.isEmpty) {
      addedLines.addAll(b);
      continue;
    }
    if (b.isEmpty) {
      removedLines.addAll(a);
      continue;
    }
    _diffLines(a, b, removedLines, addedLines, rewrites);
  }

  return RecordDiff(
    removedMedia: removed..sort(),
    addedMedia: added..sort(),
    changedMedia: changed..sort(),
    convertedMedia: converted,
    removedLines: removedLines,
    addedLines: addedLines,
    rewrittenLines: rewrites,
    removedScenes: [for (final s in oldScenes.keys) if (!newScenes.containsKey(s)) s]..sort(),
    addedScenes: [for (final s in newScenes.keys) if (!oldScenes.containsKey(s)) s]..sort(),
  );
}

Map<String, List<RecordLine>> _byScene(List<RecordLine> lines) {
  final out = <String, List<RecordLine>>{};
  for (final l in lines) {
    out.putIfAbsent(l.scene, () => []).add(l);
  }
  return out;
}

/// A line-by-line comparison of one scene (longest common run). A removed
/// line followed by an added one from the same speaker is a rewrite.
void _diffLines(List<RecordLine> a, List<RecordLine> b, List<RecordLine> removed, List<RecordLine> added,
    List<Rewrite> rewrites) {
  // Very long scenes: compare as sets rather than build a huge table.
  if (a.length * b.length > 4000000) {
    final inB = b.toSet(), inA = a.toSet();
    removed.addAll(a.where((l) => !inB.contains(l)));
    added.addAll(b.where((l) => !inA.contains(l)));
    return;
  }
  final n = a.length, m = b.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : (table[i + 1][j] >= table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
    }
  }
  var i = 0, j = 0;
  final gone = <RecordLine>[], come = <RecordLine>[];
  void flush() {
    // Pair them up in order while the speakers match; the rest stand alone.
    var x = 0, y = 0;
    while (x < gone.length && y < come.length) {
      if (gone[x].who == come[y].who) {
        rewrites.add(Rewrite(gone[x], come[y]));
        x++;
        y++;
      } else {
        removed.add(gone[x++]);
      }
    }
    removed.addAll(gone.skip(x));
    added.addAll(come.skip(y));
    gone.clear();
    come.clear();
  }

  while (i < n && j < m) {
    if (a[i] == b[j]) {
      flush();
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      gone.add(a[i++]);
    } else {
      come.add(b[j++]);
    }
  }
  gone.addAll(a.skip(i));
  come.addAll(b.skip(j));
  flush();
}

/// Something in an earlier version that the newest one doesn't have, with the
/// last version that still did.
class Gone<T> {
  final T item;
  final String lastVersion;
  const Gone(this.item, this.lastVersion);
}

/// Everything in [records] (oldest first) that the last one no longer has:
/// pictures and lines, each with the last version that had it. Pictures that
/// only changed file type don't count as gone.
({List<Gone<String>> media, List<Gone<RecordLine>> lines}) goneSince(List<VersionRecord> records) {
  if (records.length < 2) return (media: const [], lines: const []);
  final latest = records.last;
  final keepMedia = {for (final k in latest.media.keys) k};
  final keepStems = {for (final k in latest.media.keys) p.withoutExtension(k)};
  final keepLines = latest.lines.toSet();
  final media = <String, String>{};
  final lines = <RecordLine, String>{};
  for (final r in records.take(records.length - 1)) {
    for (final k in r.media.keys) {
      if (_interface.hasMatch(p.dirname(k)) || keepMedia.contains(k) || keepStems.contains(p.withoutExtension(k))) continue;
      media[k] = r.version; // later records overwrite: the last one that had it
    }
    for (final l in r.lines) {
      if (!keepLines.contains(l)) lines[l] = r.version;
    }
  }
  return (
    media: [for (final e in media.entries) Gone(e.key, e.value)]..sort((a, b) => a.item.compareTo(b.item)),
    lines: [for (final e in lines.entries) Gone(e.key, e.value)],
  );
}
