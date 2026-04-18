import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/notification_provider.dart';
import '../../theme.dart';

class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationProvider);

    return Positioned(
      bottom: 24,
      right: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: notifications.map((n) => _ToastItem(notification: n)).toList(),
      ),
    );
  }
}

class _ToastItem extends StatelessWidget {
  final AppNotification notification;

  const _ToastItem({required this.notification});

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final icon = _getIcon();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(50 * (1 - value), 0),
            child: Opacity(
              opacity: value.clamp(0, 1),
              child: child,
            ),
          );
        },
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard.withValues(alpha: 0.95),
            borderRadius: AppRadius.borderMd,
            border: Border.all(color: color.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notification.message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getColor() {
    return switch (notification.type) {
      NotificationType.success => AppColors.playGreen,
      NotificationType.warning => Colors.orange,
      NotificationType.error   => AppColors.danger,
      _                        => AppColors.accent,
    };
  }

  IconData _getIcon() {
    return switch (notification.type) {
      NotificationType.success => Icons.check_circle_outline,
      NotificationType.warning => Icons.warning_amber_rounded,
      NotificationType.error   => Icons.error_outline_rounded,
      _                        => Icons.info_outline_rounded,
    };
  }
}
