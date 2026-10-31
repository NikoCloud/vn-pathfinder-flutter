import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/user_data.dart';
import '../providers/filter_provider.dart';
import '../providers/library_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../providers/update_provider.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/common/art.dart';
import '../widgets/common/art_card.dart';
import '../widgets/common/drag_handle.dart';
import '../widgets/common/kit.dart';
import '../widgets/common/shell_focus.dart';
import '../widgets/common/status_menu.dart';
import '../widgets/game/game_actions.dart';
import '../widgets/game/game_page.dart';
import '../widgets/library/game_context_menu.dart';
import '../widgets/library/library_card.dart';
import '../widgets/modals/add_game_modal.dart';
import '../widgets/modals/metadata_fetch_modal.dart';
import '../widgets/modals/settings_modal.dart';
import '../widgets/sidebar/filter_panel.dart';

/// The Library's quick views, each one filter away.
enum LibraryView {
  all('All', null),
  playing('Playing', GameStatus.playing),
  newVersion('New version', null),
  updated('Updated', GameStatus.updated),
  unplayed('Unplayed', GameStatus.unplayed),
  onHold('On Hold', GameStatus.onHold),
  completed('Completed', GameStatus.completed);

  const LibraryView(this.label, this.status);
  final String label;
  final GameStatus? status;
}

LibraryView? activeView(FilterState f) {
  if (f.updatesOnly) return f.statuses.containsAll(allStatusIds) ? LibraryView.newVersion : null;
  if (f.statuses.containsAll(allStatusIds)) return LibraryView.all;
  if (f.statuses.length == 1) {
    for (final view in LibraryView.values) {
      if (view.status?.id == f.statuses.single) return view;
    }
  }
  return null;
}

