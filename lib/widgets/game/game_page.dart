import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/feed_item.dart';
import '../../models/game_group.dart';
import '../../models/game_status.dart';
import '../../models/version_path.dart';
import '../../providers/feed_images_provider.dart';
import '../../providers/feed_view_provider.dart';
import '../../providers/filter_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/play_tracker_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shell_provider.dart';
import '../../providers/thread_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/scanner_service.dart';
import '../../services/thread_parser.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../utils/preset_tags.dart';
import '../common/art.dart';
import '../common/art_card.dart';
import '../common/kit.dart';
import '../common/status_menu.dart';
import '../detail/screenshot_lightbox.dart';
import '../get/get_sheet.dart';
import '../library/game_context_menu.dart';
import '../modals/merge_game_dialog.dart';
import '../modals/metadata_fetch_modal.dart';
import '../modals/properties_modal.dart';
import 'game_actions.dart';
import 'version_path_view.dart';

/// The full-window game page, over whichever tab opened it.
class GamePage extends ConsumerWidget {
  final GameTarget target;
  const GamePage({super.key, required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(libraryProvider).groups;
    final group = target.baseKey == null ? null : groups.where((g) => g.baseKey == target.baseKey).firstOrNull;
    return GameView(
      key: ValueKey(target.baseKey ?? target.item?.id),
      group: group,
      item: target.item,
      onBack: () => ref.read(gamePageProvider.notifier).state = null,
      backLabel: target.origin.label,
    );
  }
}

/// One page for every game, owned or not. Your copy adds to it; it doesn't
/// change what the page is.
class GameView extends ConsumerStatefulWidget {
  final GameGroup? group;
  final RawFeedItem? item;
  final VoidCallback? onBack;
  final String backLabel;

  const GameView({super.key, this.group, this.item, this.onBack, this.backLabel = ''});

  @override
  ConsumerState<GameView> createState() => _GameViewState();
}

class _GameViewState extends ConsumerState<GameView> {
  String? _node;
  late final _notes = TextEditingController(text: _savedNote);

  String get _savedNote {
    final g = widget.group;
    return g == null ? '' : ref.read(userDataProvider).notes[g.baseKey] ?? '';
  }

  @override
  void didUpdateWidget(GameView old) {
    super.didUpdateWidget(old);
    if (old.group?.baseKey != widget.group?.baseKey) {
      _node = null;
      _notes.text = _savedNote;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final ud = ref.watch(userDataProvider);
    final epoch = ref.watch(imageEpochProvider);
    final update = g == null ? null : ref.watch(availableUpdatesProvider)[g.baseKey];

    final title = g?.effectiveTitle ?? widget.item?.title ?? '';
    final related = ref.watch(feedForGameProvider(feedTitleKey(title)));
    final item = widget.item ?? related.firstOrNull;
    final sources = threadSources(item, g, ref);
    final threadUrl = sources.firstOrNull?.url ?? '';
    final thread = ref.watch(threadProvider(threadUrl)).valueOrNull;
    final details = thread?.details;

    final carousel = g == null ? const <File>[] : groupCarouselPaths(g, ud.customArt[g.baseKey]);
    final String? heroArt = carousel.isNotEmpty
        ? carousel.first.path
        : (item?.coverUrl.isNotEmpty ?? false)
            ? item!.coverUrl
            : details?.coverUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(ambientPageProvider.notifier).state = heroArt;
    });

    final developer = [g?.effectiveDeveloper ?? '', item?.developer ?? '', details?.developer ?? '']
        .firstWhere((d) => d.isNotEmpty, orElse: () => '');
    final synopsis = [g?.newestMeta((v) => v.metaSynopsis) ?? '', details?.synopsis ?? '', item?.overview ?? '']
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final fetchedTags = g != null && g.newestMetaTags.isNotEmpty
        ? g.newestMetaTags
        : (item?.tags.isNotEmpty ?? false)
            ? item!.tags
            : details?.tags ?? const <String>[];
    final shots = carousel.length > 1
        ? carousel.skip(1).map((f) => f.path).toList()
        : details?.screenshotUrls ?? const <String>[];

    final changes = thread?.downloads.changes ?? const <ThreadChange>[];
    final installed = g?.versions.map((v) => v.versionStr).where((v) => v.isNotEmpty).toList() ?? const <String>[];
    final latest = update?.version ?? (item != null ? extractFeedVersion(item) : null) ?? (installed.isEmpty ? '' : installed.last);
    final newer = g != null && update != null;
    final played = g == null ? '' : ud.lastPlayedVersion[g.baseKey] ?? '';
    final path = buildVersionPath(
      installed: installed,
      changelog: changes.map((c) => c.version).toList(),
      latest: latest,
      played: played,
    );
    final selected = _node ?? latest;
    final notes = changes.where((c) => sameVersion(c.version, selected)).firstOrNull?.notes ?? const <String>[];

