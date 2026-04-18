import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_group.dart';
import '../../providers/library_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../modals/properties_modal.dart';
import '../../theme.dart';

void showGameContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Offset globalPosition,
  required GameGroup group,
}) async {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  
  final v = group.latestVersion;
  if (v == null) return;

  final relativePosition = RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );

  final result = await showMenu<String>(
    context: context,
    position: relativePosition,
    color: AppColors.bgCard,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderMd,
      side: const BorderSide(color: AppColors.border),
    ),
    items: [
      PopupMenuItem(
        value: 'play',
        height: 36,
        child: _MenuRow(icon: Icons.play_arrow, label: 'PLAY', color: AppColors.playGreen),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'status',
        height: 36,
        child: _MenuRow(icon: Icons.star_outline, label: 'Change Status', trailing: Icons.chevron_right),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'properties',
        height: 36,
        child: _MenuRow(icon: Icons.tune_outlined, label: 'Properties'),
      ),
      PopupMenuItem(
        value: 'folder',
        height: 36,
        child: _MenuRow(icon: Icons.folder_open_outlined, label: 'Open Folder'),
      ),
      PopupMenuItem(
        value: 'copy_path',
        height: 36,
        child: _MenuRow(icon: Icons.content_copy_outlined, label: 'Copy Path'),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'remove',
        height: 36,
        child: _MenuRow(icon: Icons.delete_outline, label: 'Remove from Library', color: AppColors.danger),
      ),
    ],
  );

  if (result == null) return;

  if (result == 'status') {
    if (!context.mounted) return;
    
    // Submenu for status
    final statusResult = await showMenu<String>(
      context: context,
      position: relativePosition,
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: const BorderSide(color: AppColors.border),
      ),
      items: [
        _statusItem('unplayed', 'Unplayed', Icons.circle_outlined),
        _statusItem('playing', 'Playing', Icons.play_circle_outline, color: AppColors.playGreen),
        _statusItem('completed', 'Completed', Icons.check_circle_outline, color: AppColors.accent),
        _statusItem('on-hold', 'On Hold', Icons.pause_circle_outline, color: Colors.orange),
        _statusItem('abandoned', 'Abandoned', Icons.do_not_disturb_on_outlined, color: AppColors.danger),
      ],
    );

    if (statusResult != null) {
      ref.read(userDataProvider.notifier).setStatus(group.baseKey, statusResult);
    }
    return;
  }

  switch (result) {
    case 'play':
      ref.read(playTrackerProvider.notifier).launch(v, group.baseKey);
      break;
    case 'properties':
      if (context.mounted) showPropertiesModal(context, group);
      break;
    case 'folder':
      Process.run('explorer', [v.folderPath.path]);
      break;
    case 'copy_path':
      Clipboard.setData(ClipboardData(text: v.folderPath.path));
      break;
    case 'remove':
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: const Text('Remove from Library?', style: TextStyle(color: Colors.white)),
          content: Text('This will hide "${group.effectiveTitle}" from your library. Files will not be deleted.',
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('REMOVE', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        ref.read(userDataProvider.notifier).setHidden(group.baseKey, true);
      }
      break;
  }
}

PopupMenuItem<String> _statusItem(String value, String label, IconData icon, {Color? color}) {
  return PopupMenuItem(
    value: value,
    height: 36,
    child: _MenuRow(icon: icon, label: label, color: color),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final IconData? trailing;

  const _MenuRow({required this.icon, required this.label, this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 14, color: AppColors.textMuted),
      ],
    );
  }
}
