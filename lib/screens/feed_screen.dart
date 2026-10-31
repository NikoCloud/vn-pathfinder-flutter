import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed_item.dart';
import '../providers/downloads_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/feed_view_provider.dart';
import '../providers/library_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/common/art.dart';
import '../widgets/common/art_card.dart';
import '../widgets/common/kit.dart';
import '../widgets/game/game_actions.dart';
import '../widgets/modals/settings_modal.dart';

/// Discovery, versions and getting games, in one place: a Spotlight, then every
/// release in time order. Every site gets the same card and the same place in
/// the order, so no site gets a better deal than another.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _panelOpen = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (!settings.feedEnabled) return const _FeedOff();

    final feed = ref.watch(feedProvider);
    final all = ref.watch(feedAllRowsProvider);
    final rows = ref.watch(feedRowsProvider);
    final filter = ref.watch(feedFilterProvider);
    final spotlight = pickSpotlight(all);
    final size = MediaQuery.sizeOf(context);
    final pad = _panelOpen && size.width > 900 ? 348.0 : AppLayout.gutter;
    final days = groupByDay(rows);

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            if (spotlight.isNotEmpty)
              SliverToBoxAdapter(
                child: _FeedSpotlight(rows: spotlight, height: Spotlight.heightFor(size.height)),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ShelvesHeader(
                child: _Shelves(
                  all: all,
                  filter: filter,
                  rightPad: pad,
                  panelOpen: _panelOpen,
                  onPanel: () => setState(() => _panelOpen = !_panelOpen),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(AppLayout.gutter, 6, pad, 0),
              sliver: SliverToBoxAdapter(child: _Notices(feed: feed, locked: settings.lockdown)),
            ),
            if (days.isEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(AppLayout.gutter, 0, pad, 110),
                sliver: SliverToBoxAdapter(child: _Empty(loading: feed.isLoading, filter: filter)),
              )
            else
              for (final (index, day) in days.indexed) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppLayout.gutter, 0, pad, 0),
                  sliver: SliverToBoxAdapter(child: _DayHead(label: day.$1, count: day.$2.length, first: index == 0)),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppLayout.gutter, 0, pad, index == days.length - 1 ? 110 : 0),
                  sliver: filter.list
                      ? SliverList.builder(
                          itemCount: day.$2.length,
                          itemBuilder: (context, i) => _FeedListRow(row: day.$2[i]),
                        )
                      : SliverLayoutBuilder(builder: (context, c) {
                          final wall = wallColumns(c.crossAxisExtent, 272);
                          return SliverGrid.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: wall.columns,
                              crossAxisSpacing: 18,
                              mainAxisSpacing: 20,
                              mainAxisExtent: ArtCard.heightFor(wall.cardWidth),
                            ),
                            itemCount: day.$2.length,
                            itemBuilder: (context, i) => FeedCard(row: day.$2[i]),
                          );
                        }),
                ),
              ],
          ],
        ),
        if (_panelOpen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 320,
            child: _FilterPanel(onClose: () => setState(() => _panelOpen = false)),
          ),
      ],
    );
  }
}

/// Rows under Today, Yesterday, Earlier this week and Older.
List<(String, List<FeedRow>)> groupByDay(List<FeedRow> rows, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final groups = <String, List<FeedRow>>{};
  for (final row in rows) {
    final at = row.item.publishedAt?.toLocal();
    final days = at == null ? 99 : today.difference(DateTime(at.year, at.month, at.day)).inDays;
    final label = days <= 0
        ? 'Today'
        : days == 1
            ? 'Yesterday'
            : days < 7
                ? 'Earlier this week'
                : 'Older';
    groups.putIfAbsent(label, () => []).add(row);
  }
  return [
    for (final label in const ['Today', 'Yesterday', 'Earlier this week', 'Older'])
      if (groups[label] != null) (label, groups[label]!),
  ];
}

// ── Spotlight ─────────────────────────────────────────────────────────────────

class _FeedSpotlight extends ConsumerStatefulWidget {
  final List<FeedRow> rows;
  final double height;
  const _FeedSpotlight({required this.rows, required this.height});