const _sortLabels = {
  SortMode.recentlyPlayed: 'Recently played',
  SortMode.alpha: 'Title',
  SortMode.developer: 'Developer',
  SortMode.rating: 'Rating',
  SortMode.playTime: 'Play time',
  SortMode.dateAdded: 'Date added',
};

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _panelOpen = false;
  bool _selecting = false;
  final _picked = <String>{};

  void _togglePick(String baseKey) => setState(() => _picked.contains(baseKey) ? _picked.remove(baseKey) : _picked.add(baseKey));

  void _stopSelecting() => setState(() {
        _selecting = false;
        _picked.clear();
      });

  List<GameGroup> _pickedGroups() =>
      ref.read(libraryProvider).groups.where((g) => _picked.contains(g.baseKey)).toList();

  Future<void> _bulkStatus(BuildContext anchor) async {
    final choice = await showVpMenuBelow<String>(anchor, [
      const VpMenuItem('', 'Auto', icon: Icons.auto_awesome_outlined),
      const VpMenuItem.divider(),
      for (final s in GameStatus.manual) VpMenuItem(s.id, s.label, icon: statusIcon(s), iconColor: statusColor(s)),
    ]);
    if (choice == null) return;
    final notifier = ref.read(userDataProvider.notifier);
    for (final key in _picked) {
      notifier.setStatus(key, choice);
    }
    ref.read(notificationProvider.notifier).success('Status set for ${_picked.length} game${_picked.length == 1 ? '' : 's'}');
  }

  void _bulkHide() {
    final notifier = ref.read(userDataProvider.notifier);
    for (final key in _picked) {
      notifier.setHidden(key, true);
    }
    ref.read(notificationProvider.notifier).info('${_picked.length} game${_picked.length == 1 ? '' : 's'} hidden');
    _stopSelecting();
  }

  /// One Fetch Metadata window for each game, in turn.
  Future<void> _bulkFetch() async {
    for (final group in _pickedGroups()) {
      if (!mounted) return;
      await showMetadataFetchModal(context, group);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(libraryDetailsProvider);
    final loading = ref.watch(libraryProvider.select((s) => s.loading));
    final error = ref.watch(libraryProvider.select((s) => s.error));
    final groups = ref.watch(filteredGroupsProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              panelOpen: _panelOpen,
              selecting: _selecting,
              onPanel: () => setState(() => _panelOpen = !_panelOpen),
              onSelect: () => _selecting ? _stopSelecting() : setState(() => _selecting = true),
            ),
            Expanded(
              child: error != null && groups.isEmpty
                  ? _Message(error)
                  : details
                      ? _Details(groups: groups)
                      : _Wall(
                          groups: groups,
                          loading: loading,
                          picking: _selecting,
                          picked: _picked,
                          rightPad: _panelOpen && MediaQuery.sizeOf(context).width > 900 ? 348 : AppLayout.gutter,
                          onPick: _togglePick,
                        ),
            ),
          ],
        ),
        if (_panelOpen)
          Positioned(
            right: 0,
            top: 52,
            bottom: 0,
            width: 320,
            child: _FilterDrawer(onClose: () => setState(() => _panelOpen = false)),
          ),
        if (_selecting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: _BulkBar(
                count: _picked.length,
                onFetch: _bulkFetch,
                onStatus: _bulkStatus,
                onHide: _bulkHide,
                onDone: _stopSelecting,
              ),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: AppText.body(color: AppColors.textMuted)));
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends ConsumerWidget {
  final bool panelOpen;
  final bool selecting;
  final VoidCallback onPanel;
  final VoidCallback onSelect;

  const _Toolbar({required this.panelOpen, required this.selecting, required this.onPanel, required this.onSelect});

  int _count(LibraryView view, List<GameGroup> games, UserData ud, Map updates) => switch (view) {
        LibraryView.all => games.length,
        LibraryView.newVersion => games.where((g) => updates.containsKey(g.baseKey)).length,
        _ => games.where((g) => effectiveGameStatus(g, ud) == view.status).length,
      };

  Future<void> _saveView(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    void done(BuildContext ctx) {
      final name = controller.text.trim();
      Navigator.of(ctx).pop();
      if (name.isEmpty) return;
      ref.read(settingsProvider.notifier).saveView(name, ref.read(filterProvider).toJson());
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save this view', style: AppText.heading()),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: AppText.body(),
            decoration: const InputDecoration(hintText: 'Name'),
            onSubmitted: (_) => done(ctx),
          ),
        ),
        actions: [
          VpButton(label: 'Cancel', tone: VpTone.quiet, small: true, onTap: () => Navigator.of(ctx).pop()),
          VpButton(label: 'Save', tone: VpTone.primary, small: true, onTap: () => done(ctx)),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final ud = ref.watch(userDataProvider);
    final updates = ref.watch(availableUpdatesProvider);
    final games = ref
        .watch(libraryGroupsProvider)
        .where((g) => g.versions.isNotEmpty && (filter.showHidden || !ud.hidden.contains(g.baseKey)))
        .toList();
    final saved = ref.watch(settingsProvider.select((s) => s.savedViews));
    final current = activeView(filter);
    final details = ref.watch(libraryDetailsProvider);

    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 9, AppLayout.gutter, 9),
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
                  for (final view in LibraryView.values) ...[
                    VpShelf(
                      label: view.label,
                      count: _count(view, games, ud, updates),
                      selected: current == view,
                      onTap: () => view == LibraryView.newVersion
                          ? notifier.setView(updatesOnly: true)
                          : notifier.setView(statuses: view.status == null ? allStatusIds : {view.status!.id}),
                    ),
                    const SizedBox(width: 2),
                  ],
                  for (final name in saved.keys) ...[
                    Tooltip(
                      message: 'Right-click to delete',
                      child: GestureDetector(
                        onSecondaryTap: () => ref.read(settingsProvider.notifier).deleteView(name),
                        child: VpShelf(
                          label: name,
                          selected: false,
                          onTap: () => notifier.load(FilterState.fromJson(saved[name]!)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  VpButton(label: '+ Save view', tone: VpTone.quiet, small: true, onTap: () => _saveView(context, ref)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          VpField(
            hint: 'Search your library',
            icon: Icons.search,
            width: MediaQuery.sizeOf(context).width < 1200 ? 150 : 190,
            onChanged: notifier.setQuery,
          ),
          const SizedBox(width: 6),
          VpTool(label: 'Filters', icon: Icons.tune, on: panelOpen, count: filter.activeFilters, onTap: onPanel),
          const SizedBox(width: 6),
          Builder(
            builder: (context) => VpTool(
              label: _sortLabels[filter.sort]!,
              icon: Icons.swap_vert,
              onTap: () async {
                final choice = await showVpMenuBelow<SortMode>(context, [
                  for (final e in _sortLabels.entries) VpMenuItem(e.key, e.value, checked: e.key == filter.sort),
                ]);
                if (choice != null) notifier.setSort(choice);
              },
            ),
          ),
          const SizedBox(width: 6),
          if (!details) ...[
            VpTool(label: 'Select', on: selecting, onTap: onSelect),
            const SizedBox(width: 6),
          ],
          VpSegmented<bool>(
            value: details,
            options: const [
              (false, Icons.grid_view_rounded, 'Cards'),
              (true, Icons.vertical_split_outlined, 'Details'),
            ],
            onChanged: (v) => ref.read(libraryDetailsProvider.notifier).state = v,
          ),
          const SizedBox(width: 6),
          VpIconButton(icon: Icons.add, tooltip: 'Add a game', size: 32, onTap: () => showAddGameModal(context)),
          VpIconButton(
            icon: Icons.refresh,
            tooltip: 'Rescan the library',
            size: 32,
            onTap: () => ref.read(libraryProvider.notifier).scan(),
          ),
        ],
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

class _Wall extends ConsumerWidget {
  final List<GameGroup> groups;
  final bool loading;
  final bool picking;
  final Set<String> picked;
  final double rightPad;
  final ValueChanged<String> onPick;

  const _Wall({
    required this.groups,
    required this.loading,
    required this.picking,
    required this.picked,
    required this.rightPad,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasFolder = ref.watch(libraryDirProvider).isNotEmpty;
    final minWidth = ref.watch(settingsProvider.select((s) => s.cardWidth));
    if (groups.isEmpty) {
      if (loading) return const _Message('Reading your library');
      if (hasFolder) return const _Message('No games match these filters.');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Choose the folder that holds your games.', style: AppText.body(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            VpButton(label: 'Open Settings', tone: VpTone.primary, onTap: () => showSettingsModal(context)),
          ],
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final wall = wallColumns(constraints.maxWidth - AppLayout.gutter - rightPad, minWidth);
      return GridView.builder(
        key: const PageStorageKey('library-wall'),
        padding: EdgeInsets.fromLTRB(AppLayout.gutter, 16, rightPad, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wall.columns,
          crossAxisSpacing: 18,
          mainAxisSpacing: 20,
          mainAxisExtent: ArtCard.heightFor(wall.cardWidth),
        ),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          return LibraryCard(
            key: ValueKey(g.baseKey),
            group: g,
            picking: picking,
            picked: picked.contains(g.baseKey),
            onOpen: picking ? () => onPick(g.baseKey) : null,
          );
        },
      );
    });
  }
}

class _BulkBar extends StatelessWidget {
  final int count;
  final VoidCallback onFetch;
  final ValueChanged<BuildContext> onStatus;
  final VoidCallback onHide;
  final VoidCallback onDone;

  const _BulkBar({
    required this.count,
    required this.onFetch,
    required this.onStatus,
    required this.onHide,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final none = count == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 8, 9, 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.96),
        border: Border.all(color: AppColors.border),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 36, offset: Offset(0, 14))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count selected', style: AppText.body(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          VpButton(label: 'Fetch metadata', small: true, onTap: none ? null : onFetch),
          const SizedBox(width: 8),
          Builder(
            builder: (context) => VpButton(label: 'Set status', small: true, onTap: none ? null : () => onStatus(context)),
          ),
          const SizedBox(width: 8),
          VpButton(label: 'Hide', small: true, onTap: none ? null : onHide),
          const SizedBox(width: 8),
          VpButton(label: 'Done', small: true, tone: VpTone.quiet, onTap: onDone),
        ],
      ),
    );
  }
}

