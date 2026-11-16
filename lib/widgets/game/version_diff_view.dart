import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/game_group.dart';
import '../../providers/version_stats_provider.dart';
import '../../services/update_record.dart';
import '../../services/version_records.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../common/kit.dart';
import 'version_stats_chart.dart' show fmtCount;

/// What changed between versions (#44): pictures removed, changed, added or
/// re-encoded, and lines removed, rewritten or added, scene by scene. Or
/// everything the game once had that the newest version doesn't, with the
/// last version that still had it.
class VersionDiffView extends StatefulWidget {
  final GameGroup group;

  /// Recorded versions, oldest first.
  final List<String> versions;

  const VersionDiffView({super.key, required this.group, required this.versions});

  @override
  State<VersionDiffView> createState() => _VersionDiffViewState();
}

enum _Mode { between, gone }

enum _Kind { pictures, dialogue }

class _VersionDiffViewState extends State<VersionDiffView> {
  var _mode = _Mode.between;
  var _kind = _Kind.pictures;
  late String _from, _to;
  Future<RecordDiff?>? _diff;
  Future<({List<Gone<String>> media, List<Gone<RecordLine>> lines})>? _gone;

  @override
  void initState() {
    super.initState();
    _defaults();
  }

  @override
  void didUpdateWidget(VersionDiffView old) {
    super.didUpdateWidget(old);
    if (old.group.baseKey != widget.group.baseKey || !_sameList(old.versions, widget.versions)) _defaults();
  }