    final main = <Widget>[
      if (g != null) ...[
        for (final other in (ref.watch(duplicatesProvider)[g.baseKey] ?? const <GameGroup>[]).take(1))
          _DuplicatePrompt(game: g, other: other),
      ],
      if (selected.isNotEmpty && notes.isNotEmpty)
        _Section(
          title: "What's new in ${fmtVersion(selected)}",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: AppText.body(color: AppColors.textMuted)),
                      Expanded(child: Text(note, style: AppText.body(color: AppColors.textSecondary))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (synopsis.isNotEmpty)
        _Section(
          title: 'About this game',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SelectableText(synopsis, style: AppText.reading(fontSize: 18, height: 1.55, color: AppColors.textSecondary)),
          ),
        ),
      if (shots.isNotEmpty) _Section(title: 'Screenshots', child: _Shots(shots: shots)),
      if (fetchedTags.isNotEmpty || g != null)
        _Section(title: 'Tags', child: _Tags(group: g, fetched: fetchedTags)),
      if (g != null)
        _Section(
          title: 'Notes',
          child: TextField(
            controller: _notes,
            onChanged: (v) => ref.read(userDataProvider.notifier).setNote(g.baseKey, v),
            minLines: 4,
            maxLines: 12,
            style: AppText.ui(fontSize: 14, height: 1.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Personal notes',
              filled: true,
              fillColor: AppColors.bgCard.withValues(alpha: 0.8),
              border: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.accent)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      if (g == null && ref.watch(lockdownProvider))
        Text('Lockdown is on. Go online to see screenshots, downloads and what changed.',
            style: AppText.body(color: AppColors.textMuted)),
    ];

    final rail = <Widget>[
      if (g != null) ...[_YourCopy(group: g), const SizedBox(height: 16)],
      _Facts(group: g, item: item, latest: latest, sources: sources, rating: details?.rating ?? 0),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 780;
      final railWidth = (constraints.maxWidth * 0.3).clamp(260.0, 320.0);
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(
              images: [?heroArt, ...shots.where((s) => !s.startsWith('http'))],
              epoch: epoch,
              title: title,
              byline: [
                if (developer.isNotEmpty) 'by $developer',
                g?.latestVersion?.engineName ?? '',
                if (item != null) siteName(item.source),
              ].where((s) => s.isNotEmpty).join(' · '),
              width: constraints.maxWidth,
              onBack: widget.onBack,
              backLabel: widget.backLabel,
              actions: _actions(context, g, item, title, latest, update != null, selected),
            ),
            if (path.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 20, AppLayout.gutter, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Version path', style: AppText.display(fontSize: 21, height: 1.1, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    VersionPathView(
                      nodes: path,
                      selected: selected,
                      newer: newer,
                      onSelect: (v) => setState(() => _node = v),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppLayout.gutter, 16, AppLayout.gutter, 110),
              child: stacked
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...rail, const SizedBox(height: 24), ..._spaced(main)])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(main))),
                        const SizedBox(width: 32),
                        SizedBox(
                          width: railWidth,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rail),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }

  List<Widget> _spaced(List<Widget> items) => [
        for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(height: 24), w],
      ];

  List<Widget> _actions(BuildContext context, GameGroup? g, RawFeedItem? item, String title, String latest, bool update, String selected) {
    final actions = <Widget>[];
    if (g == null) {
      final key = feedTitleKey(title);
      final watching = ref.watch(userDataProvider.select((u) => u.watching.contains(key)));
      actions.add(VpButton(
        label: 'Download',
        icon: Icons.download_rounded,
        tone: VpTone.primary,
        onTap: () => showGetSheet(context, ref, title: title, item: item, version: latest),
      ));
      if (item != null) {
        actions.add(VpButton(
          label: watching ? 'Watching' : 'Watch',
          icon: Icons.visibility_outlined,
          tone: VpTone.glass,
          onTap: () => toggleWatch(ref, item),
        ));
      }
      actions.add(_MoreButton(onTap: (position) => _moreForFeed(context, item, position)));
      return actions;
    }

    final running = ref.watch(isGameRunningProvider(g.baseKey));
    final version = g.versions.where((v) => sameVersion(v.versionStr, selected)).firstOrNull ?? g.latestVersion;
    final play = VpButton(
      label: running
          ? 'Running'
          : version == null || version.versionStr.isEmpty
              ? 'Play'
              : 'Play ${fmtVersion(version.versionStr)}',
      icon: Icons.play_arrow_rounded,
      tone: update ? VpTone.glass : VpTone.primary,
      busy: running,
      onTap: () => playGame(context, ref, g, version),
    );
    if (update) {
      actions.add(VpButton(
        label: 'Update to ${fmtVersion(latest)}',
        icon: Icons.download_rounded,
        tone: VpTone.update,
        onTap: () => showGetSheet(context, ref, title: title, item: item, group: g, version: latest),
      ));
    }
    actions.add(play);
    actions.add(_MoreButton(
      onTap: (position) => showGameContextMenu(context: context, ref: ref, globalPosition: position, group: g),
    ));
    return actions;
  }

  Future<void> _moreForFeed(BuildContext context, RawFeedItem? item, Offset position) async {
    if (item == null) return;
    final key = feedTitleKey(item.title);
    final choice = await showVpMenu<String>(context: context, position: position, items: [
      const VpMenuItem('thread', 'Open thread', icon: Icons.open_in_new),
      const VpMenuItem('mute', 'Mute this game', icon: Icons.notifications_off_outlined),
    ]);
    if (choice == 'thread' && ref.read(settingsProvider).allowDownloadLinks) launchUrl(Uri.parse(item.url));
    if (choice == 'mute') {
      ref.read(userDataProvider.notifier).setMuted(key, true);
      widget.onBack?.call();
    }
  }
}

