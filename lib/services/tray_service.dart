import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Minimize to the system tray (Settings → General). The tray icon only exists
/// while the setting is on.
class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final instance = TrayService._();

  bool _enabled = false;

  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled || !Platform.isWindows) return;
    _enabled = enabled;
    try {
      if (enabled) {
        trayManager.addListener(this);
        windowManager.addListener(this);
        await trayManager.setIcon('assets/tray_icon.ico');
        await trayManager.setToolTip('VN Pathfinder');
        await trayManager.setContextMenu(Menu(items: [
          MenuItem(key: 'open', label: 'Open VN Pathfinder'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ]));
      } else {
        trayManager.removeListener(this);
        windowManager.removeListener(this);
        await trayManager.destroy();
      }
    } catch (e) {
      debugPrint('System tray failed: $e');
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowMinimize() => windowManager.hide();

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open') _showWindow();
    if (menuItem.key == 'quit') windowManager.destroy();
  }
}
