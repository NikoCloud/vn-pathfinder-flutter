import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/widgets/crash_report_prompt.dart';

void main() {
  testWidgets('the crash dialog shows the report on request and copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CrashReportDialog(text: 'REPORT BODY'))));

    expect(find.text('VN Pathfinder closed unexpectedly last time'), findsOneWidget);
    expect(find.text('REPORT BODY'), findsNothing);
    expect(find.text('Report on GitHub'), findsNothing);

    await tester.tap(find.text('View report'));
    await tester.pump();
    expect(find.text('REPORT BODY'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, 'REPORT BODY');
    expect(find.text('Copied'), findsOneWidget);
  });
}
