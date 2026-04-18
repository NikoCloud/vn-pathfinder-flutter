import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NotificationType { info, success, warning, error }

class AppNotification {
  final String id;
  final String message;
  final NotificationType type;
  final DateTime timestamp;

  AppNotification({
    required this.id,
    required this.message,
    this.type = NotificationType.info,
  }) : timestamp = DateTime.now();
}

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super([]);

  void show(String message, {NotificationType type = NotificationType.info}) {
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      type: type,
    );
    
    state = [...state, notification];

    // Auto-dismiss after 3 seconds
    Timer(const Duration(seconds: 3), () {
      state = state.where((n) => n.id != notification.id).toList();
    });
  }

  void info(String message) => show(message, type: NotificationType.info);
  void success(String message) => show(message, type: NotificationType.success);
  void warning(String message) => show(message, type: NotificationType.warning);
  void error(String message) => show(message, type: NotificationType.error);
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, List<AppNotification>>(
  (ref) => NotificationNotifier(),
);
