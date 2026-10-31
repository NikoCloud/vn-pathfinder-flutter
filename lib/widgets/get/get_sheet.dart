import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../models/feed_item.dart';
import '../../models/game_group.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/feed_view_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/thread_provider.dart';
import '../../services/archive_cards.dart';
import '../../services/thread_parser.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/art.dart';
import '../common/kit.dart';
import '../game/game_actions.dart';

/// Getting a game: pick a site, a platform and a host, then the site's real
/// page opens in the panel. It stays exactly as it is on the site, with any
/// check, wait or ad, and whoever is at the keyboard finishes it there. The app
/// only notices the download starting and takes it from there.
Future<void> showGetSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  RawFeedItem? item,
  GameGroup? group,
  String version = '',
}) async {
  final notify = ref.read(notificationProvider.notifier);
  final settings = ref.read(settingsProvider);
  if (settings.lockdown) {
    notify.info('Go online to download. Lockdown is on.');
    return;
  }
  if (settings.libraryDir.isEmpty) {
    notify.info('Choose a library folder in Settings first.');
    return;
  }

  final sources = threadSources(item, group, ref);
  if (sources.isEmpty) {
    notify.info('No site is linked to this game yet. Fetch its metadata first.');
    return;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x80040509),
    transitionDuration: AppMotion.of(context, const Duration(milliseconds: 220)),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: _GetSheet(title: title, item: item, group: group, version: version, sources: sources),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
  ref.read(downloadsProvider.notifier).panelClosed();
}

/// A thread a game can be got from, on one site.
typedef ThreadSource = ({String source, String url});

/// The threads for a game: where the Feed saw it first, then saved links, then
/// any other site the Feed has it on.
List<ThreadSource> threadSources(RawFeedItem? item, GameGroup? group, WidgetRef ref) {
  final out = <ThreadSource>[];
  void add(String source, String url) {
    if (url.isNotEmpty && !out.any((s) => s.source == source)) out.add((source: source, url: url));
  }

  if (item != null) add(item.source, item.url);
  if (group != null) {
    add('f95zone', group.newestMeta((v) => v.metaF95Url));
    add('lewdcorner', group.newestMeta((v) => v.metaLcUrl));
    add('azc', group.newestMeta((v) => v.metaAzcUrl));
  }
  final title = item?.title ?? group?.effectiveTitle;
  if (title != null) {
    for (final other in ref.read(feedForGameProvider(feedTitleKey(title)))) {
      add(other.source, other.url);
    }
  }
  return out;
}

class _GetSheet extends ConsumerStatefulWidget {
  final String title;
  final RawFeedItem? item;
  final GameGroup? group;
  final String version;
  final List<ThreadSource> sources;

  const _GetSheet({
    required this.title,
    required this.item,
    required this.group,
    required this.version,
    required this.sources,
  });

  @override
  ConsumerState<_GetSheet> createState() => _GetSheetState();
}

class _GetSheetState extends ConsumerState<_GetSheet> {
  late ThreadSource _source = widget.sources.first;
  String? _platform;
  bool _inSite = false;
  bool _keepOld = true;
  int _jobsAtStart = 0;

  @override
  void initState() {
    super.initState();
    _keepOld = ref.read(settingsProvider).keepOldVersion;
    _jobsAtStart = ref.read(downloadsProvider).length;
  }

  /// [isGame] is false for extras like a walkthrough, which aren't the game.
  void _openSite(String url, {bool isGame = true}) {
    final settings = ref.read(settingsProvider);
    final installed = widget.group?.latestVersion;
    final downloads = ref.read(downloadsProvider.notifier);
    final thread = ref.read(threadProvider(_source.url)).valueOrNull;
    downloads.intent = DownloadIntent(
      title: widget.title,
      cover: widget.item?.coverUrl ?? '',
      version: widget.version,
      baseKey: widget.group?.baseKey,
      replaceFolder: _keepOld ? null : installed?.folderPath.path,
      card: !isGame
          ? null
          : ArchiveCardDraft.build(
              title: widget.group?.effectiveTitle ?? widget.title,
              version: widget.version,
              source: _source.source,
              threadUrl: _source.url,
              nameHint: widget.group?.displayName ?? '',
              item: widget.item,
              details: thread?.details,
            ),
    );
    downloads.browserPanelOpen = true;
    if (settings.keepOldVersion != _keepOld) ref.read(settingsProvider.notifier).setKeepOldVersion(_keepOld);
    ref.read(siteBrowserProvider).open(url, downloadFolder: settings.libraryDir);
    setState(() => _inSite = true);
  }

