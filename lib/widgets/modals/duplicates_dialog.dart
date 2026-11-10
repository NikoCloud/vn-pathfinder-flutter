import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/disk_space.dart' show formatBytes;
import '../../services/duplicates.dart';
import '../../theme.dart';
import '../common/kit.dart';

/// Games with the same version in more than one folder (#21).
final duplicatesProvider = Provider<List<DuplicateSet>>((ref) {
  final groups = ref.watch(libraryGroupsProvider);
  return findDuplicates(groups, ref.watch(libraryDirsProvider));
});

/// The yellow banner over the Library when duplicates are found. Nothing is
/// merged until the user opens it and confirms.
class DuplicatesBanner extends ConsumerWidget {
  const DuplicatesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(duplicatesProvider);
    if (sets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 8, AppLayout.gutter, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: AppRadius.borderSm,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Duplicates identified. Do you wish to merge? '
                '${sets.length} game${sets.length == 1 ? ' has' : 's have'} the same version in more than one folder.',
                style: AppText.ui(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            VpButton(
              label: 'Review',
              small: true,
              tone: VpTone.primary,
              onTap: () => showDialog<void>(context: context, builder: (_) => const DuplicatesDialog()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains every change before anything happens: which copy stays, what each
/// other copy holds, which saves move, and how the other copy is removed.
class DuplicatesDialog extends ConsumerStatefulWidget {
  const DuplicatesDialog({super.key});

  @override
  ConsumerState<DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends ConsumerState<DuplicatesDialog> {
  List<MergePlan>? _plans;
  bool _toTrash = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sets = ref.read(duplicatesProvider);
    final plans = <MergePlan>[];
    for (final s in sets) {
      plans.add(await planMerge(s));
    }
    if (mounted) setState(() => _plans = plans);
  }

  Future<void> _merge() async {
    final plans = _plans;
    if (plans == null) return;
    setState(() => _working = true);
    var done = 0;
    String? failure;
    for (final plan in plans) {
      try {
        await runMerge(plan, toTrash: _toTrash);
        done++;
      } catch (e) {
        failure = '$e';
      }
    }
    await ref.read(libraryProvider.notifier).scan();
    if (!mounted) return;
    Navigator.pop(context);
    final n = ref.read(notificationProvider.notifier);
    if (failure == null) {
      n.success('Merged $done game${done == 1 ? '' : 's'}');
    } else {
      n.error('Merged $done; one failed: $failure');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final anyTrash = plans?.any((pl) => pl.copies.any((c) => c.drive.trashSafe)) ?? false;
    final anyForcedDelete = plans?.any((pl) => pl.copies.any((c) => !c.drive.trashSafe)) ?? false;

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd, side: BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Merge duplicates', style: AppText.heading()),
              ]),
              const SizedBox(height: 8),
              Text(
                'For each game, the copy in your highest library folder stays (the order in Settings → General). '
                'Saves from the other copy move into it; where both have the same save, the newer one is kept. '
                'Then the other copy is removed.',
                style: AppText.ui(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: plans == null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text('Comparing the copies…',
                              style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
                        ),
                      )
                    : ListView(shrinkWrap: true, children: [for (final pl in plans) _PlanCard(pl)]),
              ),
              const SizedBox(height: 12),
              if (plans != null) ...[
                if (anyTrash)
                  RadioGroup<bool>(
                    groupValue: _toTrash,
                    onChanged: (v) => setState(() => _toTrash = v ?? false),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Choice(
                          value: true,
                          title: 'Send to the Recycle Bin',
                          note: 'Only on internal drives. Some external drives in an enclosure look internal to '
                              'Windows; on those, choose Delete permanently.',
                        ),
                        const _Choice(value: false, title: 'Delete permanently', note: 'This cannot be undone.'),
                      ],
                    ),
                  ),
                if (anyForcedDelete)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Copies on removable drives, network shares or drives the app can\'t identify are deleted '
                      'permanently: their trash stays hidden on the drive and keeps the space.',
                      style: AppText.ui(fontSize: 11, color: AppColors.warning, height: 1.4),
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  VpButton(label: 'Cancel', tone: VpTone.quiet, small: true, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  VpButton(
                    label: 'Merge',
                    tone: VpTone.primary,
                    small: true,
                    busy: _working,
                    onTap: plans == null || plans.isEmpty || _working ? null : _merge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final bool value;
  final String title;
  final String note;
  const _Choice({required this.value, required this.title, required this.note});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Radio<bool>(value: value, visualDensity: VisualDensity.compact),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$title  ', style: AppText.ui(fontSize: 12, color: AppColors.textPrimary)),
                  TextSpan(text: note, style: AppText.ui(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
            ),
          ),
        ],
      );
}

class _PlanCard extends StatelessWidget {
  final MergePlan plan;
  const _PlanCard(this.plan);

  @override
  Widget build(BuildContext context) {
    final set = plan.set;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: AppRadius.borderSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${set.title} · ${set.versionStr}',
              style: AppText.ui(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          _PathLine(label: 'Keeps', path: set.keep.folderPath.path, color: AppColors.accent),
          for (final c in plan.copies) ...[
            _PathLine(
              label: c.drive.trashSafe ? 'Removes' : 'Deletes',
              path: c.folder,
              color: AppColors.textMuted,
              tooltip: c.drive.reason,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 64, top: 2),
              child: Text(
                [
                  '${formatBytes(c.bytes)}, ${c.files} files',
                  if (c.savesToMove.isNotEmpty) '${c.savesToMove.length} save${c.savesToMove.length == 1 ? '' : 's'} move',
                  if (c.conflicts.isNotEmpty)
                    '${c.conflicts.length} in both: ${c.conflicts.values.where((v) => v).length} newer here, kept',
                  if (c.savesToMove.isEmpty && c.conflicts.isEmpty) 'no saves of its own',
                ].join(' · '),
                style: AppText.ui(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  final String label;
  final String path;
  final Color color;
  final String? tooltip;
  const _PathLine({required this.label, required this.path, required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text(label, style: AppText.ui(fontSize: 11, color: color))),
            Expanded(
              child: Tooltip(
                message: tooltip == null ? path : '$path\n$tooltip',
                child: Text(path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(fontSize: 11, color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      );
}
