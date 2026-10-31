import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../providers/feed_view_provider.dart';
import '../providers/filter_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../providers/update_provider.dart';
import '../screens/feed_screen.dart';
import '../services/save_shots.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/common/art.dart';
import '../widgets/common/art_card.dart';
import '../widgets/common/kit.dart';
import '../widgets/game/game_actions.dart';
import '../widgets/get/get_sheet.dart';
import '../widgets/library/library_card.dart';
import '../widgets/modals/settings_modal.dart';

/// Where the app opens: what you were playing, what's new for your games, and
/// what's waiting to be played.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(libraryGroupsProvider);
    final scanning = ref.watch(libraryProvider.select((s) => s.loading));
    final ud = ref.watch(userDataProvider);
    final rows = ref.watch(feedAllRowsProvider);
    final updates = ref.watch(availableUpdatesProvider);
    final games = groups.where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey)).toList();

    if (games.isEmpty) {
      return _Welcome(scanning: scanning, hasFolder: ref.watch(libraryDirProvider).isNotEmpty);
    }

    final recent = games.where((g) => gameLastPlayedAt(g, ud) != null).toList()
      ..sort((a, b) => gameLastPlayedAt(b, ud)!.compareTo(gameLastPlayedAt(a, ud)!));
    final hero = recent.firstOrNull ?? games.first;
    final newVersions = rows.where((r) => r.newer).take(4).toList();
    // F95Zone's version check can find an update the Feed hasn't listed.
    final listed = newVersions.map((r) => r.game?.baseKey).toSet();
    final otherUpdates = games.where((g) => updates.containsKey(g.baseKey) && !listed.contains(g.baseKey)).toList();
    final newOnFeed = rows.where((r) => !r.inLibrary).take(4).toList();
    final ready = games.where((g) {
      final s = effectiveGameStatus(g, ud);
      return s == GameStatus.unplayed || s == GameStatus.updated;
    }).take(4).toList();

    void seeFeed() {
      ref.read(feedFilterProvider.notifier).update((f) => f.copyWith(shelf: FeedShelf.all));
      ref.read(activeTabProvider.notifier).state = AppTab.feed;
    }

    void seeUpdates() {
      ref.read(filterProvider.notifier).setView(updatesOnly: true);
      ref.read(libraryDetailsProvider.notifier).state = false;
      ref.read(activeTabProvider.notifier).state = AppTab.library;
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ContinueHero(group: hero, updateVersion: updates[hero.baseKey]?.version, played: recent.isNotEmpty),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 4, AppLayout.gutter, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recent.length > 1)
                _Shelf(
                  title: 'Pick up where you left off',
                  children: [for (final g in recent.skip(1).take(4)) _SaveSlot(group: g)],
                ),
              if (newVersions.isNotEmpty || otherUpdates.isNotEmpty)
                _Shelf(
                  title: 'New versions for your games',
                  onSeeAll: seeUpdates,
                  children: [
                    for (final r in newVersions) FeedCard(row: r),
                    for (final g in otherUpdates) LibraryCard(group: g),
                  ],
                ),
              if (newOnFeed.isNotEmpty)
                _Shelf(
                  title: 'New on the Feed',
                  onSeeAll: seeFeed,
                  children: [for (final r in newOnFeed) FeedCard(row: r)],
                ),
              if (ready.isNotEmpty)
                _Shelf(
                  title: 'Ready to play',
                  children: [for (final g in ready) LibraryCard(group: g)],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  final bool scanning;
  final bool hasFolder;
  const _Welcome({required this.scanning, required this.hasFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(scanning ? 'Reading your library' : 'Welcome to VN Pathfinder', style: AppText.title()),
          const SizedBox(height: 8),
          Text(
            scanning
                ? 'This takes a moment the first time.'
                : hasFolder
                    ? 'No games in your library folder yet. Add some, or find one on the Feed.'
                    : 'Choose the folder that holds your games to get started.',
            style: AppText.body(color: AppColors.textSecondary),
          ),
          if (!scanning && !hasFolder) ...[
            const SizedBox(height: 16),
            VpButton(label: 'Open Settings', tone: VpTone.primary, onTap: () => showSettingsModal(context)),
          ],
        ],
      ),
    );
  }
}

