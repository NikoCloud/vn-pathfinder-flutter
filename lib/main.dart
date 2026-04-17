import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(960, 600),
    center: true,
    title: 'VN Pathfinder',
    backgroundColor: Color(0xFF1A1D23),
    titleBarStyle: TitleBarStyle.normal,
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: VNPathfinderApp()));
}
