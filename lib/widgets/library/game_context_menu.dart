import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/archive_item.dart';
import '../../models/game_group.dart';
import '../../models/game_status.dart';
import '../../models/game_version.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../utils/formatters.dart';
import '../common/kit.dart';
import '../common/status_menu.dart';
import '../modals/merge_game_dialog.dart';
import '../modals/metadata_fetch_modal.dart';
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
      side: BorderSide(color: AppColors.border),
    ),
    items: [
      PopupMenuItem(
        value: 'play',
        height: 36,
        child: _MenuRow(icon: Icons.play_arrow, label: 'Play', color: AppColors.accent),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'status',
        height: 36,
        child: _MenuRow(icon: Icons.star_outline, label: 'Change Status', trailing: Icons.chevron_right),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'fetch',
        height: 36,
        child: _MenuRow(icon: Icons.download_outlined, label: 'Fetch Metadata'),
      ),
      PopupMenuItem(
        value: 'properties',
        height: 36,
        child: _MenuRow(icon: Icons.tune_outlined, label: 'Properties'),
      ),
      PopupMenuItem(
        value: 'image',
        height: 36,
        child: _MenuRow(icon: Icons.image_outlined, label: 'Change Image'),
      ),
      PopupMenuItem(
        value: 'folder',
        height: 36,
        child: _MenuRow(icon: Icons.folder_open_outlined, label: 'Open Folder'),
      ),
      PopupMenuItem(
        value: 'saves',
        height: 36,
        child: _MenuRow(icon: Icons.save_outlined, label: 'Open Saves Folder'),
      ),
      PopupMenuItem(
        value: 'copy_path',
        height: 36,
        child: _MenuRow(icon: Icons.content_copy_outlined, label: 'Copy Path'),
      ),
      PopupMenuItem(
        value: 'merge',
        height: 36,
        child: _MenuRow(icon: Icons.call_merge, label: 'Merge into Another Game…'),
      ),
      if (group.archives.isNotEmpty)
        PopupMenuItem(
          value: 'archives',
          height: 36,
          child: _MenuRow(icon: Icons.delete_outline, label: 'Delete Archive…'),
        ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'hide',
        height: 36,
        child: ref.read(userDataProvider).hidden.contains(group.baseKey)
            ? _MenuRow(icon: Icons.visibility_outlined, label: 'Unhide')
            : _MenuRow(icon: Icons.visibility_off_outlined, label: 'Hide from Library'),
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
        side: BorderSide(color: AppColors.border),
      ),
      items: () {
        final ud = ref.read(userDataProvider);
        return statusMenuEntries(
          detected: detectedGameStatus(group, ud),
          picked: GameStatus.fromId(ud.status[group.baseKey]),
        );
      }(),
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
    case 'saves':
      _openSavesFolder(v, ref);
      break;
    case 'copy_path':
      Clipboard.setData(ClipboardData(text: v.folderPath.path));
      break;
    case 'merge':
      if (context.mounted) showMergeGameDialog(context, group);
      break;
    case 'fetch':
      if (context.mounted) showMetadataFetchModal(context, group);
      break;
    case 'image':
      if (context.mounted) showPropertiesModal(context, group, openArt: true);
      break;
    case 'archives':
      if (context.mounted) await _deleteArchives(context, ref, group);
      break;
    case 'hide':
      final notifier = ref.read(userDataProvider.notifier);
      notifier.setHidden(group.baseKey, !ref.read(userDataProvider).hidden.contains(group.baseKey));
      break;
  }
}

/// A game's archive files, with anything being extracted held back. Nothing is
/// ticked to begin with: deleting is the one thing here that can't be undone.
Future<void> _deleteArchives(BuildContext context, WidgetRef ref, GameGroup group) async {
  final status = ref.read(extractionStatusProvider);
  final free = group.archives.where((a) {
    final s = status[a.archivePath.path];
    return s == null || !(s.running || s.queued);
  }).toList();
  if (free.isEmpty) {
    ref.read(notificationProvider.notifier).warning('Its archives are being extracted. Cancel that first.');
    return;
  }
  final chosen = <ArchiveItem>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text('Delete archives', style: AppText.heading()),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in free)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.accent,
                  value: chosen.contains(a),
                  onChanged: (v) => setDialog(() => v == true ? chosen.add(a) : chosen.remove(a)),
                  title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body()),
                  secondary: Text(fmtBytes(a.sizeBytes ?? 0), style: AppText.data(color: AppColors.textMuted)),
                ),
            ],
          ),
        ),
        actions: [
          VpButton(label: 'Cancel', tone: VpTone.quiet, small: true, onTap: () => Navigator.of(ctx).pop(false)),
          VpButton(
            label: 'Delete',
            tone: VpTone.danger,
            small: true,
            onTap: chosen.isEmpty ? null : () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final names = chosen.map((a) => a.name).toSet();
  for (final a in chosen) {
    try {
      await a.archivePath.delete();
    } catch (e) {
      ref.read(notificationProvider.notifier).error('${a.name} could not be deleted: $e');
    }
  }
  for (final card in ref.read(archiveCardsProvider)) {
    if (names.contains(card.fileName)) card.delete();
  }
  ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
  ref.read(libraryProvider.notifier).scan();
}

void _openSavesFolder(GameVersion version, WidgetRef ref) {
  // Ren'Py writes saves to the game's own folder and to AppData. The scanner
  // has already found both.
  for (final dir in [version.localSaveDir, ?version.appdataSaveDir]) {
    if (dir.existsSync()) {
      Process.run('explorer', [dir.path]);
      return;
    }
  }

  final appdata = Platform.environment['APPDATA'] ?? '';
  final renPyRoot = Directory(p.join(appdata, 'RenPy'));
  if (renPyRoot.existsSync()) {
    Process.run('explorer', [renPyRoot.path]);
    ref.read(notificationProvider.notifier).info(
      'No saves folder in game/saves/ — opened %APPDATA%\\RenPy\\ instead',
    );
    return;
  }

  ref.read(notificationProvider.notifier).warning('No saves folder found for this game.');
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
