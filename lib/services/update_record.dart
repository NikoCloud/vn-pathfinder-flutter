import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/library_provider.dart';
import '../providers/version_stats_provider.dart';
import 'renpy_local.dart';
import 'version_records.dart';

/// At most this many thumbnails are kept per update, so a game that redrew
/// everything doesn't fill the disk or hold up the update for long.
const _maxThumbs = 400;

/// Before an update deletes the version it replaces: records that version
/// (if it isn't already), and keeps small thumbnails of the pictures the new
/// version removed or changed, read from the old folder while it's still
/// there. That's the only chance to see them once the folder is gone.
/// Never throws: the update goes ahead whatever happens here.
Future<void> recordBeforeRemoval({
  required UserDataNotifier ud,
  required String baseKey,
  required String oldVersion,
  required String oldFolder,
  required String newFolder,
}) async {
  try {
    if (!Directory(p.join(oldFolder, 'game')).existsSync()) return; // not Ren'Py
    await countVersion(ud, baseKey, oldVersion, oldFolder);
    final before = await compute(_recordMedia, recordPath(baseKey, oldVersion));
    if (before == null) return;
    final after = await compute(_mediaOf, newFolder);
    final afterStems = {for (final k in after.keys) p.withoutExtension(k)};

    final wanted = <String>[];
    for (final e in before.entries) {
      final k = e.key;
      if (!isPicture(k) || isInterfaceArt(k)) continue;
      final now = after[k];
      final gone = now == null && !afterStems.contains(p.withoutExtension(k));
      final changed = now != null && now != e.value;
      if (gone || changed) wanted.add(k);
      if (wanted.length >= _maxThumbs) break;
    }
    if (wanted.isEmpty) return;

    Directory(thumbFolder(baseKey)).createSync(recursive: true);
    for (var i = 0; i < wanted.length; i += 16) {
      final batch = wanted.sublist(i, (i + 16).clamp(0, wanted.length));
      final files = await compute(_read, [oldFolder, ...batch]);
      for (final e in files.entries) {
        final png = await thumbnail(e.value);
        if (png != null) File(thumbPath(baseKey, oldVersion, e.key)).writeAsBytesSync(png);
      }
    }
  } catch (e) {
    debugPrint('Recording the old version failed: $e');
  }
}

/// A picture scaled down to 360 pixels wide, as PNG. Null if it can't be
/// decoded.
Future<Uint8List?> thumbnail(Uint8List bytes, {int width = 360}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Map<String, int>? _recordMedia(String path) => VersionRecord.read(path)?.media;
Map<String, int> _mediaOf(String folder) => mediaOf(Directory(folder));
Map<String, Uint8List> _read(List<String> a) => readGameFiles(Directory(a.first), a.sublist(1));

/// One picture out of a version folder, for showing it full size.
Future<Uint8List?> readPicture(String folder, String key) async =>
    (await compute(_read, [folder, key]))[key];