class _MoreButton extends StatelessWidget {
  final ValueChanged<Offset> onTap;
  const _MoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => VpIconButton(
        icon: Icons.more_horiz,
        tooltip: 'More actions',
        onArt: true,
        size: 38,
        onTap: () {
          final box = context.findRenderObject() as RenderBox;
          onTap(box.localToGlobal(Offset(0, box.size.height + 6)));
        },
      ),
    );
  }
}

/// The art, moving through the game's other images at the Slideshow Interval
/// from Settings. A fresh visit starts on the cover.
class _HeroArt extends ConsumerStatefulWidget {
  final List<String> images;
  final int epoch;
  const _HeroArt({required this.images, required this.epoch});

  @override
  ConsumerState<_HeroArt> createState() => _HeroArtState();
}

class _HeroArtState extends ConsumerState<_HeroArt> {
  int _index = 0;
  Timer? _timer;
  double? _interval;

  void _schedule(double seconds) {
    if (_interval == seconds && _timer != null) return;
    _interval = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: (seconds * 1000).round()), (_) {
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!still && widget.images.length > 1) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = ref.watch(settingsProvider.select((s) => s.slideshowInterval));
    if (widget.images.length > 1 && seconds > 0) _schedule(seconds);
    final art = widget.images.isEmpty ? null : widget.images[_index % widget.images.length];
    return AnimatedSwitcher(
      duration: AppMotion.of(context, const Duration(milliseconds: 600)),
      child: SizedBox.expand(
        key: ValueKey(art),
        child: GameArt(source: art, epoch: widget.epoch, decodeWidth: 1600, alignment: const Alignment(0, -0.56)),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final List<String> images;
  final int epoch;
  final String title;
  final String byline;
  final double width;
  final VoidCallback? onBack;
  final String backLabel;
  final List<Widget> actions;

  const _Hero({
    required this.images,
    required this.epoch,
    required this.title,
    required this.byline,
    required this.width,
    required this.onBack,
    required this.backLabel,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.52).clamp(340.0, 500.0);
    final titleSize = (width * 0.064).clamp(36.0, 78.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ArtFade(
            from: 0.58,
            child: _HeroArt(images: images, epoch: epoch),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.3, 0.76, 1],
                colors: [
                  const Color(0x3806080D),
                  const Color(0x0006080D),
                  const Color(0x8006080D),
                  AppColors.isDark ? const Color(0x0006080D) : const Color(0xB806080D),
                ],
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              left: AppLayout.gutter,
              top: 16,
              child: Pressable(
                onTap: onBack,
                label: 'Back to $backLabel',
                builder: (context, states) => Container(
                  height: 32,
                  padding: const EdgeInsets.fromLTRB(7, 0, 12, 0),
                  decoration: BoxDecoration(
                    color: const Color(0x9E080A0F),
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left, size: 18, color: AppColors.onArt),
                      const SizedBox(width: 4),
                      Text(backLabel, style: AppText.body(color: AppColors.onArt, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: AppLayout.gutter,
            right: AppLayout.gutter,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.display(
                    fontSize: titleSize,
                    height: 1,
                    letterSpacing: titleSize * -0.018,
                    color: AppColors.onArt,
                    shadows: const [Shadow(color: Color(0x8C000000), blurRadius: 26, offset: Offset(0, 2))],
                  ),
                ),
                if (byline.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(byline, style: AppText.ui(fontSize: 15, height: 1.3, color: AppColors.onArtSoft)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppText.display(fontSize: 21, height: 1.15, color: AppColors.textPrimary)),
        const SizedBox(height: 9),
        child,
      ],
    );
  }
}

class _Shots extends StatelessWidget {
  final List<String> shots;
  const _Shots({required this.shots});

  void _open(BuildContext context, int index) {
    final paths = [
      for (final s in shots)
        if (s.startsWith('http')) FeedImageCache.fileFor(s).path else s,
    ].where((p) => File(p).existsSync()).toList();
    if (paths.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, _, _) => ScreenshotLightbox(paths: paths, initialIndex: index.clamp(0, paths.length - 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * 2) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (i, shot) in shots.take(9).indexed)
            Pressable(
              onTap: () => _open(context, i),
              label: 'Screenshot ${i + 1}',
              radius: const BorderRadius.all(Radius.circular(6)),
              builder: (context, states) => SizedBox(
                width: width,
                height: width * 9 / 16,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  child: GameArt(source: shot, decodeWidth: 400),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Tags extends ConsumerWidget {
  final GameGroup? group;
  final List<String> fetched;
  const _Tags({required this.group, required this.fetched});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = group;
    final mine = g == null ? const <String>[] : ref.watch(userDataProvider.select((u) => u.tags[g.baseKey])) ?? const <String>[];
    final notifier = ref.read(userDataProvider.notifier);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in fetched) VpTag(label: tag),
        for (final tag in mine.where((t) => !fetched.contains(t)))
          VpTag(label: tag, onRemove: () => notifier.setTags(g!.baseKey, mine.where((t) => t != tag).toList())),
        if (g != null)
          VpButton(
            label: 'Add tag',
            icon: Icons.add,
            tone: VpTone.quiet,
            small: true,
            onTap: () => _addTag(context, ref, g.baseKey, mine),
          ),
      ],
    );
  }

  void _addTag(BuildContext context, WidgetRef ref, String baseKey, List<String> current) {
    final notifier = ref.read(userDataProvider.notifier);
    var value = '';
    var keepAsPreset = false;
    void add(String tag) {
      if (tag.isEmpty || current.contains(tag)) return;
      notifier.setTags(baseKey, [...current, tag]);
      if (keepAsPreset && !presetTags.contains(tag)) notifier.addCustomPreset(tag);
    }

    final presets = [
      ...presetTags,
      ...ref.read(userDataProvider).customPresets,
    ].where((t) => !current.contains(t)).toList();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add a tag', style: AppText.heading()),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in presets)
                  VpChip(
                    label: tag,
                    onTap: () {
                      add(tag);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                style: AppText.body(),
                decoration: const InputDecoration(hintText: 'Or type your own'),
                onChanged: (v) => value = v.trim(),
                onSubmitted: (_) {
                  add(value);
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: 6),
              StatefulBuilder(
                builder: (ctx2, setDialog) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.accent,
                  value: keepAsPreset,
                  onChanged: (v) => setDialog(() => keepAsPreset = v ?? false),
                  title: Text('Keep as a preset', style: AppText.meta()),
                ),
              ),
            ],
          ),
        ),
        actions: [
          VpButton(label: 'Cancel', tone: VpTone.quiet, small: true, onTap: () => Navigator.of(ctx).pop()),
          VpButton(
            label: 'Add',
            tone: VpTone.primary,
            small: true,
            onTap: () {
              add(value);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
}

/// Offers to merge a game with one that looks like the same game.
class _DuplicatePrompt extends ConsumerWidget {
  final GameGroup game;
  final GameGroup other;
  const _DuplicatePrompt({required this.game, required this.other});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return VpCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.call_merge, size: 15, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This may be the same game as ${other.latestVersion?.folderName ?? other.effectiveTitle}.',
              style: AppText.body(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          VpButton(label: 'Merge', small: true, onTap: () => showMergeGameDialog(context, game)),
          const SizedBox(width: 6),
          VpButton(
            label: 'Not a duplicate',
            small: true,
            tone: VpTone.quiet,
            onTap: () => ref.read(userDataProvider.notifier).markNotDuplicate(game.baseKey, other.baseKey),
          ),
        ],
      ),
    );
  }
}

class _YourCopy extends ConsumerWidget {
  final GameGroup group;
  const _YourCopy({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ud = ref.watch(userDataProvider);
    final status = effectiveGameStatus(group, ud);
    final seconds = ud.playtime[group.baseKey] ?? 0;
    final last = gameLastPlayedAt(group, ud);
    final sessions = ud.playCount[group.baseKey] ?? 0;

    return VpCard(
      title: 'Your copy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VpFact(
            label: 'Status',
            child: Builder(
              builder: (context) => Pressable(
                label: 'Status, ${status.label}',
                onTap: () async {
                  final box = context.findRenderObject() as RenderBox;
                  final at = box.localToGlobal(Offset(0, box.size.height + 4));
                  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                  final choice = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
                    items: statusMenuEntries(
                      detected: detectedGameStatus(group, ud),
                      picked: GameStatus.fromId(ud.status[group.baseKey]),
                    ),
                  );
                  if (choice != null) ref.read(userDataProvider.notifier).setStatus(group.baseKey, choice);
                },
                builder: (context, states) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon(status), size: 15, color: statusColor(status)),
                    const SizedBox(width: 5),
                    Text(status.label,
                        style: AppText.body(
                          fontWeight: FontWeight.w500,
                          color: states.contains(WidgetState.hovered) ? AppColors.accent : AppColors.textPrimary,
                        )),
                  ],
                ),
              ),
            ),
          ),
          VpFact(label: 'Play time', value: seconds > 0 ? fmtTime(seconds) : 'None'),
          VpFact(label: 'Last played', value: last == null ? 'Never' : fmtDate(last.toIso8601String())),
          VpFact(label: 'Sessions', value: '$sessions'),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: VpButton(
              label: 'Patches and properties',
              tone: VpTone.quiet,
              small: true,
              onTap: () => showPropertiesModal(context, group),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: VpButton(
              label: 'Fetch metadata',
              tone: VpTone.quiet,
              small: true,
              onTap: () => showMetadataFetchModal(context, group),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends ConsumerStatefulWidget {
  final GameGroup? group;
  final RawFeedItem? item;
  final String latest;
  final List<ThreadSource> sources;
  final double rating;

  const _Facts({
    required this.group,
    required this.item,
    required this.latest,
    required this.sources,
    required this.rating,
  });

  @override
  ConsumerState<_Facts> createState() => _FactsState();
}

class _FactsState extends ConsumerState<_Facts> {
  Future<int>? _size;
  String? _sizeFor;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final path = g?.latestVersion?.folderPath.path;
    if (path != _sizeFor) {
      _sizeFor = path;
      _size = path == null ? null : compute(_folderSize, path);
    }
    final rating = g == null ? null : ref.watch(gameRatingsProvider)[g.baseKey];
    final shownRating = rating ?? (widget.rating > 0 ? widget.rating : widget.item?.rating ?? 0);
    final version = g?.latestVersion;
    final engine = version?.engineName ?? '';
    final at = widget.item?.publishedAt;
    final links = ref.watch(settingsProvider.select((s) => s.allowDownloadLinks));

    return VpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.latest.isNotEmpty) VpFact(label: 'Latest', value: fmtVersion(widget.latest), mono: true),
          VpFact(
            label: 'You have',
            value: g == null ? 'Not installed' : g.versions.map((v) => fmtVersion(v.versionStr)).join(', '),
            mono: g != null,
          ),
          if (at != null) VpFact(label: 'Updated', value: '${releaseTime(at)} (${ageText(at)} ago)'),
          if (engine.isNotEmpty) VpFact(label: 'Engine', value: engine),
          if (_size != null)
            FutureBuilder<int>(
              future: _size,
              builder: (context, snap) => VpFact(
                label: 'Size',
                value: snap.hasData && snap.data! > 0 ? fmtBytes(snap.data!) : '…',
              ),
            ),
          if (shownRating > 0) VpFact(label: 'Rating', value: '★ ${shownRating.toStringAsFixed(1)}'),
          if (widget.sources.isNotEmpty)
            VpFact(label: 'Available on', value: widget.sources.map((s) => siteName(s.source)).join(', '), last: !links),
          if (links && widget.sources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 2,
              children: [
                for (final s in widget.sources)
                  VpButton(
                    label: 'Open on ${siteName(s.source)}',
                    icon: Icons.open_in_new,
                    tone: VpTone.quiet,
                    small: true,
                    onTap: () => launchUrl(Uri.parse(s.url)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

int _folderSize(String path) {
  var total = 0;
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += entity.lengthSync();
      } catch (_) {}
    }
  }
  return total;
}