  @override
  ConsumerState<_FeedSpotlight> createState() => _FeedSpotlightState();
}

class _FeedSpotlightState extends ConsumerState<_FeedSpotlight> {
  int _index = 0;
  bool _hold = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final showing = ref.read(activeTabProvider) == AppTab.feed && ref.read(gamePageProvider) == null;
      if (_hold || still || !showing || widget.rows.length < 2) return;
      setState(() => _index = (_index + 1) % widget.rows.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final row = rows[_index % rows.length];
    final item = row.item;
    final art = feedArt(row, ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setAmbientRest(ref, AppTab.feed, art);
    });

    final age = ageText(item.publishedAt);
    final meta = [siteName(item.source), if (age.isNotEmpty) '$age ago'].join(' · ');
    return MouseRegion(
      onEnter: (_) => _hold = true,
      onExit: (_) => _hold = false,
      child: Spotlight(
        art: art,
        height: widget.height,
        eyebrow: row.newer
            ? 'New version for your game'
            : item.kind == FeedKind.newGame
                ? 'New game'
                : 'Just updated',
        eyebrowNew: row.newer,
        title: row.game?.effectiveTitle ?? item.title,
        blurb: row.game?.newestMeta((v) => v.metaSynopsis) ?? item.overview,
        versionLine: _VersionLine(row: row, meta: meta),
        actions: [
          FeedPrimaryButton(row: row, small: false),
          VpButton(
            label: 'View game',
            tone: VpTone.glass,
            onTap: () => openGame(ref, baseKey: row.game?.baseKey, item: item),
          ),
        ],
        trailing: rows.length < 2
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, r) in rows.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _RailThumb(
                      art: feedArt(r, ref),
                      title: r.item.title,
                      on: i == _index % rows.length,
                      onTap: () => setState(() => _index = i),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  final FeedRow row;
  final String meta;
  const _VersionLine({required this.row, required this.meta});

  @override
  Widget build(BuildContext context) {
    final mono = AppText.mono(fontSize: 13, height: 1, fontWeight: FontWeight.w500, color: AppColors.onArtSoft);
    final version = row.version.isEmpty ? '' : fmtVersion(row.version);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        if (row.newer) ...[
          Text(fmtVersion(row.installed), style: mono),
          Text('→', style: mono),
        ],
        if (version.isNotEmpty) Text(version, style: mono.copyWith(color: AppColors.newVersion)),
        Text(meta, style: AppText.ui(fontSize: 13, height: 1, color: AppColors.onArtMuted)),
      ],
    );
  }
}

