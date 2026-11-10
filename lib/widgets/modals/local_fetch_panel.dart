import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../models/game_group.dart';
import '../../providers/library_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/game_detect.dart';
import '../../services/renpy_local.dart';
import '../../services/scanner_service.dart';
import '../../theme.dart';
import '../common/kit.dart';

/// Fetch Metadata's Local source (#25): the game's own files, read on this
/// PC, with nothing sent anywhere, so it works in Lockdown. Ren'Py for now.
/// Always a preview first: nothing changes until Apply.
class LocalFetchPanel extends ConsumerStatefulWidget {
  final GameGroup group;
  const LocalFetchPanel({super.key, required this.group});

  @override
  ConsumerState<LocalFetchPanel> createState() => _LocalFetchPanelState();
}

class _LocalFetchPanelState extends ConsumerState<LocalFetchPanel> {
  LocalGameInfo? _info;
  bool _reading = true;
  bool _useTitle = true, _useVersion = true, _useCover = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final v = widget.group.latestVersion;
    if (v == null || v.engine != GameEngine.renpy) {
      setState(() => _reading = false);
      return;
    }
    final folder = v.folderPath.path;
    LocalGameInfo info;
    try {
      info = await Isolate.run(_localFetchJob(folder));
    } catch (e) {
      debugPrint('Local fetch failed for $folder: $e');
      info = const LocalGameInfo();
    }
    if (!mounted) return;
    final meta = v.metadata;
    final hasCover = Directory(p.join(folder, '.vnpf')).existsSync() &&
        Directory(p.join(folder, '.vnpf')).listSync().any((f) => p.basename(f.path).toLowerCase().startsWith('cover.'));
    setState(() {
      _info = info;
      _reading = false;
      // Don't offer to replace what's already there unless asked.
      _useTitle = info.title != null && (meta['title'] as String? ?? '').isEmpty;
      _useVersion = info.version != null && v.versionStr.isEmpty;
      _useCover = info.cover != null && !hasCover;
    });
  }

  Future<void> _apply() async {
    final v = widget.group.latestVersion, info = _info;
    if (v == null || info == null) return;
    setState(() => _applying = true);
    try {
      final meta = Map<String, dynamic>.from(loadGameMetadata(v.folderPath));
      if (_useTitle && info.title != null) meta['title'] = info.title;
      if (_useVersion && info.version != null) meta['local_version'] = info.version;
      meta['local_fetched'] = DateTime.now().toIso8601String();
      await saveGameMetadata(v.folderPath, meta);
      final vnpf = Directory(p.join(v.folderPath.path, '.vnpf'))..createSync(recursive: true);
      if (_useCover && info.cover != null) {
        for (final f in vnpf.listSync().whereType<File>()) {
          if (p.basename(f.path).toLowerCase().startsWith('cover.')) f.deleteSync();
        }
        File(p.join(vnpf.path, 'cover${info.coverExt}')).writeAsBytesSync(info.cover!);
      }
      if (info.icon != null) File(p.join(vnpf.path, 'icon.png')).writeAsBytesSync(info.icon!);
      await ref.read(libraryProvider.notifier).scan();
      if (!mounted) return;
      ref.read(notificationProvider.notifier).success('Read from the game files');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ref.read(notificationProvider.notifier).error('Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.group.latestVersion;
    if (_reading) {
      return Center(child: Text('Reading the game files…', style: AppText.ui(fontSize: 12, color: AppColors.textMuted)));
    }
    if (v == null || v.engine != GameEngine.renpy) {
      return _Note('Local fetch reads Ren\'Py games for now. Other engines come later.');
    }
    final info = _info;
    if (info == null || info.isEmpty) {
      return _Note('Nothing readable in this game\'s files. Some developers pack their games in their own '
          'format; the online sources can still help.');
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgInput,
                  borderRadius: AppRadius.borderSm,
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: info.cover == null
                    ? Center(child: Text('No menu art', style: AppText.ui(fontSize: 12, color: AppColors.textMuted)))
                    : Image.memory(info.cover!, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From this game\'s files', style: AppText.heading()),
                const SizedBox(height: 4),
                Text('Read on this PC; nothing goes online. Tick what to use.',
                    style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 14),
                _Pick(
                  label: 'Title',
                  value: info.title,
                  on: _useTitle,
                  onChanged: (b) => setState(() => _useTitle = b),
                ),
                _Pick(
                  label: 'Version',
                  value: info.version,
                  note: v.versionStr.isEmpty
                      ? 'The folder name has no version, so this one is used.'
                      : 'The folder name already gives ${v.versionStr}, which stays.',
                  on: _useVersion,
                  onChanged: (b) => setState(() => _useVersion = b),
                ),
                _Pick(
                  label: 'Cover',
                  value: info.cover == null ? null : 'The main menu art',
                  on: _useCover,
                  onChanged: (b) => setState(() => _useCover = b),
                ),
                const SizedBox(height: 16),
                VpButton(
                  label: 'Apply',
                  tone: VpTone.primary,
                  small: true,
                  busy: _applying,
                  onTap: _applying || !(_useTitle || _useVersion || _useCover) ? null : _apply,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pick extends StatelessWidget {
  final String label;
  final String? value;
  final String? note;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _Pick({required this.label, required this.value, this.note, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value != null && on,
              onChanged: value == null ? null : (b) => onChanged(b ?? false),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.ui(fontSize: 11, color: AppColors.textMuted)),
                    Text(value ?? 'Not found', style: AppText.ui(fontSize: 13, color: value == null ? AppColors.textMuted : AppColors.textPrimary)),
                    if (note != null && value != null)
                      Text(note!, style: AppText.ui(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: AppText.ui(fontSize: 13, color: AppColors.textMuted)),
        ),
      );
}

/// The background job, made outside the widget so it carries only the
/// folder: a closure made in a State method also carries the State, which
/// can't be sent to another isolate.
LocalGameInfo Function() _localFetchJob(String folder) => () => localFetch(Directory(folder));