class _ContinueHero extends ConsumerWidget {
  final GameGroup group;
  final String? updateVersion;
  final bool played;
  const _ContinueHero({required this.group, required this.updateVersion, required this.played});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final ud = ref.watch(userDataProvider);
    final art = localArt(g, ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) setAmbientRest(ref, AppTab.home, art);
    });
    final version = g.latestVersion?.versionStr ?? '';
    final seconds = ud.playtime[g.baseKey] ?? 0;
    final last = gameLastPlayedAt(g, ud);
    final summary = [
      if (seconds > 0) '${fmtTime(seconds)} played',
      if (last != null) 'last played ${fmtDate(last.toIso8601String()).toLowerCase()}',
    ].join(' · ');
    final shot = ref.watch(saveShotProvider(g.baseKey)).valueOrNull;
    final height = Spotlight.heightFor(MediaQuery.sizeOf(context).height);

    return Spotlight(
      art: art,
      epoch: ref.watch(imageEpochProvider),
      height: height,
      eyebrow: played ? 'Continue playing' : 'Start playing',
      title: g.effectiveTitle,
      blurb: g.newestMeta((v) => v.metaSynopsis),
      versionLine: Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (version.isNotEmpty)
            Text(fmtVersion(version),
                style: AppText.mono(fontSize: 13, height: 1, fontWeight: FontWeight.w500, color: AppColors.onArtSoft)),
          if (summary.isNotEmpty) Text(summary, style: AppText.ui(fontSize: 13, height: 1, color: AppColors.onArtMuted)),
        ],
      ),
      actions: [
        VpButton(
          label: version.isEmpty ? 'Play' : 'Play ${fmtVersion(version)}',
          icon: Icons.play_arrow_rounded,
          tone: VpTone.primary,
          onTap: () => playGame(context, ref, g),
        ),
        if (updateVersion != null)
          VpButton(
            label: 'Update to ${fmtVersion(updateVersion!)}',
            icon: Icons.download_rounded,
            tone: VpTone.update,
            onTap: () => showGetSheet(context, ref, title: g.effectiveTitle, group: g, version: updateVersion!),
          ),
        VpButton(label: 'View game', tone: VpTone.glass, onTap: () => openGame(ref, baseKey: g.baseKey)),
      ],
      trailing: shot == null || MediaQuery.sizeOf(context).width < 1100
          ? null
          : Container(
              width: 300,
              decoration: const BoxDecoration(
                color: Color(0x9E080A0F),
                borderRadius: AppRadius.borderLg,
                boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 14))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: GameArt(source: shot.image, decodeWidth: 400)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 8, 11, 10),
                    child: Text('Last save: ${fmtDate(shot.at.toIso8601String()).toLowerCase()}',
                        style: AppText.body(color: AppColors.onArtSoft)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A heading and up to four things in a row.
class _Shelf extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final List<Widget> children;
  const _Shelf({required this.title, required this.children, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.display(fontSize: 23, height: 1.1, color: AppColors.textPrimary))),
              if (onSeeAll != null) VpButton(label: 'See all', tone: VpTone.quiet, small: true, onTap: onSeeAll),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final width = (constraints.maxWidth - 18 * 3) / 4;
            return SizedBox(
              height: ArtCard.heightFor(width),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 18),
                    SizedBox(width: width, child: i < children.length ? children[i] : null),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// A game you were playing, shown by its last save.
class _SaveSlot extends ConsumerWidget {
  final GameGroup group;
  const _SaveSlot({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final shot = ref.watch(saveShotProvider(g.baseKey)).valueOrNull;
    final ud = ref.watch(userDataProvider);
    final art = localArt(g, ref);
    final last = gameLastPlayedAt(g, ud);
    return ArtCard(
      art: shot?.image ?? art,
      title: g.effectiveTitle,
      subtitle: last == null ? '' : 'Last played ${fmtDate(last.toIso8601String()).toLowerCase()}',
      onOpen: () => openGame(ref, baseKey: g.baseKey),
      onHover: (on) => setAmbientHover(ref, on ? art : null),
      actions: [
        VpButton(
          label: 'Play',
          icon: Icons.play_arrow_rounded,
          tone: VpTone.primary,
          small: true,
          onTap: () => playGame(context, ref, g),
        ),
      ],
    );
  }
}
