import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'services/crash_log.dart';
import 'widgets/crash_report_prompt.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else, so the last run's log is read before this one writes.
  final crashReport = CrashLog.start();

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(960, 600),
    center: true,
    title: 'VN Pathfinder',
    backgroundColor: Color(0xFF0D1017),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(ProviderScope(
    overrides: [crashReportProvider.overrideWith((ref) => crashReport)],
    child: const VNPathfinderApp(),
  ));
}
