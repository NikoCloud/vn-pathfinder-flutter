import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_update_service.dart' show appVersion;

/// The app's log and its crash reports (#22). Kept in
/// `%APPDATA%\VN Pathfinder\logs`. Nothing leaves this PC: a report is only
/// shown, and copied when the user presses Copy.
///
/// Three sources:
///   • `app.log`, rotated at about 1 MB into `app.1.log` and `app.2.log`:
///     errors from Flutter's hooks, plus every `debugPrint` line the app
///     already writes (scans, downloads, extractions, updates).
///   • `native-crash.txt`, written by the Windows launcher when a crash
///     happens in native code, which Dart never sees.
///   • `unclean-<pid>`, left by the launcher when the last run didn't end
///     normally (a crash, a force-quit, a power cut).
class CrashLog {
  CrashLog._();

  static const maxLogBytes = 1024 * 1024;
  static const keepOldLogs = 2;
  static const reportLines = 200;

  static Directory? _dirOverride;
  static IOSink? _sink;
  static int _written = 0;

  /// For tests.
  @visibleForTesting
  static set directoryForTesting(Directory? dir) => _dirOverride = dir;

  static Directory get logsDir =>
      _dirOverride ?? Directory(p.join(Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'logs'));

  static File get _log => File(p.join(logsDir.path, 'app.log'));

  /// Starts the log and hooks Flutter's errors into it. Returns a report when
  /// the last run ended badly, read before this session writes anything.
  static CrashReport? start() {
    CrashReport? report;
    try {
      logsDir.createSync(recursive: true);
      report = _readLastRun();
      _rotateIfLarge();
      _sink = _log.openWrite(mode: FileMode.append);
      _written = _log.existsSync() ? _log.lengthSync() : 0;
      write('=== VN Pathfinder $appVersion started ${DateTime.now().toIso8601String()} '
          'on ${Platform.operatingSystemVersion} ===');
    } catch (_) {
      // A log that can't be written must never stop the app.
    }

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      write('ERROR ${details.exceptionAsString()}\n${details.stack ?? ''}');
      (previousFlutterError ?? FlutterError.presentError)(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      write('ERROR $error\n$stack');
      return true;
    };
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      previousPrint(message, wrapWidth: wrapWidth);
      if (message != null) write(message);
    };
    return report;
  }

  @visibleForTesting
  static Future<void> stopForTesting() async {
    final sink = _sink;
    _sink = null;
    await sink?.close();
  }

  /// Appends a line with the time. Rotates once the file passes [maxLogBytes].
  static void write(String message) {
    final sink = _sink;
    if (sink == null) return;
    final line = '${DateTime.now().toIso8601String().substring(11, 23)} $message\n';
    try {
      sink.write(line);
      _written += line.length;
      if (_written > maxLogBytes) {
        _sink = null;
        sink.close();
        _rotateIfLarge(force: true);
        _sink = _log.openWrite(mode: FileMode.append);
        _written = 0;
      }
    } catch (_) {}
  }

  /// The updater ends the process with exit(0), which skips the launcher's
  /// normal-exit cleanup; this removes this run's marker so it isn't reported.
  static Future<void> beforeExit() async {
    try {
      await _sink?.flush();
      final marker = File(p.join(logsDir.path, 'running-$pid'));
      if (marker.existsSync()) marker.deleteSync();
    } catch (_) {}
  }

  static void _rotateIfLarge({bool force = false}) {
    final log = _log;
    if (!log.existsSync() || (!force && log.lengthSync() < maxLogBytes)) return;
    for (var i = keepOldLogs; i >= 1; i--) {
      final from = i == 1 ? log : File(p.join(logsDir.path, 'app.${i - 1}.log'));
      final to = File(p.join(logsDir.path, 'app.$i.log'));
      if (!from.existsSync()) continue;
      if (to.existsSync()) to.deleteSync();
      from.renameSync(to.path);
    }
  }

  static CrashReport? _readLastRun() {
    final flags = logsDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('unclean-'))
        .toList();
    if (flags.isEmpty) return null;
    DateTime? started;
    for (final f in flags) {
      final t = DateTime.tryParse(f.readAsStringSync().trim());
      if (t != null && (started == null || t.isAfter(started))) started = t;
      f.deleteSync();
    }

    String? native;
    final nativeFile = File(p.join(logsDir.path, 'native-crash.txt'));
    if (nativeFile.existsSync()) {
      final text = nativeFile.readAsStringSync();
      final at = DateTime.tryParse(RegExp(r'time: (\S+)').firstMatch(text)?.group(1) ?? '');
      // Only a crash from the run being reported, not an older one.
      if (at != null && (started == null || !at.isBefore(started))) native = text.trim();
    }

    final logLines = _log.existsSync() ? _lastSession(_log.readAsLinesSync()) : <String>[];
    final report = CrashReport(started: started, nativeCrash: native, logTail: logLines);
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      File(p.join(logsDir.path, 'crash-$stamp.txt')).writeAsStringSync(report.text());
    } catch (_) {}
    return report;
  }

  /// The last session's lines, at most [reportLines].
  static List<String> _lastSession(List<String> lines) {
    final start = lines.lastIndexWhere((l) => l.contains('=== VN Pathfinder '));
    final session = start < 0 ? lines : lines.sublist(start);
    return session.length > reportLines ? session.sublist(session.length - reportLines) : session;
  }
}

/// What's known about a run that ended badly.
class CrashReport {
  final DateTime? started;
  final String? nativeCrash;
  final List<String> logTail;

  const CrashReport({this.started, this.nativeCrash, this.logTail = const []});

  /// The report as text, with personal paths replaced (see [sanitizeReport]).
  String text({List<String> libraryDirs = const []}) {
    final b = StringBuffer()
      ..writeln('VN Pathfinder $appVersion closed unexpectedly')
      ..writeln('Windows: ${Platform.operatingSystemVersion}')
      ..writeln('Run started: ${started?.toIso8601String() ?? 'unknown'}')
      ..writeln()
      ..writeln(nativeCrash == null
          ? 'No native crash was recorded. The app may have been closed by Windows, a force-quit or a power cut.'
          : 'Native crash:\n$nativeCrash')
      ..writeln()
      ..writeln('Last log lines:');
    for (final l in logTail) {
      b.writeln(l);
    }
    return sanitizeReport(b.toString(), libraryDirs: libraryDirs);
  }
}

/// Replaces what could identify the user: library folders become
/// `<library 1>` and so on, the Windows profile folder `<user folder>`, and
/// the account name `<user>`.
String sanitizeReport(
  String text, {
  List<String> libraryDirs = const [],
  String? userProfile,
  String? userName,
}) {
  final profile = userProfile ?? Platform.environment['USERPROFILE'] ?? '';
  final name = userName ?? Platform.environment['USERNAME'] ?? '';
  var out = text;
  final libs = [...libraryDirs]..sort((a, b) => b.length.compareTo(a.length));
  for (final lib in libs) {
    if (lib.isEmpty) continue;
    out = _replaceAllIgnoreCase(out, lib, '<library ${libraryDirs.indexOf(lib) + 1}>');
  }
  if (profile.isNotEmpty) out = _replaceAllIgnoreCase(out, profile, '<user folder>');
  if (name.length >= 2) out = _replaceAllIgnoreCase(out, name, '<user>');
  return out;
}

String _replaceAllIgnoreCase(String text, String find, String replace) =>
    text.replaceAll(RegExp(RegExp.escape(find), caseSensitive: false), replace);
