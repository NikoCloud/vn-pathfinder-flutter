import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/feed_item.dart';
import '../../models/game_group.dart';
import '../../providers/feed_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/shell_provider.dart';
import '../../providers/update_provider.dart';
import '../../theme.dart';
import '../game/game_actions.dart';
import 'art.dart';
import 'kit.dart';

/// One result in quick find: a library game or a Feed release.
class FinderHit {
  final GameGroup? game;
  final RawFeedItem? item;
  const FinderHit({this.game, this.item});
  String get title => game?.effectiveTitle ?? item!.title;
  String get subtitle => game?.effectiveDeveloper ?? item!.developer;
}

/// Library games first, then Feed releases not already listed, at most [limit].
/// Every word of [query] has to appear in the title or the developer.
List<FinderHit> findGames(String query, Iterable<GameGroup> groups, Iterable<RawFeedItem> items, {int limit = 6}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  bool hit(String text) => words.every(text.toLowerCase().contains);

  final hits = <FinderHit>[];
  final titles = <String>{};
  for (final g in groups) {
    if (g.versions.isEmpty || !hit('${g.effectiveTitle} ${g.effectiveDeveloper}')) continue;
    titles.add(feedTitleKey(g.effectiveTitle));
    hits.add(FinderHit(game: g));
  }
  for (final item in items) {
    if (!hit('${item.title} ${item.developer}')) continue;
    if (titles.add(feedTitleKey(item.title))) hits.add(FinderHit(item: item));
  }
  return hits.take(limit).toList();
}

/// Ctrl+K: type a name, press Enter.
class Finder extends ConsumerWidget {
  const Finder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(finderOpenProvider)) return const SizedBox.shrink();
    return const Positioned.fill(child: _FinderBox());
  }
}

class _FinderBox extends ConsumerStatefulWidget {
  const _FinderBox();

  @override
  ConsumerState<_FinderBox> createState() => _FinderBoxState();
}

class _FinderBoxState extends ConsumerState<_FinderBox> {
  String _query = '';
  int _index = 0;

  void _close() => ref.read(finderOpenProvider.notifier).state = false;

  void _open(FinderHit hit) {
    _close();
    openGame(ref, baseKey: hit.game?.baseKey, item: hit.item);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(libraryProvider).groups;
    final items = ref.watch(feedProvider).items;
    final updates = ref.watch(availableUpdatesProvider);
    final hits = findGames(_query, groups, items);
    final index = hits.isEmpty ? 0 : _index.clamp(0, hits.length - 1);
    final top = MediaQuery.sizeOf(context).height * 0.13;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(onTap: _close, child: const ColoredBox(color: Color(0x80040509))),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: top),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _close,
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(() => _index = index + 1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(() => _index = index - 1),
              },
              child: Container(
                width: 620,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.border),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 26))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                        child: Row(
                          children: [
                            Icon(Icons.search, size: 18, color: AppColors.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                autofocus: true,
                                onChanged: (v) => setState(() {
                                  _query = v;
                                  _index = 0;
                                }),
                                onSubmitted: (_) {
                                  if (hits.isNotEmpty) _open(hits[index]);
                                },
                                cursorColor: AppColors.accent,
                                style: AppText.ui(fontSize: 16, color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  hintText: 'Find a game',
                                  hintStyle: AppText.ui(fontSize: 16, color: AppColors.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hits.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text('No games match.', style: AppText.body(color: AppColors.textMuted)),
                        ),
                      for (final (i, hit) in hits.indexed)
                        _Result(
                          hit: hit,
                          active: i == index,
                          note: hit.game == null
                              ? siteName(hit.item!.source)
                              : updates.containsKey(hit.game!.baseKey)
                                  ? 'New version'
                                  : 'In library',
                          onTap: () => _open(hit),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Result extends ConsumerWidget {
  final FinderHit hit;
  final bool active;
  final String note;
  final VoidCallback onTap;
  const _Result({required this.hit, required this.active, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = hit.game != null ? localArt(hit.game!, ref) : hit.item!.coverUrl;
    return Pressable(
      onTap: onTap,
      label: hit.title,
      radius: BorderRadius.zero,
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: active || states.contains(WidgetState.hovered) ? AppColors.bgHover : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 45,
              child: ClipRRect(borderRadius: AppRadius.borderXs, child: GameArt(source: art, decodeWidth: 96)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(fontWeight: FontWeight.w500)),
                  Text(hit.subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(note, style: AppText.meta(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
