import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/play_tracker_provider.dart';

void main() {
  test('access denied points at the share and antivirus', () {
    final m = launchFailureMessage(const ProcessException('Game.exe', [], 'Access is denied.', 5));
    expect(m, contains('network share'));
    expect(m, contains('Antivirus'));
  });

  test('anything else keeps the original error', () {
    final m = launchFailureMessage(const ProcessException('Game.exe', [], 'The system cannot find the file', 2));
    expect(m, startsWith('Failed to launch:'));
    expect(m, contains('cannot find the file'));
  });
}
