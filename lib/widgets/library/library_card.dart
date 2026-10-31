import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_group.dart';
import '../../models/game_status.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../providers/update_provider.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/art_card.dart';
import '../common/kit.dart';
import '../common/status_menu.dart';
import '../get/get_sheet.dart';
import '../game/game_actions.dart';
import 'game_context_menu.dart';

/// A game you have, as a card. [onOpen] defaults to the game page.
class LibraryCard extends ConsumerWidget {
  final GameGroup group;
  final bool picking;
  final bool picked;
  final VoidCallback? onOpen;

  const LibraryCard({super.key, required this.group, this.picking = false, this.picked = false, this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final ud = ref.watch(userDataProvider);
    final status = effectiveGameStatus(g, ud);
    final update = ref.watch(availableUpdatesProvider)[g.baseKey];
    final running = ref.watch(isGameRunningProvider(g.baseKey));
    final job = jobFor(ref.watch(downloadsProvider), g.effectiveTitle);
    final art = localArt(g, ref);
    final seconds = ud.playtime[g.baseKey] ?? 0;
    final hidden = ud.hidden.contains(g.baseKey);
    final version = g.latestVersion?.versionStr ?? '';

    final chip = job != null
        ? VpBadge(
            label: job.stage == JobStage.extracting
                ? 'Extracting'
                : job.progress == null
                    ? 'Downloading'
                    : '${(job.progress! * 100).round()}%',
            mono: true,
            fill: AppColors.accent,
            color: AppColors.onAccent,
          )
        : update != null
            ? NewVersionBadge(label: 'New version ${fmtVersion(update.version)}')
            : running
                ? VpBadge(label: 'Running', fill: AppColors.accent, color: AppColors.onAccent)
                : hidden
                    ? const VpBadge(label: 'Hidden')
                    : null;

    return ArtCard(
      art: art,
      epoch: ref.watch(imageEpochProvider),
      title: g.effectiveTitle,
      subtitle: [g.effectiveDeveloper, if (seconds > 0) fmtTime(seconds)].where((s) => s.isNotEmpty).join(' · '),
      topLeft: VpBadge(label: status.label, icon: statusIcon(status), color: const Color(0xFFE8EBF1)),
      topRight: chip,
      version: version.isEmpty ? null : fmtVersion(version),
      peekText: g.newestMetaTags.take(4).join(', '),
      semanticLabel: '${g.effectiveTitle}, ${status.label}${version.isEmpty ? '' : ', ${fmtVersion(version)}'}',
      picking: picking,
      picked: picked,
      onOpen: onOpen ?? () => openGame(ref, baseKey: g.baseKey),
      onHover: (on) => setAmbientHover(ref, on ? art : null),
      onSecondaryTapDown: (d) => showGameContextMenu(
        context: context,
        ref: ref,
        globalPosition: d.globalPosition,
        group: g,
      ),
      actions: [
        if (job != null)
          const SizedBox.shrink()
        else if (update != null)
          VpButton(
            label: 'Update',
            icon: Icons.download_rounded,
            tone: VpTone.update,
            small: true,
            onTap: () => showGetSheet(context, ref, title: g.effectiveTitle, group: g, version: update.version),
          )
        else
          VpButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            tone: VpTone.primary,
            small: true,
            onTap: () => playGame(context, ref, g),
          ),
        Builder(
          builder: (context) => VpIconButton(
            icon: Icons.more_horiz,
            tooltip: 'More actions',
            onArt: true,
            onTap: () {
              final box = context.findRenderObject() as RenderBox;
              showGameContextMenu(
                context: context,
                ref: ref,
                globalPosition: box.localToGlobal(Offset(0, box.size.height + 4)),
                group: g,
              );
            },
          ),
        ),
      ],
    );
  }
}
