import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../theme.dart';
import '../models/archive_item.dart';
import '../models/game_group.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

// ═══════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════

enum _ExStatus { idle, queued, running, done, failed }

class _ExState {
  final _ExStatus status;
  final double progress;
  final String? error;
  final String? currentFile;
  final int filesCompleted;
  final int totalFiles;
  const _ExState({
    this.status = _ExStatus.idle,
    this.progress = 0,
    this.error,
    this.currentFile,
    this.filesCompleted = 0,
    this.totalFiles = 0,
  });
  bool get isActive => status == _ExStatus.running;
  bool get isDone   => status == _ExStatus.done;
  bool get isFailed => status == _ExStatus.failed;
  bool get isQueued => status == _ExStatus.queued;
}

// Per-path extraction state
final _exProvider = StateProvider<Map<String, _ExState>>((ref) => {});
// Ordered extraction queue (paths to extract, not yet started)
final _queueProvider = StateProvider<List<String>>((ref) => []);

// ═══════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});
  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

enum _SortKey { name, size, type, modified, status }
enum _SortDir { asc, desc }

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  String _query        = '';
  ArchiveType? _typeFilter;
  bool _unmatchedOnly  = false;
  _SortKey _sortKey    = _SortKey.modified;
  _SortDir _sortDir    = _SortDir.desc;
  String?  _selectedPath;
  bool _queueCollapsed     = false;
  bool _completedCollapsed = false;

  // ── Data helpers ──────────────────────────────────────────────────

  List<ArchiveItem> _allArchives(List<GameGroup> groups) {
    final all = <ArchiveItem>[];
    for (final g in groups) { all.addAll(g.archives); }
    return all;
  }

  List<ArchiveItem> _filtered(List<ArchiveItem> all) {
    return all.where((a) {
      if (_query.isNotEmpty &&
          !a.name.toLowerCase().contains(_query.toLowerCase())) { return false; }
      if (_typeFilter != null && a.type != _typeFilter) return false;
      if (_unmatchedOnly && a.matchedFolder != null) return false;
      return true;
    }).toList()
      ..sort(_comparator);
  }

  int Function(ArchiveItem, ArchiveItem) get _comparator {
    int cmp(ArchiveItem a, ArchiveItem b) {
      switch (_sortKey) {
        case _SortKey.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortKey.size:
          return (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
        case _SortKey.type:
          return a.type.label.compareTo(b.type.label);
        case _SortKey.modified:
          return a.modTime.compareTo(b.modTime);
        case _SortKey.status:
          final aEx = _isExtracted(a) ? 1 : 0;
          final bEx = _isExtracted(b) ? 1 : 0;
          return aEx.compareTo(bEx);
      }
    }
    return _sortDir == _SortDir.asc
        ? (a, b) => cmp(a, b)
        : (a, b) => cmp(b, a);
  }

  bool _isExtracted(ArchiveItem item) {
    final dir = Directory(p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    ));
    return dir.existsSync();
  }

  void _toggleSort(_SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortDir = _sortDir == _SortDir.asc ? _SortDir.desc : _SortDir.asc;
      } else {
        _sortKey = key;
        _sortDir = _SortDir.asc;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final libState     = ref.watch(libraryProvider);
    final settings     = ref.watch(settingsProvider);
    final exStates     = ref.watch(_exProvider);
    ref.watch(_queueProvider);
    final all          = _allArchives(libState.groups);
    final visible      = _filtered(all);
    final totalBytes   = all.fold<int>(0, (s, a) => s + (a.sizeBytes ?? 0));
    final extractedAll = all.where(_isExtracted).toList();
    // Completed = any archive whose extracted folder exists on disk.
    // Using filesystem as source of truth so the list survives app restarts.
    final completed    = all.where(_isExtracted).toList();
    final queued       = all.where((a) => exStates[a.archivePath.path]?.isQueued == true).toList();
    final activeEntry  = exStates.entries.where((e) => e.value.isActive).firstOrNull;
    final selectedItem = visible.where((a) => a.archivePath.path == _selectedPath).firstOrNull;

    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── 1. Header bar ──────────────────────────────────────────
          _ArchiveHeader(
            query: _query,
            typeFilter: _typeFilter,
            unmatchedOnly: _unmatchedOnly,
            onQueryChanged: (q) => setState(() => _query = q),
            onTypeFilter: (t) => setState(() { _typeFilter = t; }),
            onUnmatchedOnly: (v) => setState(() => _unmatchedOnly = v),
            onRefresh: () => ref.read(libraryProvider.notifier).scan(),
          ),

          // ── 2. Extraction Hero ─────────────────────────────────────
          _ExtractionHero(activeEntry: activeEntry),

          // ── 3. Up Next Queue ───────────────────────────────────────
          if (queued.isNotEmpty)
            _QueueSection(
              title: 'Up Next',
              count: queued.length,
              collapsed: _queueCollapsed,
              onToggle: () => setState(() => _queueCollapsed = !_queueCollapsed),
              children: queued.map((item) => _QueueRow(
                name: item.name,
                onCancel: () => _dequeue(item),
              )).toList(),
            ),

          // ── 4. Completed Queue ─────────────────────────────────────
          if (completed.isNotEmpty)
            _QueueSection(
              title: 'Completed',
              count: completed.length,
              collapsed: _completedCollapsed,
              onToggle: () => setState(() => _completedCollapsed = !_completedCollapsed),
              trailing: Row(
                children: [
                  _QueueActionBtn(
                    label: 'Clear All',
                    onTap: () => _clearCompleted(completed, exStates),
                  ),
                  const SizedBox(width: 6),
                  _QueueActionBtn(
                    label: 'Clear & Delete All',
                    danger: true,
                    onTap: () => _clearAndDeleteCompleted(completed, exStates),
                  ),
                ],
              ),
              children: completed.map((item) => _QueueRow(
                name: item.name,
                isCompleted: true,
                onCancel: () => _clearSingleCompleted(item, exStates),
              )).toList(),
            ),

          // ── 5. Table ───────────────────────────────────────────────
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(hasLibrary: settings.libraryDir.isNotEmpty)
                : Column(
                    children: [
                      // Sticky header
                      _TableHeader(
                        sortKey: _sortKey,
                        sortDir: _sortDir,
                        onSort: _toggleSort,
                      ),
                      // Rows
                      Expanded(
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemExtent: 44,
                          itemBuilder: (ctx, i) {
                            final item = visible[i];
                            final exState = exStates[item.archivePath.path] ?? const _ExState();
                            final isSelected = item.archivePath.path == _selectedPath;
                            final isExtracted = _isExtracted(item);
                            return _ArchiveRow(
                              item: item,
                              exState: exState,
                              isSelected: isSelected,
                              isExtracted: isExtracted,
                              onTap: () => setState(() =>
                                _selectedPath = isSelected ? null : item.archivePath.path),
                              onRightClick: (pos) => _showContextMenu(ctx, pos, item, isExtracted, exState),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),

          // ── 6. Summary bar ─────────────────────────────────────────
          _SummaryBar(
            total: all.length,
            totalBytes: totalBytes,
            extractedCount: extractedAll.length,
          ),

          // ── 7. Bottom action bar ───────────────────────────────────
          _ActionBar(
            selected: selectedItem,
            exState: selectedItem != null
                ? (exStates[selectedItem.archivePath.path] ?? const _ExState())
                : null,
            isExtracted: selectedItem != null ? _isExtracted(selectedItem) : false,
            onExtract: selectedItem != null ? () => _enqueue(selectedItem) : null,
            onDeleteArchive: selectedItem != null ? () => _deleteArchive(selectedItem) : null,
            onOpenFolder: selectedItem != null ? () => _openFolder(selectedItem) : null,
            onAssignPatch: selectedItem != null ? () => _showAssignDialog(selectedItem) : null,
            onDeleteExtracted: (selectedItem != null && _isExtracted(selectedItem))
                ? () => _deleteSingleExtracted(selectedItem)
                : null,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // CONTEXT MENU
  // ═══════════════════════════════════════════════════════════════════

  void _showContextMenu(BuildContext context, Offset pos, ArchiveItem item,
      bool isExtracted, _ExState exState) {
    setState(() => _selectedPath = item.archivePath.path);
    final canExtract = item.type == ArchiveType.zip || item.type == ArchiveType.rar;

    showMenu<String>(
      context: context,
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderSm,
        side: const BorderSide(color: AppColors.borderLight),
      ),
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (canExtract)
          _ctxItem('extract', Icons.unarchive_outlined, '📦  Extract',
              enabled: exState.status != _ExStatus.running && exState.status != _ExStatus.queued),
        _ctxItem('delete_archive', Icons.delete_outline, '🗑  Delete Archive'),
        _ctxItem('open_folder', Icons.folder_open_outlined, '📂  Open Folder'),
        _ctxItem('assign_patch', Icons.extension_outlined, '🔗  Assign Patch for…'),
        if (isExtracted) ...[
          const PopupMenuDivider(height: 1),
          _ctxItem('delete_extracted', Icons.delete_sweep_outlined, '🗑  Delete Extracted'),
          _ctxItem('clear_and_delete', Icons.delete_forever_outlined, '⚡  Clear & Delete Archive',
              danger: true),
        ],
        const PopupMenuDivider(height: 1),
        _ctxItem('copy_path', Icons.copy_outlined, '📋  Copy Path'),
      ],
    ).then((val) {
      switch (val) {
        case 'extract':          _enqueue(item);
        case 'delete_archive':   _deleteArchive(item);
        case 'open_folder':      _openFolder(item);
        case 'assign_patch':     _showAssignDialog(item);
        case 'delete_extracted': _deleteSingleExtracted(item);
        case 'clear_and_delete': _clearAndDeleteSingle(item);
        case 'copy_path':
          // ignore: use_build_context_synchronously
          _copyPath(item);
      }
    });
  }

  PopupMenuItem<String> _ctxItem(String val, IconData icon, String label,
      {bool enabled = true, bool danger = false}) {
    return PopupMenuItem<String>(
      value: val,
      enabled: enabled,
      padding: EdgeInsets.zero,
      child: _CtxMenuRow(icon: icon, label: label, danger: danger, enabled: enabled),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // QUEUE / EXTRACTION LOGIC
  // ═══════════════════════════════════════════════════════════════════

  void _enqueue(ArchiveItem item) {
    final key = item.archivePath.path;
    final exNotifier = ref.read(_exProvider.notifier);
    final qNotifier  = ref.read(_queueProvider.notifier);

    // Already running or queued — ignore
    final current = ref.read(_exProvider)[key];
    if (current?.isActive == true || current?.isQueued == true) return;

    final isAnythingRunning = ref.read(_exProvider).values.any((e) => e.isActive);

    if (isAnythingRunning) {
      // Add to queue
      exNotifier.state = {...exNotifier.state, key: const _ExState(status: _ExStatus.queued)};
      qNotifier.state  = [...qNotifier.state, key];
    } else {
      // Start immediately
      _startExtraction(item);
    }
  }

  void _dequeue(ArchiveItem item) {
    final key = item.archivePath.path;
    final exNotifier = ref.read(_exProvider.notifier);
    final qNotifier  = ref.read(_queueProvider.notifier);
    exNotifier.state = Map.of(exNotifier.state)..remove(key);
    qNotifier.state  = qNotifier.state.where((p) => p != key).toList();
  }

  void _startExtraction(ArchiveItem item) async {
    final key        = item.archivePath.path;
    final exNotifier = ref.read(_exProvider.notifier);
    final qNotifier  = ref.read(_queueProvider.notifier);

    exNotifier.state = {...exNotifier.state, key: const _ExState(status: _ExStatus.running)};

    try {
      if (item.type == ArchiveType.zip) {
        await _extractZip(item, exNotifier);
      } else if (item.type == ArchiveType.rar) {
        await _extractRar(item, exNotifier);
      } else {
        throw 'Extraction not supported for ${item.type.label} files.';
      }
      exNotifier.state = {
        ...exNotifier.state,
        key: const _ExState(status: _ExStatus.done, progress: 1.0),
      };
      ref.read(libraryProvider.notifier).scan();
    } catch (e) {
      exNotifier.state = {
        ...exNotifier.state,
        key: _ExState(status: _ExStatus.failed, error: e.toString()),
      };
    }

    // Process next in queue
    final nextPath = qNotifier.state.firstOrNull;
    if (nextPath != null && mounted) {
      qNotifier.state = qNotifier.state.skip(1).toList();
      final allItems = _allArchives(ref.read(libraryProvider).groups);
      final nextItem = allItems.where((a) => a.archivePath.path == nextPath).firstOrNull;
      if (nextItem != null) _startExtraction(nextItem);
    }
  }

  Future<void> _extractZip(
      ArchiveItem item, StateController<Map<String, _ExState>> notifier) async {
    final destDir = p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    );
    Directory(destDir).createSync(recursive: true);
    final key     = item.archivePath.path;
    final bytes   = await item.archivePath.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final total   = archive.files.length;
    var done = 0;

    for (final file in archive.files) {
      if (file.isFile) {
        await compute(_writeFile, (p.join(destDir, file.name), file.content as List<int>));
      }
      done++;
      if (mounted) {
        notifier.state = {
          ...notifier.state,
          key: _ExState(
            status: _ExStatus.running,
            progress: done / total.clamp(1, total),
            currentFile: p.basename(file.name),
            filesCompleted: done,
            totalFiles: total,
          ),
        };
      }
      await Future.delayed(Duration.zero);
    }

    final settings = ref.read(settingsProvider);
    if (settings.deleteAfterExtract) await item.archivePath.delete();
  }

  Future<void> _extractRar(
      ArchiveItem item, StateController<Map<String, _ExState>> notifier) async {
    const candidates = [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];
    final sevenZip = candidates.firstWhere(
      (c) => File(c).existsSync(),
      orElse: () => '',
    );
    if (sevenZip.isEmpty) throw '7-Zip not found. Install 7-Zip to extract RAR archives.';

    final destDir = p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    );
    Directory(destDir).createSync(recursive: true);
    final result = await Process.run(sevenZip, ['x', item.archivePath.path, '-o$destDir', '-y']);
    if (result.exitCode != 0) throw '7-Zip extraction failed:\n${result.stderr}';

    final settings = ref.read(settingsProvider);
    if (settings.deleteAfterExtract) await item.archivePath.delete();
  }

  static Future<void> _writeFile((String, List<int>) args) async {
    final (path, bytes) = args;
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsBytesSync(bytes);
  }

  // ═══════════════════════════════════════════════════════════════════
  // DELETION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _deleteArchive(ArchiveItem item) async {
    final ok = await _confirmDialog(
      title: 'Delete Archive?',
      body: 'Delete "${item.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await item.archivePath.delete();
      ref.read(libraryProvider.notifier).scan();
    } catch (e) { debugPrint('deleteArchive: $e'); }
  }

  Future<void> _deleteSingleExtracted(ArchiveItem item) async {
    final dirPath = _extractedDirPath(item);
    try {
      await compute(_deleteDir, dirPath);
      if (mounted) setState(() {});
    } catch (e) { debugPrint('deleteSingleExtracted: $e'); }
  }

  Future<void> _clearAndDeleteSingle(ArchiveItem item) async {
    final ok = await _confirmDialog(
      title: 'Clear & Delete?',
      body: 'Delete the extracted folder and the archive file "${item.name}"?\nThis cannot be undone.',
      confirmLabel: 'Clear & Delete',
    );
    if (!ok) return;
    try {
      await compute(_deleteDirsAndFiles, ([_extractedDirPath(item)], [item.archivePath.path]));
      if (mounted) {
        ref.read(libraryProvider.notifier).scan();
        setState(() {});
      }
    } catch (e) { debugPrint('clearAndDeleteSingle: $e'); }
  }


  void _clearCompleted(List<ArchiveItem> items, Map<String, _ExState> exStates) {
    final notifier = ref.read(_exProvider.notifier);
    final updated = Map<String, _ExState>.from(notifier.state);
    for (final item in items) {
      updated.remove(item.archivePath.path);
    }
    notifier.state = updated;
  }

  Future<void> _clearAndDeleteCompleted(
      List<ArchiveItem> items, Map<String, _ExState> exStates) async {
    if (items.isEmpty) return;
    final ok = await _confirmDialog(
      title: 'Clear & Delete All Completed?',
      body: 'Delete ${items.length} extracted folder(s) and their archive files?\nThis cannot be undone.',
      confirmLabel: 'Clear & Delete All',
    );
    if (!ok) return;
    final dirs  = items.map(_extractedDirPath).toList();
    final files = items.map((i) => i.archivePath.path).toList();
    await compute(_deleteDirsAndFiles, (dirs, files));
    _clearCompleted(items, exStates);
    if (mounted) {
      ref.read(libraryProvider.notifier).scan();
      setState(() {});
    }
  }

  void _clearSingleCompleted(ArchiveItem item, Map<String, _ExState> exStates) {
    final notifier = ref.read(_exProvider.notifier);
    notifier.state = Map.of(notifier.state)..remove(item.archivePath.path);
  }

  void _openFolder(ArchiveItem item) {
    final dir = _extractedDirPath(item);
    final target = Directory(dir).existsSync() ? dir : p.dirname(item.archivePath.path);
    Process.run('explorer', [target]);
  }

  void _copyPath(ArchiveItem item) {
    // No clipboard package — just print for now
    debugPrint('Path: ${item.archivePath.path}');
  }

  // ═══════════════════════════════════════════════════════════════════
  // ASSIGN PATCH
  // ═══════════════════════════════════════════════════════════════════

  void _showAssignDialog(ArchiveItem item) {
    final groups = ref.read(libraryProvider).groups;
    showDialog<void>(
      context: context,
      builder: (_) => _AssignPatchDialog(item: item, groups: groups),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  String _extractedDirPath(ArchiveItem item) => p.join(
    p.dirname(item.archivePath.path),
    p.basenameWithoutExtension(item.archivePath.path),
  );

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderMd,
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(title,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: Text(body,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary,
                height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Background isolate helpers ──────────────────────────────────

  static Future<void> _deleteDir(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }


  static Future<void> _deleteDirsAndFiles((List<String>, List<String>) args) async {
    final (dirs, files) = args;
    for (final path in dirs) {
      final dir = Directory(path);
      if (dir.existsSync()) try { dir.deleteSync(recursive: true); } catch (_) {}
    }
    for (final path in files) {
      final file = File(path);
      if (file.existsSync()) try { file.deleteSync(); } catch (_) {}
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// ARCHIVE HEADER
// ═══════════════════════════════════════════════════════════════════

class _ArchiveHeader extends StatefulWidget {
  final String query;
  final ArchiveType? typeFilter;
  final bool unmatchedOnly;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ArchiveType?> onTypeFilter;
  final ValueChanged<bool> onUnmatchedOnly;
  final VoidCallback onRefresh;

  const _ArchiveHeader({
    required this.query,
    required this.typeFilter,
    required this.unmatchedOnly,
    required this.onQueryChanged,
    required this.onTypeFilter,
    required this.onUnmatchedOnly,
    required this.onRefresh,
  });

  @override
  State<_ArchiveHeader> createState() => _ArchiveHeaderState();
}

class _ArchiveHeaderState extends State<_ArchiveHeader> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Subtitle
          Text(
            'Archives (.zip, .rar, .rpa, .rpy) — manage & extract',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          // Type filters
          for (final type in [null, ArchiveType.zip, ArchiveType.rar, ArchiveType.rpa])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Chip(
                label: type == null ? 'All' : type.label,
                active: widget.typeFilter == type,
                onTap: () => widget.onTypeFilter(type),
              ),
            ),

          const SizedBox(width: 8),

          // Unmatched toggle
          _Chip(
            label: 'Unmatched',
            active: widget.unmatchedOnly,
            onTap: () => widget.onUnmatchedOnly(!widget.unmatchedOnly),
          ),

          const SizedBox(width: 12),

          // Search
          SizedBox(
            width: 190,
            height: 28,
            child: TextField(
              onChanged: widget.onQueryChanged,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search archives…',
                hintStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                isDense: true,
                prefixIcon:
                    const Icon(Icons.search, size: 13, color: AppColors.textMuted),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Refresh button
          _HeaderBtn(
            label: '⟳  Refresh',
            onTap: widget.onRefresh,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// EXTRACTION HERO
// ═══════════════════════════════════════════════════════════════════

class _ExtractionHero extends StatelessWidget {
  final MapEntry<String, _ExState>? activeEntry;
  const _ExtractionHero({required this.activeEntry});

  @override
  Widget build(BuildContext context) {
    if (activeEntry == null) return _buildIdle();
    return _buildActive(activeEntry!);
  }

  Widget _buildIdle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📦', style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Text(
            'No active extraction — select an archive and press Extract.\nFiles are extracted into a folder next to the archive. The library rescans automatically when done.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(MapEntry<String, _ExState> entry) {
    final ex       = entry.value;
    final fileName = p.basename(entry.key);
    final pct      = (ex.progress * 100);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          // Gradient background glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.08),
                    AppColors.bgCard.withValues(alpha: 0.97),
                    AppColors.bgCard,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Left: stats + status lines
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats row
                      Row(
                        children: [
                          _ExStat(label: 'READ',
                              value: '${(ex.filesCompleted * 0.5).toStringAsFixed(1)} MB/s'),
                          const SizedBox(width: 20),
                          _ExStat(label: 'WRITE',
                              value: '${(ex.filesCompleted * 0.3).toStringAsFixed(1)} MB/s'),
                          const SizedBox(width: 20),
                          _ExStat(label: 'DISK',
                              value: '${(ex.filesCompleted * 2)} MB'),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Status lines
                      Text(
                        ex.currentFile != null
                            ? 'Extracting: ${ex.currentFile}'
                            : 'Preparing…',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (ex.totalFiles > 0)
                        Text(
                          'File ${ex.filesCompleted} of ${ex.totalFiles}',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 32),

                // Right: progress bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              fileName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Progress bar
                      ClipRRect(
                        borderRadius: AppRadius.borderXl,
                        child: SizedBox(
                          height: 10,
                          child: LinearProgressIndicator(
                            value: ex.progress,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.06),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Meta
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${ex.filesCompleted} / ${ex.totalFiles} files',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: AppColors.textMuted),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}% complete',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExStat extends StatelessWidget {
  final String label;
  final String value;
  const _ExStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// QUEUE SECTIONS
// ═══════════════════════════════════════════════════════════════════

class _QueueSection extends StatelessWidget {
  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget? trailing;
  final List<Widget> children;

  const _QueueSection({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            hoverColor: AppColors.bgHover,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '($count)',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more,
                        size: 14, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          // Body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: collapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Column(children: children),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final String name;
  final bool isCompleted;
  final VoidCallback onCancel;

  const _QueueRow({
    required this.name,
    required this.onCancel,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Icon(
            isCompleted ? Icons.check_circle_outline : Icons.hourglass_empty,
            size: 12,
            color: isCompleted ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isCompleted ? AppColors.textSecondary : AppColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _SmallIconBtn(
            icon: Icons.close,
            onTap: onCancel,
            tooltip: isCompleted ? 'Dismiss' : 'Remove from queue',
          ),
        ],
      ),
    );
  }
}

class _QueueActionBtn extends StatefulWidget {
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _QueueActionBtn({required this.label, required this.onTap, this.danger = false});
  @override
  State<_QueueActionBtn> createState() => _QueueActionBtnState();
}

class _QueueActionBtnState extends State<_QueueActionBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? AppColors.danger : AppColors.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered ? color.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(
              color: _hovered ? color : AppColors.border,
            ),
            borderRadius: AppRadius.borderXs,
          ),
          child: Text(widget.label,
              style: GoogleFonts.inter(
                  fontSize: 10,
                  color: _hovered ? color : AppColors.textMuted)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TABLE
// ═══════════════════════════════════════════════════════════════════

class _TableHeader extends StatelessWidget {
  final _SortKey sortKey;
  final _SortDir sortDir;
  final ValueChanged<_SortKey> onSort;

  const _TableHeader({
    required this.sortKey,
    required this.sortDir,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 0),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Left border placeholder
          const SizedBox(width: 3),
          _TH('NAME',     _SortKey.name,     flex: 4, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('SIZE',     _SortKey.size,     width: 80, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('TYPE',     _SortKey.type,     width: 70, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('MODIFIED', _SortKey.modified, width: 100, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('STATUS',   _SortKey.status,   width: 130, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
        ],
      ),
    );
  }
}

class _TH extends StatefulWidget {
  final String label;
  final _SortKey key_;
  final double? width;
  final int flex;
  final _SortKey sortKey;
  final _SortDir sortDir;
  final ValueChanged<_SortKey> onSort;

  const _TH(this.label, this.key_, {
    this.width,
    this.flex = 1,
    required this.sortKey,
    required this.sortDir,
    required this.onSort,
  });

  @override
  State<_TH> createState() => _THState();
}

class _THState extends State<_TH> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final isActive = widget.sortKey == widget.key_;
    final color = isActive ? AppColors.accent : (_hovered ? AppColors.textPrimary : AppColors.textMuted);
    final child = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSort(widget.key_),
        child: Container(
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 3),
                Text(
                  widget.sortDir == _SortDir.asc ? '↑' : '↓',
                  style: TextStyle(fontSize: 10, color: AppColors.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return widget.width != null
        ? SizedBox(width: widget.width, child: child)
        : Expanded(flex: widget.flex, child: child);
  }
}

// ── Archive Row ───────────────────────────────────────────────────

class _ArchiveRow extends StatefulWidget {
  final ArchiveItem item;
  final _ExState exState;
  final bool isSelected;
  final bool isExtracted;
  final VoidCallback onTap;
  final void Function(Offset) onRightClick;

  const _ArchiveRow({
    required this.item,
    required this.exState,
    required this.isSelected,
    required this.isExtracted,
    required this.onTap,
    required this.onRightClick,
  });

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _hovered = false;

  Color get _leftBorder {
    if (widget.isSelected) return AppColors.accent;
    if (widget.isExtracted) return AppColors.accentDim;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ex   = widget.exState;

    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: (d) => widget.onRightClick(d.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.bgActive
                : _hovered
                    ? AppColors.bgHover
                    : Colors.transparent,
            border: Border(
              left: BorderSide(color: _leftBorder, width: 3),
              bottom: const BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Name
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Text(
                    item.name,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              // Size
              SizedBox(
                width: 80,
                child: Text(
                  item.sizeBytes != null ? fmtBytes(item.sizeBytes!) : '—',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),

              // Type badge
              SizedBox(
                width: 70,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TypeBadge(type: item.type),
                ),
              ),

              // Modified
              SizedBox(
                width: 100,
                child: Text(
                  item.modTime.length >= 10
                      ? item.modTime.substring(0, 10)
                      : '—',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ),

              // Status
              SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _StatusBadge(
                    isExtracted: widget.isExtracted,
                    exState: ex,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Type Badge ────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final ArchiveType type;
  const _TypeBadge({required this.type});

  Color get _bg => switch (type) {
    ArchiveType.zip => const Color(0x264A90D9),
    ArchiveType.rar => const Color(0x26A855C8),
    ArchiveType.rpa => const Color(0x264A9E6E),
    ArchiveType.rpy || ArchiveType.py => const Color(0x264A9E6E),
    _ => AppColors.bgHover,
  };

  Color get _fg => switch (type) {
    ArchiveType.zip => const Color(0xFF7AB8ED),
    ArchiveType.rar => const Color(0xFFC28DE0),
    ArchiveType.rpa => AppColors.accentLight,
    ArchiveType.rpy || ArchiveType.py => AppColors.accentLight,
    _ => AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        type.label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: _fg,
        ),
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isExtracted;
  final _ExState exState;
  const _StatusBadge({required this.isExtracted, required this.exState});

  @override
  Widget build(BuildContext context) {
    // Override display based on live extraction state
    if (exState.status == _ExStatus.running) {
      return Row(
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text('Extracting…',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.accent)),
        ],
      );
    }
    if (exState.status == _ExStatus.queued) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('Queued',
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.warning)),
        ],
      );
    }
    if (exState.status == _ExStatus.failed) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Failed',
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.danger),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    if (isExtracted) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text('Extracted',
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.accentLight)),
        ],
      );
    }
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.textMuted.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('Not extracted',
            style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUMMARY BAR
// ═══════════════════════════════════════════════════════════════════

class _SummaryBar extends StatelessWidget {
  final int total;
  final int totalBytes;
  final int extractedCount;
  const _SummaryBar({
    required this.total,
    required this.totalBytes,
    required this.extractedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$total archives · ${fmtBytes(totalBytes)} total'
          '${extractedCount > 0 ? ' · $extractedCount extracted' : ''}',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// BOTTOM ACTION BAR
// ═══════════════════════════════════════════════════════════════════

class _ActionBar extends StatelessWidget {
  final ArchiveItem? selected;
  final _ExState? exState;
  final bool isExtracted;
  final VoidCallback? onExtract;
  final VoidCallback? onDeleteArchive;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onAssignPatch;
  final VoidCallback? onDeleteExtracted;

  const _ActionBar({
    required this.selected,
    required this.exState,
    required this.isExtracted,
    required this.onExtract,
    required this.onDeleteArchive,
    required this.onOpenFolder,
    required this.onAssignPatch,
    required this.onDeleteExtracted,
  });

  bool get _canExtract {
    if (selected == null) return false;
    final t = selected!.type;
    if (t != ArchiveType.zip && t != ArchiveType.rar) return false;
    final s = exState?.status;
    return s != _ExStatus.running && s != _ExStatus.queued;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _BarBtn(
            label: '📦  Extract',
            primary: true,
            enabled: _canExtract,
            onTap: onExtract,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: '🗑  Delete Archive',
            danger: true,
            enabled: selected != null,
            onTap: onDeleteArchive,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: '📂  Open Folder',
            enabled: selected != null,
            onTap: onOpenFolder,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: '🔗  Assign Patch for…',
            enabled: selected != null,
            onTap: onAssignPatch,
          ),
          if (isExtracted) ...[
            const SizedBox(width: 8),
            _BarBtn(
              label: '🗑  Delete Extracted',
              enabled: true,
              onTap: onDeleteExtracted,
            ),
          ],

          const Spacer(),

          if (selected == null)
            Text(
              'Select an archive to enable actions',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _BarBtn extends StatefulWidget {
  final String label;
  final bool enabled;
  final bool primary;
  final bool danger;
  final VoidCallback? onTap;
  const _BarBtn({
    required this.label,
    required this.enabled,
    this.primary = false,
    this.danger = false,
    this.onTap,
  });
  @override
  State<_BarBtn> createState() => _BarBtnState();
}

class _BarBtnState extends State<_BarBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    Color bg, border, text;
    if (!widget.enabled) {
      bg = Colors.transparent;
      border = AppColors.border;
      text = AppColors.textMuted;
    } else if (widget.primary) {
      bg = _hovered
          ? AppColors.accentDim
          : AppColors.accent.withValues(alpha: 0.15);
      border = _hovered ? AppColors.accent : AppColors.accentDim;
      text = AppColors.accentLight;
    } else if (widget.danger) {
      bg = _hovered
          ? AppColors.danger.withValues(alpha: 0.15)
          : Colors.transparent;
      border = _hovered ? AppColors.danger : AppColors.border;
      text = _hovered ? AppColors.danger : AppColors.textSecondary;
    } else {
      bg = _hovered ? AppColors.bgHover : Colors.transparent;
      border = _hovered ? AppColors.borderLight : AppColors.border;
      text = _hovered ? AppColors.textPrimary : AppColors.textSecondary;
    }

    return MouseRegion(
      onEnter: (_) => widget.enabled ? setState(() => _hovered = true) : null,
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: AppRadius.borderSm,
          ),
          child: Text(widget.label,
              style: GoogleFonts.inter(fontSize: 11, color: text)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CONTEXT MENU ROW
// ═══════════════════════════════════════════════════════════════════

class _CtxMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final bool enabled;
  const _CtxMenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textMuted
        : danger
            ? AppColors.danger
            : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inter(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final bool hasLibrary;
  const _EmptyState({required this.hasLibrary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.archive_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            hasLibrary ? 'No archives found in library' : 'Set a library directory in Settings',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            hasLibrary
                ? 'Place .zip, .rar, or .rpa files in your library folder.'
                : 'Archives will appear here once your library is configured.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _Chip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});
  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.accentGlow
                : _hovered
                    ? AppColors.bgHover
                    : AppColors.bgSecondary,
            borderRadius: AppRadius.borderSm,
            border: Border.all(
              color: widget.active ? AppColors.accentDim : AppColors.border,
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
              color: widget.active ? AppColors.accentLight : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HeaderBtn({required this.label, required this.onTap});
  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    const c = AppColors.textSecondary;
    const hc = AppColors.textPrimary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? c.withValues(alpha: 0.1) : Colors.transparent,
            border: Border.all(
              color: _hovered ? c : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _hovered ? hc : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _SmallIconBtn({required this.icon, required this.onTap, this.tooltip});
  @override
  State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Icon(
            widget.icon,
            size: 12,
            color: _hovered ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ASSIGN PATCH DIALOG
// ═══════════════════════════════════════════════════════════════════

class _AssignPatchDialog extends ConsumerStatefulWidget {
  final ArchiveItem item;
  final List<GameGroup> groups;
  const _AssignPatchDialog({required this.item, required this.groups});
  @override
  ConsumerState<_AssignPatchDialog> createState() => _AssignPatchDialogState();
}

class _AssignPatchDialogState extends ConsumerState<_AssignPatchDialog> {
  GameGroup? _selectedGroup;
  String?    _selectedVersion;
  bool       _working = false;
  String?    _error;

  @override
  void initState() {
    super.initState();
    if (widget.item.matchedFolder != null) {
      try {
        _selectedGroup = widget.groups.firstWhere(
            (g) => g.baseKey == widget.item.baseKey);
        _selectedVersion = _selectedGroup?.latestVersion?.versionStr;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text('Assign as Patch',
          style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${widget.item.name}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text('TARGET GAME',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            _Dropdown<GameGroup>(
              value: _selectedGroup,
              hint: 'Select game…',
              items: widget.groups,
              labelOf: (g) => g.effectiveTitle,
              onChanged: (g) => setState(() {
                _selectedGroup = g;
                _selectedVersion = g?.latestVersion?.versionStr;
              }),
            ),
            if (_selectedGroup != null && _selectedGroup!.versions.length > 1) ...[
              const SizedBox(height: 12),
              Text('TARGET VERSION',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              _Dropdown<String>(
                value: _selectedVersion,
                hint: 'Select version…',
                items: _selectedGroup!.versions.map((v) => v.versionStr).toList(),
                labelOf: (v) => v.isEmpty ? 'Unknown' : 'v$v',
                onChanged: (v) => setState(() => _selectedVersion = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _working || _selectedGroup == null ? null : _assign,
          child: _working
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent))
              : Text('Assign',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent)),
        ),
      ],
    );
  }

  Future<void> _assign() async {
    final group      = _selectedGroup!;
    final versionStr = _selectedVersion ?? '';
    final version    = group.versions.firstWhere(
      (v) => v.versionStr == versionStr,
      orElse: () => group.latestVersion!,
    );
    setState(() { _working = true; _error = null; });
    try {
      // .patches/ lives at the ROOT of the game directory, NOT inside game/.
      // Patches are moved INTO game/ to activate them (RenPy loads from there).
      final patchesDir = Directory(
          p.join(version.folderPath.path, '.patches'));
      patchesDir.createSync(recursive: true);
      final metaKey = '${group.baseKey}::${versionStr.isEmpty ? '_' : versionStr}';
      final suffix = p.extension(widget.item.name).toLowerCase();

      if (suffix == '.rpa' || suffix == '.rpy' || suffix == '.rpyc' || suffix == '.py') {
        // Loose file patch — move directly into .patches/
        await _assignLoose(patchesDir, metaKey);
      } else if (suffix == '.zip') {
        // ZIP — extract to temp, move resulting folder into .patches/
        await _assignZip(patchesDir, metaKey);
      } else if (suffix == '.rar') {
        // RAR — extract via 7-Zip, move resulting folder into .patches/
        await _assignRar(patchesDir, metaKey);
      } else {
        throw 'Unsupported patch format: $suffix';
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _working = false; _error = e.toString(); });
    }
  }

  /// Move a loose file (.rpa, .rpy, .rpyc, .py) directly into .patches/.
  Future<void> _assignLoose(Directory patchesDir, String metaKey) async {
    final patchName = _resolveCollision(widget.item.name, patchesDir);
    final dest = File(p.join(patchesDir.path, patchName));
    await widget.item.archivePath.rename(dest.path);
    ref.read(userDataProvider.notifier).setPatchState(metaKey, patchName, false);
  }

  /// The file extensions we consider valid RenPy patch files.
  static const _kPatchExts = {'.rpa', '.rpy', '.rpyc', '.py'};

  /// Extract ZIP — write only recognised patch files directly into .patches/.
  ///
  /// Rules:
  ///   • Only .rpa / .rpy / .rpyc / .py files are extracted — everything else
  ///     (READMEs, images, txts …) is silently skipped.
  ///   • If ANY patch-relevant file sits inside a sub-folder inside the ZIP,
  ///     the whole assign is aborted and the user is asked to apply manually.
  ///     We can't know the creator's intended directory structure, so we don't guess.
  Future<void> _assignZip(Directory patchesDir, String metaKey) async {
    final bytes   = await widget.item.archivePath.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // ── Pass 1: check depth of every patch file ────────────────────────────
    // Accepted:  patch.rpa          (depth 0 — at zip root)
    // Accepted:  game/patch.rpa     (depth 1 — inside exactly one sub-folder)
    // Rejected:  game/ch1/patch.rpy (depth 2+ — too complex, apply manually)
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final ext = p.extension(entry.name).toLowerCase();
      if (!_kPatchExts.contains(ext)) continue;

      // Count path components: "game/patch.rpa".split('/') = ["game","patch.rpa"] → depth 1
      final parts = entry.name.split('/').where((s) => s.isNotEmpty).toList();
      final depth = parts.length - 1; // number of folder levels above the file
      if (depth > 1) {
        throw _complexStructureError(widget.item.name);
      }
    }

    // ── Pass 2: extract patch files flat into .patches/ ─────────────────────
    // Folder prefix (depth-1 case like game/patch.rpa) is stripped — only the
    // filename is used, so .patches/ always contains loose flat files.
    int written = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final ext = p.extension(entry.name).toLowerCase();
      if (!_kPatchExts.contains(ext)) continue;

      final patchName = _resolveCollision(p.basename(entry.name), patchesDir);
      await File(p.join(patchesDir.path, patchName))
          .writeAsBytes(entry.content as List<int>);
      ref.read(userDataProvider.notifier).setPatchState(metaKey, patchName, false);
      written++;
    }

    if (written == 0) {
      throw 'No patch files (.rpa, .rpy, .rpyc, .py) found in ZIP.';
    }
    await widget.item.archivePath.delete();
  }

  /// Extract RAR via 7-Zip to a temp dir, then move only recognised patch files
  /// into .patches/.
  ///
  /// Rules (same as ZIP):
  ///   • Only .rpa / .rpy / .rpyc / .py files are moved — everything else discarded.
  ///   • If ANY patch-relevant file is nested inside a sub-folder inside the RAR,
  ///     the whole assign is aborted and the user is asked to apply manually.
  Future<void> _assignRar(Directory patchesDir, String metaKey) async {
    const candidates = [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];
    final sevenZip = candidates.firstWhere(
      (c) => File(c).existsSync(),
      orElse: () => '',
    );
    if (sevenZip.isEmpty) {
      throw '7-Zip not found. Install 7-Zip to assign RAR patches.';
    }

    // Temp dir inside patchesDir so rename() never crosses drive boundaries.
    final tmp = Directory(p.join(
      patchesDir.path,
      '.tmp_${DateTime.now().millisecondsSinceEpoch}',
    ));
    tmp.createSync(recursive: true);
    try {
      final result = await Process.run(
          sevenZip, ['x', widget.item.archivePath.path, '-o${tmp.path}', '-y']);
      if (result.exitCode != 0) {
        throw '7-Zip extraction failed:\n${result.stderr}';
      }

      final allFiles = tmp.listSync(recursive: true).whereType<File>().toList();

      // ── Check depth of every patch file ───────────────────────────────────
      // Accepted:  tmp/patch.rpa          (depth 0 — directly in temp root)
      // Accepted:  tmp/game/patch.rpa     (depth 1 — one sub-folder, e.g. game/)
      // Rejected:  tmp/game/ch1/patch.rpy (depth 2+ — complex, apply manually)
      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_kPatchExts.contains(ext)) continue;

        final isAtRoot    = file.parent.path == tmp.path;
        final isOneDeep   = file.parent.parent.path == tmp.path;
        if (!isAtRoot && !isOneDeep) {
          throw _complexStructureError(widget.item.name);
        }
      }

      // ── Move flat patch files into .patches/ ───────────────────────────────
      // Sub-folder prefix (depth-1 case) is stripped — only the filename is kept.
      int moved = 0;
      for (final file in allFiles) {
        final ext = p.extension(file.path).toLowerCase();
        if (!_kPatchExts.contains(ext)) continue;

        final patchName = _resolveCollision(p.basename(file.path), patchesDir);
        // rename() is safe — tmp is inside patchesDir (same drive).
        await file.rename(p.join(patchesDir.path, patchName));
        ref.read(userDataProvider.notifier).setPatchState(metaKey, patchName, false);
        moved++;
      }

      if (moved == 0) {
        throw 'No patch files (.rpa, .rpy, .rpyc, .py) found in RAR.';
      }
      await widget.item.archivePath.delete();
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  }

  /// Error message for archives with nested folder structure.
  static String _complexStructureError(String archiveName) =>
      '"$archiveName" contains patch files inside sub-folders.\n\n'
      'VN Pathfinder cannot safely determine where these files belong — '
      'the creator\'s intended directory structure could vary.\n\n'
      'Please apply this patch manually:\n'
      '  1. Extract the archive yourself\n'
      '  2. Place the .rpa / .rpy / .py files directly into the game\'s game/ folder\n'
      '  3. Use Scan in the Patches tab to sync the app\'s database';

  /// Returns [name] if it doesn't exist in [dir], otherwise appends _2, _3, …
  String _resolveCollision(String name, Directory dir) {
    if (!File(p.join(dir.path, name)).existsSync() &&
        !Directory(p.join(dir.path, name)).existsSync()) {
      return name;
    }
    final stem = p.basenameWithoutExtension(name);
    final ext  = p.extension(name);
    var i = 2;
    while (true) {
      final candidate = '${stem}_$i$ext';
      if (!File(p.join(dir.path, candidate)).existsSync() &&
          !Directory(p.join(dir.path, candidate)).existsSync()) {
        return candidate;
      }
      i++;
    }
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          isDense: true,
          isExpanded: true,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
          dropdownColor: AppColors.bgCard,
          icon: const Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