class _FilterDrawer extends ConsumerWidget {
  final VoidCallback onClose;
  const _FilterDrawer({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardWidth = ref.watch(settingsProvider.select((s) => s.cardWidth));
    final count = ref.watch(filteredGroupsProvider).length;
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
                const FilterPanel(),
                const SizedBox(height: 18),
                Text('Card size', style: AppText.body(fontWeight: FontWeight.w600)),
                Slider(
                  value: cardWidth.clamp(210, 360),
                  min: 210,
                  max: 360,
                  divisions: 15,
                  activeColor: AppColors.accent,
                  label: 'Card size',
                  onChanged: ref.read(settingsProvider.notifier).setCardWidth,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                VpButton(
                  label: 'Clear all',
                  tone: VpTone.quiet,
                  small: true,
                  onTap: () => ref.read(filterProvider.notifier).clearFilters(),
                ),
                const Spacer(),
                Text('$count game${count == 1 ? '' : 's'}', style: AppText.meta(color: AppColors.textMuted)),
                const SizedBox(width: 10),
                VpButton(label: 'Done', small: true, onTap: onClose),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Details ───────────────────────────────────────────────────────────────────

/// The list beside the game page. The separator can be dragged, and the width
/// is saved when the drag ends.
class _Details extends ConsumerStatefulWidget {
  final List<GameGroup> groups;
  const _Details({required this.groups});

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  static const _minList = 220.0;
  static const _minPage = 460.0;
  static const _rowHeight = 56.0;

  /// The width during a drag; settings hold it otherwise.
  double? _dragging;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the selected game on screen when the keyboard moves the selection.
  void _reveal(String? baseKey) {
    if (!_scroll.hasClients) return;
    final index = widget.groups.indexWhere((g) => g.baseKey == baseKey);
    if (index < 0) return;
    final top = index * _rowHeight;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + _rowHeight - position.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(libraryProvider.select((s) => s.selectedBaseKey), (_, key) => _reveal(key));
    final saved = ref.watch(settingsProvider.select((s) => s.sidebarWidth));
    final selectedKey = ref.watch(libraryProvider.select((s) => s.selectedBaseKey));
    final epoch = ref.watch(imageEpochProvider);
    final groups = widget.groups;
    final selected = groups.where((g) => g.baseKey == selectedKey).firstOrNull ?? groups.firstOrNull;

    return LayoutBuilder(builder: (context, constraints) {
      final max = (constraints.maxWidth - _minPage).clamp(_minList, double.infinity);
      final width = (_dragging ?? saved).clamp(_minList, max);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: width,
            child: ColoredBox(
              color: AppColors.bgSecondary.withValues(alpha: 0.62),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(6),
                itemExtent: _rowHeight,
                itemCount: groups.length,
                itemBuilder: (context, i) => _DetailRow(
                  group: groups[i],
                  selected: groups[i].baseKey == selected?.baseKey,
                ),
              ),
            ),
          ),
          DragHandle(
            axis: Axis.horizontal,
            onDrag: (dx) => setState(() => _dragging = (width + dx).clamp(_minList, max)),
            onDragEnd: () {
              final end = _dragging;
              if (end != null) ref.read(settingsProvider.notifier).setSidebarWidth(end);
              setState(() => _dragging = null);
            },
            onReset: () => ref.read(settingsProvider.notifier).setSidebarWidth(AppLayout.sidebarWidth),
          ),
          Expanded(
            child: selected == null
                ? const _Message('No games match these filters.')
                // Keyed on the image epoch so freshly fetched art replaces the
                // cached images after Fetch Metadata.
                : GameView(key: ValueKey('${selected.baseKey}@$epoch'), group: selected),
          ),
        ],
      );
    });
  }
}

