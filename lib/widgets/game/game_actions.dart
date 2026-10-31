import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/feed_item.dart';
import '../../models/game_group.dart';
import '../../models/game_version.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/feed_view_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../providers/shell_provider.dart';
import '../../services/scanner_service.dart';
import '../../utils/formatters.dart';
import '../common/kit.dart';
import '../get/get_sheet.dart';

/// Things every game surface can do, in one place, so a card, a row and the
/// game page all behave the same.

void setAmbientHover(WidgetRef ref, String? art) => ref.read(ambientHoverProvider.notifier).state = art;

void setAmbientRest(WidgetRef ref, AppTab tab, String? art) {
  final rest = ref.read(ambientRestProvider);
  if (rest[tab] != art) ref.read(ambientRestProvider.notifier).state = {...rest, tab: art};
}

void toggleWatch(WidgetRef ref, RawFeedItem item) {
  final key = feedTitleKey(item.title);
  final watching = ref.read(userDataProvider).watching.contains(key);
  ref.read(userDataProvider.notifier).setWatching(key, !watching);
  ref.read(notificationProvider.notifier).info(
      watching ? 'No longer watching' : 'Watching. New versions will reach you here.');
}

void openGame(WidgetRef ref, {String? baseKey, RawFeedItem? item}) {
  final current = ref.read(gamePageProvider);
  ref.read(gamePageProvider.notifier).state = GameTarget(
    baseKey: baseKey,
    item: item,
    origin: current?.origin ?? ref.read(activeTabProvider),
  );
}

Future<void> playGame(BuildContext context, WidgetRef ref, GameGroup group, [GameVersion? version]) async {
  final v = version ?? group.latestVersion;
  if (v == null) return;
  final error = await ref.read(playTrackerProvider.notifier).launch(v, group.baseKey);
  if (error != null) ref.read(notificationProvider.notifier).error(error);
}

/// The local cover of a library game, if it has one.
String? localArt(GameGroup g, WidgetRef ref) {
  final images = groupCarouselPaths(g, ref.read(userDataProvider).customArt[g.baseKey]);
  return images.isEmpty ? null : images.first.path;
}

/// The right art for a Feed row: your copy's if you have one.
String feedArt(FeedRow row, WidgetRef ref) {
  final game = row.game;
  if (game != null) {
    final local = localArt(game, ref);
    if (local != null) return local;
  }
  return row.item.coverUrl;
}

/// Age of a release, in the Feed's short form.
String ageText(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min';
  if (d.inHours < 24) return '${d.inHours} hr';
  return '${d.inDays} d';
}

/// The exact moment of a release, in the viewer's time.
String releaseTime(DateTime at) => DateFormat('EEE, MMM d, h:mm a').format(at.toLocal());

String siteName(String source) => switch (source) {
      'f95zone' => 'F95Zone',
      'lewdcorner' => 'LewdCorner',
      'azc' => "Azkosel's Corner",
      _ => source,
    };

/// The Download, Update or Play button for a Feed row.
class FeedPrimaryButton extends ConsumerWidget {
  final FeedRow row;
  final bool small;
  final bool longLabel;
  const FeedPrimaryButton({super.key, required this.row, this.small = true, this.longLabel = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = row.game;
    if (game != null && !row.newer) {
      return VpButton(
        label: longLabel ? 'Play ${fmtVersion(row.installed)}' : 'Play',
        icon: Icons.play_arrow_rounded,
        tone: VpTone.primary,
        small: small,
        onTap: () => playGame(context, ref, game),
      );
    }
    return VpButton(
      label: row.newer ? (longLabel ? 'Update to ${fmtVersion(row.version)}' : 'Update') : 'Download',
      icon: Icons.download_rounded,
      tone: row.newer ? VpTone.update : VpTone.primary,
      small: small,
      onTap: () => showGetSheet(context, ref, title: row.item.title, item: row.item, group: game, version: row.version),
    );
  }
}

/// The chip in a Feed card's top right corner.
Widget? feedRelationChip(FeedRow row, DownloadJob? job) {
  if (job != null) {
    return VpBadge(
      label: job.stage == JobStage.extracting
          ? 'Extracting'
          : job.progress == null
              ? 'Downloading'
              : '${(job.progress! * 100).round()}%',
      mono: true,
      fill: const Color(0xFF4FD1A5),
      color: const Color(0xFF06231B),
    );
  }
  if (row.newer) {
    return _NewVersionChip(label: 'You have ${fmtVersion(row.installed)}');
  }
  if (row.inLibrary) return const VpBadge(label: 'In library');
  if (row.watching) return const VpBadge(label: 'Watching');
  return null;
}

class _NewVersionChip extends StatelessWidget {
  final String label;
  const _NewVersionChip({required this.label});

  @override
  Widget build(BuildContext context) => NewVersionBadge(label: label);
}

class NewVersionBadge extends StatelessWidget {
  final String label;
  const NewVersionBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return VpBadge(label: label, fill: const Color(0xFFFFC857), color: const Color(0xFF2A1B00));
  }
}

/// The active job for a game, by title.
DownloadJob? jobFor(List<DownloadJob> jobs, String title) {
  final key = feedTitleKey(title);
  for (final job in jobs) {
    if (job.active && feedTitleKey(job.title) == key) return job;
  }
  return null;
}