  @override
  Widget build(BuildContext context) {
    // The moment a download starts, the sheet has done its job.
    ref.listen(downloadsProvider, (_, jobs) {
      if (jobs.length > _jobsAtStart && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });

    final width = MediaQuery.sizeOf(context).width;
    return Material(
      color: AppColors.bgCard,
      child: AnimatedContainer(
        duration: AppMotion.of(context, const Duration(milliseconds: 250)),
        curve: Curves.easeOut,
        width: (_inSite ? 980.0 : 440.0).clamp(0.0, width),
        height: double.infinity,
        decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Head(title: widget.title, version: widget.version, cover: widget.item?.coverUrl, source: _source),
            Expanded(child: _inSite ? const _SitePanel() : _choices()),
          ],
        ),
      ),
    );
  }

  Widget _choices() {
    final thread = ref.watch(threadProvider(_source.url));
    final installed = widget.group?.latestVersion;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: AppText.body(fontWeight: FontWeight.w600)),
        );

    final sections = <Widget>[
      if (widget.sources.length > 1) ...[
        heading('Site'),
        _Picker<ThreadSource>(
          value: _source,
          options: [for (final s in widget.sources) (s, siteName(s.source))],
          onChanged: (s) => setState(() {
            _source = s;
            _platform = null;
          }),
        ),
        const SizedBox(height: 18),
      ],
      ...thread.when(
        loading: () => [
          heading('Download'),
          Text('Reading the thread', style: AppText.body(color: AppColors.textMuted)),
        ],
        error: (_, _) => _noLinks(heading),
        data: (found) {
          final links = found?.downloads.links ?? const <ThreadLink>[];
          if (links.isEmpty) return _noLinks(heading);
          final platforms = found!.downloads.platforms;
          final platform = platforms.contains(_platform) ? _platform! : platforms.first;
          final hosts = links.where((l) => l.platform == platform).toList();
          return [
            if (platforms.length > 1) ...[
              heading('Platform'),
              _Picker<String>(
                value: platform,
                options: [for (final p in platforms) (p, p.isEmpty ? 'Other' : p)],
                onChanged: (p) => setState(() => _platform = p),
              ),
              const SizedBox(height: 18),
            ],
            if (hosts.length == 1 && hosts.single.host == 'Download page') ...[
              heading('Download'),
              Text('${siteName(_source.source)} keeps its links on one page.',
                  style: AppText.meta(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: VpButton(
                  label: 'Open the download page',
                  tone: VpTone.primary,
                  onTap: () => _openSite(hosts.single.url),
                ),
              ),
            ] else ...[
              heading('Download from'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4.4,
                children: [
                  for (final link in hosts)
                    _Host(label: link.host, onTap: () => _openSite(link.url, isGame: link.platform != 'Extras')),
                ],
              ),
            ],
          ];
        },
      ),
      if (installed != null) ...[
        const SizedBox(height: 18),
        heading('After it installs'),
        _Radio(label: 'Keep ${fmtVersion(installed.versionStr)} too', on: _keepOld, onTap: () => setState(() => _keepOld = true)),
        _Radio(label: 'Remove ${fmtVersion(installed.versionStr)}', on: !_keepOld, onTap: () => setState(() => _keepOld = false)),
        const SizedBox(height: 4),
        Text(
          "Removing it deletes that folder, including saves kept inside it. Ren'Py also keeps its saves in AppData.",
          style: AppText.meta(color: AppColors.textMuted),
        ),
      ],
      const SizedBox(height: 18),
      Text('The file goes to your library folder, then Pathfinder extracts it and adds it to your library.',
          style: AppText.meta(color: AppColors.textMuted)),
    ];

    return ListView(padding: const EdgeInsets.all(16), children: sections);
  }

  List<Widget> _noLinks(Widget Function(String) heading) => [
        heading('Download'),
        Text("Pathfinder couldn't read the links in this thread. You can get them from the thread itself.",
            style: AppText.meta(color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: VpButton(label: 'Open the thread', tone: VpTone.primary, onTap: () => _openSite(_source.url)),
        ),
      ];
}

class _Head extends StatelessWidget {
  final String title;
  final String version;
  final String? cover;
  final ThreadSource source;
  const _Head({required this.title, required this.version, required this.cover, required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 36,
            child: ClipRRect(borderRadius: AppRadius.borderXs, child: GameArt(source: cover, decodeWidth: 96)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$title ${version.isEmpty ? '' : fmtVersion(version)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(fontSize: 18, height: 1.15, color: AppColors.textPrimary)),
                Text(siteName(source.source), style: AppText.meta(color: AppColors.textMuted)),
              ],
            ),
          ),
          VpIconButton(icon: Icons.close, tooltip: 'Close', onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const _Picker({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: AppRadius.borderMd),
        child: ClipRRect(
          borderRadius: AppRadius.borderMd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (v, label) in options)
                Pressable(
                  onTap: () => onChanged(v),
                  selected: v == value,
                  label: label,
                  radius: BorderRadius.zero,
                  builder: (context, states) => Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    color: v == value ? AppColors.bgActive : Colors.transparent,
                    child: Text(label,
                        style: AppText.body(
                          fontWeight: FontWeight.w500,
                          color: v == value ? AppColors.textPrimary : AppColors.textSecondary,
                        )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Host extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Host({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: 'Download from $label',
      builder: (context, states) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bgHover,
          border: Border.all(color: states.contains(WidgetState.hovered) ? AppColors.accent : AppColors.border),
          borderRadius: AppRadius.borderMd,
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.ui(fontSize: 13, height: 1, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppColors.textPrimary)),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Radio({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: label,
      selected: on,
      builder: (context, states) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 16, color: on ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 9),
            Text(label, style: AppText.body(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// The in-app browser: a plain address line and the site's page.
class _SitePanel extends ConsumerWidget {
  const _SitePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browser = ref.watch(siteBrowserProvider);
    final controller = browser.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              VpIconButton(icon: Icons.arrow_back, tooltip: 'Back', onTap: browser.canGoBack ? browser.back : null),
              VpIconButton(icon: Icons.arrow_forward, tooltip: 'Forward', onTap: browser.canGoForward ? browser.forward : null),
              VpIconButton(icon: Icons.refresh, tooltip: 'Reload', onTap: browser.reload),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    border: Border.all(color: AppColors.border),
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Row(
                    children: [
                      Icon(browser.url.startsWith('https') ? Icons.lock_outline : Icons.public,
                          size: 14, color: browser.url.startsWith('https') ? AppColors.accent : AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(browser.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.ui(fontSize: 12.5, height: 1, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: browser.error != null
                  ? Center(child: Text(browser.error!, style: AppText.body(color: AppColors.textSecondary)))
                  : controller == null || !controller.value.isInitialized
                      ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                      : Webview(controller),
            ),
          ),
        ),
      ],
    );
  }
}