class _DetailRow extends ConsumerWidget {
  final GameGroup group;
  final bool selected;
  const _DetailRow({required this.group, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final ud = ref.watch(userDataProvider);
    final status = effectiveGameStatus(g, ud);
    final update = ref.watch(availableUpdatesProvider).containsKey(g.baseKey);
    final version = g.latestVersion?.versionStr ?? '';
    return Pressable(
      onTap: () {
        ref.read(libraryProvider.notifier).select(g.baseKey);
        shellFocus.requestFocus();
      },
      label: g.effectiveTitle,
      selected: selected,
      onSecondaryTapDown: (d) => showGameContextMenu(
        context: context,
        ref: ref,
        globalPosition: d.globalPosition,
        group: g,
      ),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.bgActive
              : states.contains(WidgetState.hovered)
                  ? AppColors.bgHover
                  : Colors.transparent,
          borderRadius: AppRadius.borderMd,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 40,
              child: ClipRRect(
                borderRadius: AppRadius.borderXs,
                child: GameArt(source: localArt(g, ref), decodeWidth: 96, epoch: ref.watch(imageEpochProvider)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(g.effectiveTitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(fontWeight: FontWeight.w500)),
                  Text(
                    [g.effectiveDeveloper, if (version.isNotEmpty) fmtVersion(version)].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (update) ...[
              Icon(Icons.arrow_circle_up_rounded, size: 15, color: AppColors.newVersion),
              const SizedBox(width: 5),
            ],
            Tooltip(message: status.label, child: Icon(statusIcon(status), size: 15, color: statusColor(status))),
          ],
        ),
      ),
    );
  }
}
