import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_group.dart';
import '../../providers/library_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/update_check_service.dart';
import '../../theme.dart';

/// Picks the game [source] should become part of, for two library entries
/// that are really one game. Games that look the same are listed first.
void showMergeGameDialog(BuildContext context, GameGroup source) {
  showDialog<void>(context: context, builder: (_) => _MergeGameDialog(source: source));
}

class _MergeGameDialog extends ConsumerStatefulWidget {
  final GameGroup source;
  const _MergeGameDialog({required this.source});

  @override
  ConsumerState<_MergeGameDialog> createState() => _MergeGameDialogState();
}

class _MergeGameDialogState extends ConsumerState<_MergeGameDialog> {
  String _query = '';
  GameGroup? _target;

  void _merge() {
    final target = _target;
    if (target == null) return;
    ref.read(userDataProvider.notifier).mergeGames(widget.source.baseKey, target.baseKey);
    ref.read(libraryProvider.notifier).select(target.baseKey);
    ref.read(notificationProvider.notifier).success('Merged into ${target.effectiveTitle}');
    Navigator.of(context).pop();
  }

  bool _matches(GameGroup g) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return g.effectiveTitle.toLowerCase().contains(q) ||
        g.versions.any((v) => v.folderName.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final hidden = ref.watch(userDataProvider).hidden;
    final games = ref
        .watch(libraryProvider)
        .groups
        .where((g) =>
            g.versions.isNotEmpty &&
            g.baseKey != source.baseKey &&
            !hidden.contains(g.baseKey) &&
            _matches(g))
        .toList();
    final likely = games.where((g) => UpdateCheckService.looksLikeSameGame(source, g)).toList();
    final others = games.where((g) => !likely.contains(g)).toList();

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 480,
        height: 540,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Merge "${source.effectiveTitle}"',
                style: AppText.ui(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Pick the game it belongs to. Its versions move under that game, and new '
                'versions will join automatically. Your game files stay where they are, and '
                'you can undo this in Properties → Versions.',
                style: AppText.ui(
                    fontSize: 12, height: 1.45, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: AppText.ui(fontSize: 12, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search your library',
                  hintStyle: AppText.ui(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.borderMd,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.borderMd,
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: games.isEmpty
                    ? Center(
                        child: Text('No games found',
                            style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
                      )
                    : ListView(
                        children: [
                          if (likely.isNotEmpty) ...[
                            const _SectionLabel('Likely the same game'),
                            for (final g in likely) _row(g),
                          ],
                          if (others.isNotEmpty) ...[
                            const _SectionLabel('All games'),
                            for (final g in others) _row(g),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _target == null ? null : _merge,
                    child: Text('Merge',
                        style: TextStyle(
                            color: _target == null ? AppColors.textMuted : AppColors.accent)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(GameGroup g) {
    final selected = _target?.baseKey == g.baseKey;
    final folders = g.versions.map((v) => v.folderName).join(', ');
    return InkWell(
      onTap: () => setState(() => _target = g),
      borderRadius: AppRadius.borderMd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.bgActive : Colors.transparent,
          borderRadius: AppRadius.borderMd,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.effectiveTitle,
                      style: AppText.ui(fontSize: 12, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(folders,
                      style: AppText.ui(fontSize: 11, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 15, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(text,
          style: AppText.ui(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.textMuted)),
    );
  }
}