  static bool _sameList(List<String> a, List<String> b) => a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);

  void _defaults() {
    final v = widget.versions;
    _from = v[v.length - 2];
    _to = v.last;
    _load();
  }

  void _load() {
    final key = widget.group.baseKey;
    _diff = compareVersions(key, _from, _to);
    _gone = goneFromGame(key, widget.versions);
  }

  /// The installed folder of [version], to read a picture from.
  String? _folderOf(String version) =>
      widget.group.versions.where((v) => v.versionStr == version).firstOrNull?.folderPath.path;

  Future<void> _pick(BuildContext context, bool from) async {
    final current = from ? _from : _to;
    final choice = await showVpMenuBelow<String>(context, [
      for (final v in widget.versions) VpMenuItem(v, fmtVersion(v), checked: v == current),
    ]);
    if (choice == null || !mounted) return;
    setState(() {
      if (from) {
        _from = choice;
      } else {
        _to = choice;
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 2,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VpShelf(label: 'Between versions', selected: _mode == _Mode.between, onTap: () => setState(() => _mode = _Mode.between)),
            VpShelf(label: 'No longer in the game', selected: _mode == _Mode.gone, onTap: () => setState(() => _mode = _Mode.gone)),
            if (_mode == _Mode.between) ...[
              const SizedBox(width: 12),
              Builder(builder: (c) => VpButton(label: fmtVersion(_from), small: true, icon: Icons.expand_more, onTap: () => _pick(c, true))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 14, color: AppColors.textMuted),
              ),
              Builder(builder: (c) => VpButton(label: fmtVersion(_to), small: true, icon: Icons.expand_more, onTap: () => _pick(c, false))),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (_mode == _Mode.between) _between() else _goneView(),
      ],
    );
  }

  Widget _kindTabs(int pictures, int lines) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          VpShelf(label: 'Pictures', count: pictures, selected: _kind == _Kind.pictures, onTap: () => setState(() => _kind = _Kind.pictures)),
          const SizedBox(width: 2),
          VpShelf(label: 'Dialogue', count: lines, selected: _kind == _Kind.dialogue, onTap: () => setState(() => _kind = _Kind.dialogue)),
        ]),
      );

  Widget _between() {
    return FutureBuilder<RecordDiff?>(
      future: _diff,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _note('Comparing…');
        final d = snap.data;
        if (d == null) return _note("One of these versions hasn't been recorded yet.");
        if (_from == _to) return _note('Pick two different versions.');
        if (d.empty) return _note('No differences in pictures or dialogue.');
        final pictures = d.removedMedia.length + d.changedMedia.length + d.addedMedia.length;
        final lines = d.removedLines.length + d.rewrittenLines.length + d.addedLines.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary([
              _counts('Pictures', [
                (d.removedMedia.length, 'removed'),
                (d.changedMedia.length, 'changed'),
                (d.addedMedia.length, 'added'),
                (d.convertedMedia.length, 're-encoded as a new file type'),
              ]),
              _counts('Lines', [
                (d.removedLines.length, 'removed'),
                (d.rewrittenLines.length, 'rewritten'),
                (d.addedLines.length, 'added'),
              ]),
              if (d.removedScenes.isNotEmpty) 'Scenes gone: ${fmtCount(d.removedScenes.length)}',
            ].where((s) => s.isNotEmpty).toList()),
            const SizedBox(height: 10),
            _kindTabs(pictures, lines),
            if (_kind == _Kind.pictures) ...[
              _PictureGroup(
                title: 'Removed in ${fmtVersion(_to)}',
                keys: d.removedMedia,
                baseKey: widget.group.baseKey,
                version: (_) => _from,
                folderOf: _folderOf,
              ),
              _PictureGroup(
                title: 'Changed in ${fmtVersion(_to)}',
                note: 'Same name, different file: redrawn, edited or only recompressed. Open one to compare.',
                keys: d.changedMedia,
                baseKey: widget.group.baseKey,
                version: (_) => _from,
                folderOf: _folderOf,
                compareWith: _to,
              ),
              _PictureGroup(
                title: 'New in ${fmtVersion(_to)}',
                keys: d.addedMedia,
                baseKey: widget.group.baseKey,
                version: (_) => _to,
                folderOf: _folderOf,
                startOpen: false,
              ),
            ] else
              _LinesView(removed: d.removedLines, rewritten: d.rewrittenLines, added: d.addedLines, goneScenes: d.removedScenes),
          ],
        );
      },
    );
  }

  Widget _goneView() {
    return FutureBuilder(
      future: _gone,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _note('Looking through every recorded version…');
        final g = snap.data;
        if (g == null || (g.media.isEmpty && g.lines.isEmpty)) {
          return _note('Everything the recorded versions had is still in ${fmtVersion(widget.versions.last)}.');
        }
        final lastIn = {for (final x in g.media) x.item: x.lastVersion};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary([
              if (g.media.isNotEmpty) '${fmtCount(g.media.length)} pictures',
              if (g.lines.isNotEmpty) '${fmtCount(g.lines.length)} lines',
              'that earlier versions had and ${fmtVersion(widget.versions.last)} doesn\'t',
            ]),
            const SizedBox(height: 10),
            _kindTabs(g.media.length, g.lines.length),
            if (_kind == _Kind.pictures)
              _PictureGroup(
                title: 'Pictures',
                keys: [for (final x in g.media) x.item],
                baseKey: widget.group.baseKey,
                version: (k) => lastIn[k]!,
                folderOf: _folderOf,
                caption: (k) => 'last in ${fmtVersion(lastIn[k]!)}',
              )
            else
              _LinesView(
                removed: [for (final x in g.lines) x.item],
                lastIn: {for (final x in g.lines) x.item: x.lastVersion},
                rewritten: const [],
                added: const [],
                goneScenes: const [],
              ),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: AppText.body(color: AppColors.textMuted)),
      );

  Widget _summary(List<String> parts) => Text(parts.join('   ·   '), style: AppText.body(color: AppColors.textSecondary));

  /// "Pictures: 55 changed, 907 added", or empty when all are zero.
  String _counts(String what, List<(int, String)> parts) {
    final shown = [for (final (n, label) in parts) if (n > 0) '${fmtCount(n)} $label'];
    return shown.isEmpty ? '' : '$what: ${shown.join(', ')}';
  }
}

/// A group of pictures, as thumbnails where one was kept or a version that
/// has the picture is installed, otherwise as names.
class _PictureGroup extends StatefulWidget {
  final String title;
  final String? note;
  final List<String> keys;
  final String baseKey;

  /// The version a picture is shown from.
  final String Function(String key) version;
  final String? Function(String version) folderOf;
  final String Function(String key)? caption;

  /// For changed pictures: the version to show beside the old one.
  final String? compareWith;
  final bool startOpen;

  const _PictureGroup({
    required this.title,
    required this.keys,
    required this.baseKey,
    required this.version,
    required this.folderOf,
    this.note,
    this.caption,
    this.compareWith,
    this.startOpen = true,
  });

