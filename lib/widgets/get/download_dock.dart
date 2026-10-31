import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/feed_item.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/library_provider.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/art.dart';
import '../common/kit.dart';
import '../game/game_actions.dart';

/// Games on their way in, in the bottom corner on every tab.
class DownloadDock extends ConsumerWidget {
  const DownloadDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(downloadsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final job in jobs) ...[_JobRow(job: job), const SizedBox(height: 8)],
      ],
    );
  }
}

class _JobRow extends ConsumerWidget {
  final DownloadJob job;
  const _JobRow({required this.job});

  String get _status {
    final version = job.version.isEmpty ? 'It' : fmtVersion(job.version);
    final amount = job.progress == null ? fmtBytes(job.received) : '${(job.progress! * 100).round()}%';
    return switch (job.stage) {
      JobStage.downloading => job.tries > 1 ? 'Connection dropped. Try ${job.tries}, $amount' : 'Downloading $amount',
      JobStage.waiting => 'Waiting to extract',
      JobStage.extracting => 'Extracting to your library',
      JobStage.ready => '$version is ready to play',
      JobStage.saved => job.message,
      JobStage.failed => job.message,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.read(downloadsProvider.notifier);
    final key = feedTitleKey(job.title);
    final game = ref.watch(libraryProvider).groups.where((g) {
      return g.versions.isNotEmpty && (g.baseKey == job.baseKey || feedTitleKey(g.effectiveTitle) == key);
    }).firstOrNull;

    return Container(
      width: 340,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.96),
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderLg,
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 36, offset: Offset(0, 14))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 40,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(5)),
              child: GameArt(source: job.cover.isEmpty ? null : job.cover, decodeWidth: 96),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(job.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(fontWeight: FontWeight.w600)),
                Text(_status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta(color: job.stage == JobStage.failed ? AppColors.danger : AppColors.textSecondary)),
                if (job.active) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                    child: LinearProgressIndicator(
                      value: job.stage == JobStage.waiting ? null : job.progress,
                      minHeight: 3,
                      color: AppColors.accent,
                      backgroundColor: AppColors.bgActive,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (job.stage == JobStage.ready && game != null) ...[
            VpIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Play',
              selected: true,
              onTap: () {
                downloads.dismiss(job);
                playGame(context, ref, game);
              },
            ),
            const SizedBox(width: 4),
          ],
          if (job.stage == JobStage.downloading)
            VpIconButton(icon: Icons.close, tooltip: 'Cancel', onTap: () => downloads.cancel(job))
          else if (!job.active)
            VpIconButton(icon: Icons.close, tooltip: 'Dismiss', onTap: () => downloads.dismiss(job)),
        ],
      ),
    );
  }
}
