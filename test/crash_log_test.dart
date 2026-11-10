import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/services/crash_log.dart';

void main() {
  late Directory dir;
  late DebugPrintCallback savedPrint;
  late FlutterExceptionHandler? savedError;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vnp_logs');
    CrashLog.directoryForTesting = dir;
    savedPrint = debugPrint;
    savedError = FlutterError.onError;
  });

  tearDown(() async {
    await CrashLog.stopForTesting();
    debugPrint = savedPrint;
    FlutterError.onError = savedError;
    CrashLog.directoryForTesting = null;
    dir.deleteSync(recursive: true);
  });

  test('a normal start has no report and logs the session and debugPrint lines', () async {
    expect(CrashLog.start(), isNull);
    debugPrint('Extracted Game-0.5.zip');
    await CrashLog.stopForTesting();
    final log = File(p.join(dir.path, 'app.log')).readAsStringSync();
    expect(log, contains('=== VN Pathfinder'));
    expect(log, contains('Extracted Game-0.5.zip'));
  });

  test('an unclean run is reported once, with its native crash and last session', () async {
    File(p.join(dir.path, 'app.log')).writeAsStringSync(
        '10:00:00.000 === VN Pathfinder old started ===\n10:00:01.000 old session line\n'
        '11:00:00.000 === VN Pathfinder x started ===\n11:00:01.000 Scanning library\n');
    File(p.join(dir.path, 'unclean-1234')).writeAsStringSync('2026-11-10T11:00:00Z\n');
    File(p.join(dir.path, 'native-crash.txt')).writeAsStringSync(
        'time: 2026-11-10T11:05:00Z\nexception: 0xC0000005\nmodule: comdlg32.dll\noffset: 0x4F82\n');

    final report = CrashLog.start();
    expect(report, isNotNull);
    expect(report!.nativeCrash, contains('comdlg32.dll'));
    expect(report.logTail.join('\n'), contains('Scanning library'));
    expect(report.logTail.join('\n'), isNot(contains('old session line')));
    expect(File(p.join(dir.path, 'unclean-1234')).existsSync(), isFalse);
    expect(dir.listSync().any((f) => p.basename(f.path).startsWith('crash-')), isTrue);

    await CrashLog.stopForTesting();
    expect(CrashLog.start(), isNull, reason: 'reported once');
  });

  test('an older native crash is not blamed on this run', () {
    File(p.join(dir.path, 'unclean-1')).writeAsStringSync('2026-11-10T11:00:00Z\n');
    File(p.join(dir.path, 'native-crash.txt')).writeAsStringSync('time: 2026-11-01T09:00:00Z\nmodule: old.dll\n');
    final report = CrashLog.start()!;
    expect(report.nativeCrash, isNull);
    expect(report.text(), contains('force-quit'));
  });

  test('the log rotates past its size and keeps two old files', () async {
    File(p.join(dir.path, 'app.log')).writeAsStringSync('x' * (CrashLog.maxLogBytes + 10));
    File(p.join(dir.path, 'app.1.log')).writeAsStringSync('older');
    CrashLog.start();
    await CrashLog.stopForTesting();
    expect(File(p.join(dir.path, 'app.2.log')).readAsStringSync(), 'older');
    expect(File(p.join(dir.path, 'app.1.log')).lengthSync(), greaterThan(CrashLog.maxLogBytes));
    expect(File(p.join(dir.path, 'app.log')).lengthSync(), lessThan(1000));
  });

  test('reports leave out library folders, the user folder and the user name', () {
    final text = sanitizeReport(
      r'Scanning D:\Games\VN and C:\Users\Niko\AppData\Roaming\VN Pathfinder for niko',
      libraryDirs: [r'D:\Games\VN'],
      userProfile: r'C:\Users\Niko',
      userName: 'Niko',
    );
    expect(text, r'Scanning <library 1> and <user folder>\AppData\Roaming\VN Pathfinder for <user>');
  });
}