class _RailThumb extends StatelessWidget {
  final String art;
  final String title;
  final bool on;
  final VoidCallback onTap;
  const _RailThumb({required this.art, required this.title, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: title,
      selected: on,
      radius: const BorderRadius.all(Radius.circular(6)),
      builder: (context, states) => AnimatedOpacity(
        duration: AppMotion.of(context, AppMotion.select),
        opacity: on || states.contains(WidgetState.hovered) ? 1 : 0.72,
        child: Container(
          width: 118,
          height: 66,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GameArt(source: art, decodeWidth: 160),
              if (on) Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 3, color: AppColors.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shelves ───────────────────────────────────────────────────────────────────

class _ShelvesHeader extends SliverPersistentHeaderDelegate {
  static const height = 52.0;

  final Widget child;
  _ShelvesHeader({required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_ShelvesHeader old) => true;
}

class _Shelves extends ConsumerWidget {
  final List<FeedRow> all;
  final FeedFilter filter;
  final double rightPad;
  final bool panelOpen;
  final VoidCallback onPanel;

  const _Shelves({
    required this.all,
    required this.filter,
    required this.rightPad,
    required this.panelOpen,
    required this.onPanel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = all.where((r) => matchesFeedFilter(r, filter)).toList();
    void set(FeedFilter Function(FeedFilter) change) => ref.read(feedFilterProvider.notifier).update(change);

    return Container(
      height: _ShelvesHeader.height,
      padding: EdgeInsets.fromLTRB(AppLayout.gutter, 9, rightPad, 9),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary.withValues(alpha: 0.92),
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final shelf in FeedShelf.values) ...[
                    if (shelf == FeedShelf.myGames)
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: AppColors.border,
                      ),
                    VpShelf(
                      label: shelf.label,
                      count: shelfRows(base, shelf).length,
                      selected: filter.shelf == shelf,
                      onTap: () => set((f) => f.copyWith(shelf: shelf)),
                    ),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          VpField(
            hint: 'Search the Feed',
            icon: Icons.search,
            width: MediaQuery.sizeOf(context).width < 1100 ? 150 : 220,
            onChanged: (v) => set((f) => f.copyWith(query: v)),
          ),
          const SizedBox(width: 6),
          VpTool(label: 'Filters', icon: Icons.tune, on: panelOpen, count: filter.active, onTap: onPanel),
          const SizedBox(width: 6),
          VpSegmented<bool>(
            value: filter.list,
            options: const [
              (false, Icons.grid_view_rounded, 'Cards'),
              (true, Icons.view_list_rounded, 'List'),
            ],
            onChanged: (v) => set((f) => f.copyWith(list: v)),
          ),
        ],
      ),
    );
  }
}

// ── Wall ──────────────────────────────────────────────────────────────────────

/// What the Feed couldn't do, said plainly above the list.
class _Notices extends StatelessWidget {
  final FeedState feed;
  final bool locked;
  const _Notices({required this.feed, required this.locked});

  @override
  Widget build(BuildContext context) {
    final saved = feed.lastRefreshed == null ? 'the saved list' : 'the list saved ${_ago(feed.lastRefreshed!)}';
    final lines = <(IconData, String)>[
      if (locked) (Icons.lock_outline, 'Lockdown is on, so this is $saved. Downloads and Refresh need you to go online.'),
      if (feed.error != null) (Icons.error_outline, "The Feed couldn't refresh, so this is $saved."),
      for (final e in feed.problems.entries)
        (
          Icons.info_outline,
          switch (e.value) {
            'public' => "${siteName(e.key)}'s full list didn't answer. Refresh in a while, or check your login under Settings, Network.",
            'behind' => "${siteName(e.key)} stopped answering partway back. The next refresh picks up from there.",
            'threads' => "Some of ${siteName(e.key)}'s threads wouldn't open, so their cards wait for the next refresh.",
            _ => "${siteName(e.key)} couldn't be reached. Its earlier releases are still here.",
          },
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (icon, text) in lines)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.bgCard.withValues(alpha: 0.85),
                border: Border.all(color: AppColors.border),
                borderRadius: AppRadius.borderMd,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 9),
                  Expanded(child: Text(text, style: AppText.body(color: AppColors.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return '${d.inDays} d ago';
}

class _DayHead extends ConsumerWidget {
  final String label;
  final int count;
  final bool first;
  const _DayHead({required this.label, required this.count, required this.first});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final locked = ref.watch(lockdownProvider);
    final last = feed.lastRefreshed;
    final when = last == null ? 'Never updated' : '${locked ? 'Saved' : 'Updated'} ${_ago(last)}';
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Row(
        children: [
          Text(label, style: AppText.display(fontSize: 23, height: 1.1, color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Text('$count release${count == 1 ? '' : 's'}', style: AppText.body(color: AppColors.textMuted)),
          const Spacer(),
          if (first) ...[
            VpButton(
              label: 'Mark all seen',
              tone: VpTone.quiet,
              small: true,
              onTap: () {
                ref.read(settingsProvider.notifier).markFeedSeen();
                ref.read(notificationProvider.notifier).info('Everything is marked as seen');
              },
            ),
            Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 6), color: AppColors.border),
            Text(when, style: AppText.body(color: AppColors.textMuted)),
            const SizedBox(width: 4),
            VpButton(
              label: feed.isLoading ? 'Refreshing' : 'Refresh',
              tone: VpTone.quiet,
              small: true,
              busy: feed.isLoading,
              tooltip: locked ? 'Refresh needs you to go online' : null,
              onTap: locked ? null : () => ref.read(feedProvider.notifier).refresh(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool loading;
  final FeedFilter filter;
  const _Empty({required this.loading, required this.filter});

  @override
  Widget build(BuildContext context) {
    final watching = filter.shelf == FeedShelf.watching;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loading ? 'Getting the latest releases' : 'Nothing here yet',
              style: AppText.display(fontSize: 23, height: 1.1, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'This takes a few seconds the first time.'
                : watching
                    ? 'Point at a game and press the eye to watch it. New versions will show up here.'
                    : 'No releases match these filters.',
            style: AppText.body(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FeedOff extends ConsumerWidget {
  const _FeedOff();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('The Feed is off', style: AppText.title()),
          const SizedBox(height: 8),
          Text('It shows new releases and updates for your games from the sites you choose.',
              style: AppText.body(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          VpButton(
            label: 'Turn on the Feed',
            tone: VpTone.primary,
            onTap: () => ref.read(settingsProvider.notifier).setFeedEnabled(true),
          ),
          const SizedBox(height: 8),
          VpButton(label: 'Open Settings', tone: VpTone.quiet, onTap: () => showSettingsModal(context)),
        ],
      ),
    );
  }
}

const _kindLabels = {
  FeedKind.newGame: 'New game',
  FeedKind.update: 'Update',
  FeedKind.complete: 'Complete',
};

/// A release as a card.
class FeedCard extends ConsumerWidget {
  final FeedRow row;
  const FeedCard({super.key, required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = row.item;
    final titleKey = feedTitleKey(item.title);
    final job = jobFor(ref.watch(downloadsProvider), item.title);
    final art = feedArt(row, ref);
    final at = item.publishedAt;

    final kind = item.kind == FeedKind.newGame
        ? VpBadge(label: 'New game', fill: AppColors.accent, color: AppColors.onAccent)
        : item.kind == FeedKind.complete
            ? const VpBadge(label: 'Complete', fill: Color(0xEBE6EBF2), color: Color(0xFF141821))
            : const VpBadge(label: 'Update');

    return ArtCard(
      art: art,
      title: row.game?.effectiveTitle ?? item.title,
      subtitle: [item.developer, siteName(item.source)].where((s) => s.isNotEmpty).join(' · '),
      time: at == null ? null : '${ageText(at)} ago',
      timeTooltip: at == null ? null : releaseTime(at),
      dot: row.fresh,
      topLeft: kind,
      topRight: feedRelationChip(row, job),
      version: row.version.isEmpty ? null : fmtVersion(row.version),
      peekText: item.tags.isEmpty ? 'Open for details' : item.tags.take(4).join(', '),
      semanticLabel: '${item.title}${row.version.isEmpty ? '' : ', ${fmtVersion(row.version)}'}',
      onOpen: () => openGame(ref, baseKey: row.game?.baseKey, item: item),
      onHover: (on) => setAmbientHover(ref, on ? art : null),
      actions: [
        if (job == null) FeedPrimaryButton(row: row) else const SizedBox.shrink(),
        if (!row.inLibrary)
          VpIconButton(
            icon: Icons.visibility_outlined,
            tooltip: row.watching ? 'Stop watching' : 'Watch this game',
            onArt: true,
            selected: row.watching,
            onTap: () => toggleWatch(ref, item),
          ),
        VpIconButton(
          icon: Icons.notifications_off_outlined,
          tooltip: 'Mute this game',
          onArt: true,
          onTap: () {
            ref.read(userDataProvider.notifier).setMuted(titleKey, true);
            ref.read(notificationProvider.notifier).info('${item.title} is muted');
          },
        ),
      ],
    );
  }
}

/// A release as a line.
class _FeedListRow extends ConsumerWidget {
  final FeedRow row;
  const _FeedListRow({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = row.item;
    final art = feedArt(row, ref);
    final note = [
      _kindLabels[item.kind]!,
      if (row.newer) 'you have ${fmtVersion(row.installed)}' else if (row.inLibrary) 'in library',
    ].join(' · ');
    return MouseRegion(
      onEnter: (_) => setAmbientHover(ref, art),
      onExit: (_) => setAmbientHover(ref, null),
      child: Pressable(
        onTap: () => openGame(ref, baseKey: row.game?.baseKey, item: item),
        label: item.title,
        radius: const BorderRadius.all(Radius.circular(8)),
        builder: (context, states) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered) ? AppColors.bgHover : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: 63,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(5)),
                  child: GameArt(source: art, decodeWidth: 160),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.game?.effectiveTitle ?? item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display(fontSize: 16, height: 1.2, color: AppColors.textPrimary)),
                    Text(note, style: AppText.meta(color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 92,
                child: Text(row.version.isEmpty ? '' : fmtVersion(row.version),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.data(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Text(item.developer,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 130,
                child: Text(siteName(item.source),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(color: AppColors.textSecondary)),
              ),
              SizedBox(
                width: 54,
                child: Tooltip(
                  message: item.publishedAt == null ? '' : releaseTime(item.publishedAt!),
                  child: Text(ageText(item.publishedAt),
                      textAlign: TextAlign.right, style: AppText.body(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(width: 130, child: Align(alignment: Alignment.centerRight, child: FeedPrimaryButton(row: row))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filters ───────────────────────────────────────────────────────────────────

class _FilterPanel extends ConsumerWidget {
  final VoidCallback onClose;
  const _FilterPanel({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(feedFilterProvider);
    final settings = ref.watch(settingsProvider);
    final feed = ref.watch(feedProvider);
    final muted = ref.watch(userDataProvider.select((u) => u.muted));
    void set(FeedFilter Function(FeedFilter) change) => ref.read(feedFilterProvider.notifier).update(change);

    final counts = <String, int>{};
    for (final item in feed.items) {
      for (final tag in item.tags) {
        final key = tag.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final tags = (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!))).take(40).toList()..sort();
    final sites = [
      if (settings.feedSourceF95) 'f95zone',
      if (settings.feedSourceLC) 'lewdcorner',
      if (settings.feedSourceAzc) 'azc',
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.96),
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text('Sites', style: AppText.body(fontWeight: FontWeight.w600)),
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final site in sites)
                    VpChip(
                      label: siteName(site),
                      selected: !filter.hiddenSites.contains(site),
                      onTap: () => set((f) => f.copyWith(
                            hiddenSites: f.hiddenSites.contains(site)
                                ? f.hiddenSites.difference({site})
                                : {...f.hiddenSites, site},
                          )),
                    ),
                ]),
                const SizedBox(height: 18),
                Text('Tags: click to include, again to exclude', style: AppText.body(fontWeight: FontWeight.w600)),
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final tag in tags)
                    VpChip(
                      label: tag,
                      selected: filter.wanted.contains(tag),
                      excluded: filter.unwanted.contains(tag),
                      onTap: () => set((f) {
                        if (f.wanted.contains(tag)) {
                          return f.copyWith(wanted: f.wanted.difference({tag}), unwanted: {...f.unwanted, tag});
                        }
                        if (f.unwanted.contains(tag)) return f.copyWith(unwanted: f.unwanted.difference({tag}));
                        return f.copyWith(wanted: {...f.wanted, tag});
                      }),
                    ),
                ]),
                const SizedBox(height: 18),
                Text('Games without tags stay visible, because not every site lists them in its feed.',
                    style: AppText.meta(color: AppColors.textMuted)),
                if (muted.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: VpButton(
                      label: 'Show ${muted.length} muted game${muted.length == 1 ? '' : 's'}',
                      small: true,
                      onTap: () => ref.read(userDataProvider.notifier).update((u) => u.copyWith(muted: const {})),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                VpButton(
                  label: filter.active > 0 ? 'Clear all (${filter.active})' : 'Clear all',
                  tone: VpTone.quiet,
                  small: true,
                  onTap: () => set((f) => FeedFilter(shelf: f.shelf, query: f.query, list: f.list)),
                ),
                const Spacer(),
                VpButton(label: 'Done', small: true, onTap: onClose),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