  @override
  State<_PictureGroup> createState() => _PictureGroupState();
}

class _PictureGroupState extends State<_PictureGroup> {
  late var _open = widget.startOpen;
  var _shown = 48;

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text('${widget.title}  ', style: AppText.ui(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(fmtCount(widget.keys.length), style: AppText.mono(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
          ),
          if (_open) ...[
            if (widget.note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 22),
                child: Text(widget.note!, style: AppText.ui(fontSize: 12.5, color: AppColors.textMuted)),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final k in widget.keys.take(_shown))
                  _Tile(
                    picture: k,
                    caption: widget.caption?.call(k),
                    thumb: thumbPath(widget.baseKey, widget.version(k), k),
                    folder: widget.folderOf(widget.version(k)),
                    onOpen: () => _openPicture(context, k),
                  ),
              ],
            ),
            if (widget.keys.length > _shown)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VpButton(
                    label: 'Show ${fmtCount((widget.keys.length - _shown).clamp(0, 96))} more',
                    small: true,
                    tone: VpTone.quiet,
                    onTap: () => setState(() => _shown += 96),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPicture(BuildContext context, String key) async {
    final version = widget.version(key);
    final other = widget.compareWith;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.bgCard,
        insetPadding: const EdgeInsets.all(40),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(key, style: AppText.mono(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(child: _FullPicture(label: fmtVersion(version), load: () => _bytes(key, version))),
                    if (other != null) ...[
                      const SizedBox(width: 12),
                      Flexible(child: _FullPicture(label: fmtVersion(other), load: () => _bytes(key, other))),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// From an installed copy of [version], else the thumbnail kept for it.
  Future<Uint8List?> _bytes(String key, String version) async {
    final folder = widget.folderOf(version);
    if (folder != null) {
      final b = await readPicture(folder, key);
      if (b != null) return b;
    }
    final thumb = File(thumbPath(widget.baseKey, version, key));
    return thumb.existsSync() ? thumb.readAsBytes() : null;
  }
}

class _Tile extends StatefulWidget {
  final String picture;
  final String? caption;
  final String thumb;
  final String? folder;
  final VoidCallback onOpen;
  const _Tile({required this.picture, required this.thumb, required this.folder, required this.onOpen, this.caption});

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  Future<Uint8List?>? _image;

  @override
  void initState() {
    super.initState();
    final thumb = File(widget.thumb);
    if (thumb.existsSync()) {
      _image = thumb.readAsBytes();
    } else if (widget.folder != null) {
      // Read and shrunk in the background; only for pictures on screen.
      _image = readPicture(widget.folder!, widget.picture).then((b) => b == null ? null : thumbnail(b, width: 240));
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onOpen,
      borderRadius: AppRadius.borderMd,
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: AppRadius.borderMd,
              child: Container(
                width: 168,
                height: 95,
                color: AppColors.bgSecondary,
                alignment: Alignment.center,
                child: _image == null
                    ? Icon(Icons.image_not_supported_outlined, size: 20, color: AppColors.textMuted)
                    : FutureBuilder<Uint8List?>(
                        future: _image,
                        builder: (context, snap) => snap.data == null
                            ? Icon(Icons.image_outlined, size: 20, color: AppColors.textMuted)
                            : Image.memory(snap.data!, width: 168, height: 95, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(p.basename(widget.picture),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(fontSize: 11.5, color: AppColors.textSecondary)),
            if (widget.caption != null)
              Text(widget.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _FullPicture extends StatefulWidget {
  final String label;
  final Future<Uint8List?> Function() load;
  const _FullPicture({required this.label, required this.load});

  @override
  State<_FullPicture> createState() => _FullPictureState();
}

class _FullPictureState extends State<_FullPicture> {
  late final _bytes = widget.load();
  String get label => widget.label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.ui(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Flexible(
          child: FutureBuilder<Uint8List?>(
            future: _bytes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(width: 320, height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              if (snap.data == null) {
                return SizedBox(
                  width: 320,
                  height: 180,
                  child: Center(
                    child: Text("This version isn't installed and no thumbnail was kept.",
                        textAlign: TextAlign.center, style: AppText.body(color: AppColors.textMuted)),
                  ),
                );
              }
              return Image.memory(snap.data!, fit: BoxFit.contain);
            },
          ),
        ),
      ],
    );
  }
}

/// Lines by scene: removed ones struck through, rewritten ones before and
/// after, added ones plain. Scenes start folded when there are many.
class _LinesView extends StatefulWidget {
  final List<RecordLine> removed;
  final List<Rewrite> rewritten;
  final List<RecordLine> added;
  final List<String> goneScenes;

  /// For "no longer in the game": the last version that had each line.
  final Map<RecordLine, String>? lastIn;

  const _LinesView({required this.removed, required this.rewritten, required this.added, required this.goneScenes, this.lastIn});

  @override
  State<_LinesView> createState() => _LinesViewState();
}

class _LinesViewState extends State<_LinesView> {
  final _open = <String>{};
  var _scenesShown = 30;
  var _showAdded = false;

  @override
  Widget build(BuildContext context) {
    final scenes = <String, List<Widget>>{};
    final counts = <String, int>{};
    void add(String scene, Widget w) {
      scenes.putIfAbsent(scene, () => []).add(w);
      counts[scene] = (counts[scene] ?? 0) + 1;
    }

    for (final l in widget.removed) {
      add(l.scene, _line(l, struck: true, trailing: widget.lastIn == null ? null : 'last in ${fmtVersion(widget.lastIn![l]!)}'));
    }
    for (final r in widget.rewritten) {
      add(r.before.scene, _rewrite(r));
    }
    if (_showAdded) {
      for (final l in widget.added) {
        add(l.scene, _line(l));
      }
    }
    final names = scenes.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final gone = widget.goneScenes.toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.added.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: VpButton(
                label: _showAdded ? 'Hide the ${fmtCount(widget.added.length)} new lines' : 'Also show the ${fmtCount(widget.added.length)} new lines',
                small: true,
                tone: VpTone.quiet,
                onTap: () => setState(() => _showAdded = !_showAdded),
              ),
            ),
          ),
        if (names.isEmpty) Text('Nothing removed or rewritten.', style: AppText.body(color: AppColors.textMuted)),
        for (final s in names.take(_scenesShown))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _open.contains(s) ? _open.remove(s) : _open.add(s)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(_open.contains(s) || names.length <= 3 ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(s.isEmpty ? 'Outside any scene' : s, style: AppText.mono(fontSize: 12.5, color: AppColors.textPrimary)),
                      const SizedBox(width: 8),
                      Text(fmtCount(counts[s]!), style: AppText.mono(fontSize: 12, color: AppColors.textMuted)),
                      if (gone.contains(s)) ...[
                        const SizedBox(width: 8),
                        Text('whole scene gone', style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ]),
                  ),
                ),
                if (_open.contains(s) || names.length <= 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, bottom: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: scenes[s]!.take(200).toList()),
                  ),
              ],
            ),
          ),
        if (names.length > _scenesShown)
          Align(
            alignment: Alignment.centerLeft,
            child: VpButton(
              label: 'Show more scenes',
              small: true,
              tone: VpTone.quiet,
              onTap: () => setState(() => _scenesShown += 60),
            ),
          ),
      ],
    );
  }

  Widget _who(RecordLine l) {
    // A speaker written as a plain string ("Moonbox") shows without quotes.
    final who = l.isChoice ? 'Choice' : l.who.replaceAll(RegExp(r'''^["']|["']$'''), '');
    return SizedBox(
      width: 90,
      child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(fontSize: 12, color: AppColors.textMuted)),
    );
  }

  Widget _line(RecordLine l, {bool struck = false, String? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _who(l),
            Expanded(
              child: SelectableText(
                _plain(l.what),
                style: AppText.ui(fontSize: 13.5, color: struck ? AppColors.textSecondary : AppColors.textPrimary).copyWith(
                  decoration: struck ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.textMuted,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Text(trailing, style: AppText.ui(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ],
        ),
      );

  Widget _rewrite(Rewrite r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _who(r.before),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    _plain(r.before.what),
                    style: AppText.ui(fontSize: 13.5, color: AppColors.textSecondary)
                        .copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.textMuted),
                  ),
                  SelectableText(_plain(r.after.what), style: AppText.ui(fontSize: 13.5, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A line without Ren'Py's text tags ({b}, {i}, {w}...), as a player reads it.
String _plain(String what) => what.replaceAll(RegExp(r'\{[^{}]*\}'), '');
