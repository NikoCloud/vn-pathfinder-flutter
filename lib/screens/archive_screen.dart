import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../theme.dart';
import '../models/archive_item.dart';
import '../models/game_group.dart';
import '../providers/downloads_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/notification_provider.dart';
import '../services/archive_cards.dart';
import '../services/extraction_log.dart';
import '../services/extraction_service.dart';
import '../services/scanner_service.dart' show planExtractFolderName;
import '../utils/formatters.dart';
import '../widgets/common/art_card.dart';
import '../widgets/common/kit.dart';
import '../widgets/game/game_actions.dart';
import '../widgets/modals/orphan_scanner_modal.dart';

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
  final ExtractionProgress? measured;
  final Duration elapsed;
  const _ExState({
    this.status = _ExStatus.idle,
    this.progress = 0,
    this.error,
    this.currentFile,
    this.filesCompleted = 0,
    this.totalFiles = 0,
    this.measured,
    this.elapsed = Duration.zero,
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

/// What an archive shows as a card: its saved data, or the game it belongs to.
class ArchiveEntry {
  final ArchiveItem item;
  final ArchiveCard? card;
  final GameGroup? game;
  const ArchiveEntry(this.item, {this.card, this.game});

  String get title => card?.title.isNotEmpty == true ? card!.title : game?.effectiveTitle ?? item.name;
  String get developer => card?.developer.isNotEmpty == true ? card!.developer : game?.effectiveDeveloper ?? '';
  String get version => card?.version.isNotEmpty == true ? card!.version : item.versionStr;
  List<String> get tags => card?.tags.isNotEmpty == true ? card!.tags : game?.newestMetaTags ?? const [];
}

/// The game an archive belongs to: where it was extracted to, or the game with
/// its name. Null if neither is in the library.
GameGroup? gameForArchive(ArchiveItem item, List<GameGroup> groups, String? extractedTo) {
  if (extractedTo != null) {
    for (final g in groups) {
      if (g.versions.any((v) => p.equals(v.folderPath.path, extractedTo))) return g;
    }
  }
  return groups.where((g) => g.baseKey == item.baseKey && g.versions.isNotEmpty).firstOrNull;
}

/// This archive's version is already in the library, however it got there.
/// 1.0 called any archive with a matching game safe to delete. That would
/// include an update you haven't extracted yet, so the version has to match.
bool archiveIsInstalled(ArchiveItem item, GameGroup? game) =>
    game != null && item.versionStr.isNotEmpty && game.versions.any((v) => v.versionStr == item.versionStr);

/// 7-Zip's usual place, or null.
String? _findSevenZip() {
  for (final path in const [
    r'C:\Program Files\7-Zip\7z.exe',
    r'C:\Program Files (x86)\7-Zip\7z.exe',
  ]) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

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

  // Running extractions, so they can be cancelled.
  final _jobs = <String, ExtractionJob>{};

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

  bool _isExtracted(ArchiveItem item) =>
      Directory(_extractedDirPath(item)).existsSync();

  GameGroup? _gameOf(ArchiveItem item, List<GameGroup> groups) =>
      gameForArchive(item, groups, ExtractionLog.folderFor(item.archivePath.path));

  bool _isBusy(ArchiveItem item) {
    final state = ref.read(_exProvider)[item.archivePath.path];
    return state?.isActive == true || state?.isQueued == true;
  }

  /// Files being extracted aren't deleted out from under the extraction.
  bool _refuseIfBusy(ArchiveItem item) {
    if (!_isBusy(item)) return false;
    ref.read(notificationProvider.notifier).warning('${item.name} is being extracted. Cancel it first.');
    return true;
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
    ref.listen(_exProvider, (_, next) {
      ref.read(extractionStatusProvider.notifier).state = {
        for (final e in next.entries)
          e.key: (
            running: e.value.isActive,
            queued: e.value.isQueued,
            done: e.value.isDone,
            failed: e.value.isFailed,
            progress: e.value.progress,
            error: e.value.error,
          ),
      };
    });
    ref.listen(libraryProvider, (_, next) {
      if (!next.loading) _startRequested(next);
    });

    final libState     = ref.watch(libraryProvider);
    final settings     = ref.watch(settingsProvider);
    final exStates     = ref.watch(_exProvider);
    ref.watch(_queueProvider);
    final downloading  = ref.watch(downloadingPathsProvider);
    final all          = _allArchives(libState.groups)
        .where((a) => !downloading.contains(p.canonicalize(a.archivePath.path)))
        .toList();
    final visible      = _filtered(all);
    final totalBytes   = all.fold<int>(0, (s, a) => s + (a.sizeBytes ?? 0));
    final extractedAll = all.where(_isExtracted).toList();
    // Clean Up only ever deletes the archive, so it can include anything whose
    // version is in the library. Nothing being extracted is offered.
    final removable = all
        .where((a) => !_isBusy(a) && (_isExtracted(a) || archiveIsInstalled(a, _gameOf(a, libState.groups))))
        .toList();
    // Completed = any archive whose extracted folder exists on disk.
    // Using filesystem as source of truth so the list survives app restarts.
    final completed    = all.where(_isExtracted).toList();
    final queued       = all.where((a) => exStates[a.archivePath.path]?.isQueued == true).toList();
    final activeEntries = exStates.entries.where((e) => e.value.isActive).toList();
    final failures = exStates.entries.where((e) => e.value.isFailed).toList();
    final failure = failures.where((e) => e.key == _selectedPath).firstOrNull ?? failures.lastOrNull;
    final selectedItem = visible.where((a) => a.archivePath.path == _selectedPath).firstOrNull;

    // Anything the app knows something about gets a card; the rest stay rows.
    final savedCards = ref.watch(archiveCardsProvider);
    final entries = <ArchiveEntry>[];
    final rows = <ArchiveItem>[];
    for (final item in visible) {
      final card = savedCards.where((c) => c.fileName == item.name).firstOrNull;
      final game = _gameOf(item, libState.groups);
      if (card != null || game != null) {
        entries.add(ArchiveEntry(item, card: card, game: game));
      } else {
        rows.add(item);
      }
    }

    return SizedBox.expand(
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
            cleanUpLabel: removable.isEmpty
                ? 'Clean Up'
                : 'Clean Up (${removable.length}, ${fmtBytes(removable.fold<int>(0, (s, a) => s + (a.sizeBytes ?? 0)))})',
            onCleanUp: () => _showCleanUp(removable),
            onOrphans: () => showOrphanScannerModal(context),
          ),

          // ── 2. Extraction Hero ─────────────────────────────────────
          if (activeEntries.isEmpty) _ExtractionHero(activeEntry: null, failure: failure),
          for (final entry in activeEntries)
            _ExtractionHero(
              activeEntry: entry,
              onCancel: () => _jobs[entry.key]?.cancel(),
            ),

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
                : CustomScrollView(
                    slivers: [
                      if (entries.isNotEmpty)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(AppLayout.gutter, 16, AppLayout.gutter, rows.isEmpty ? 24 : 12),
                          sliver: SliverLayoutBuilder(builder: (context, c) {
                            final wall = wallColumns(c.crossAxisExtent, 272);
                            return SliverGrid.builder(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: wall.columns,
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 20,
                                mainAxisExtent: ArtCard.heightFor(wall.cardWidth),
                              ),
                              itemCount: entries.length,
                              itemBuilder: (context, i) => _entryCard(context, entries[i], exStates),
                            );
                          }),
                        ),
                      if (rows.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _TableHeader(
                            sortKey: _sortKey,
                            sortDir: _sortDir,
                            onSort: _toggleSort,
                          ),
                        ),
                        SliverFixedExtentList(
                          itemExtent: 44,
                          delegate: SliverChildBuilderDelegate(
                            childCount: rows.length,
                            (ctx, i) {
                              final item = rows[i];
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

  /// An archive with art: the same card as everywhere else in the app.
  Widget _entryCard(BuildContext context, ArchiveEntry entry, Map<String, _ExState> exStates) {
    final item = entry.item;
    final exState = exStates[item.archivePath.path] ?? const _ExState();
    final extracted = _isExtracted(item);
    final installed = extracted || archiveIsInstalled(item, entry.game);
    final selected = item.archivePath.path == _selectedPath;
    final canExtract = item.type == ArchiveType.zip || item.type == ArchiveType.rar;
    final game = entry.game;
    final art = entry.card?.cover ?? (game == null ? null : localArt(game, ref));

    final chip = switch (exState.status) {
      _ExStatus.running => VpBadge(
          label: 'Extracting ${(exState.progress * 100).round()}%',
          fill: AppColors.accent,
          color: AppColors.onAccent,
        ),
      _ExStatus.queued => const VpBadge(label: 'Queued'),
      _ExStatus.failed => Tooltip(
          message: exState.error ?? '',
          child: VpBadge(label: 'Failed', fill: AppColors.danger, color: AppColors.bgPrimary),
        ),
      _ when extracted => const VpBadge(label: 'Extracted'),
      _ when installed => const VpBadge(label: 'Already installed'),
      _ => VpBadge(label: canExtract ? 'Ready to extract' : item.type.label),
    };

    void more(Offset position) => _showContextMenu(context, position, item, extracted, exState);

    return ArtCard(
      key: ValueKey(item.archivePath.path),
      art: art,
      epoch: ref.watch(archiveCardsEpochProvider),
      title: entry.title,
      subtitle: entry.developer,
      time: item.sizeBytes == null ? null : fmtBytes(item.sizeBytes!),
      timeTooltip: item.name,
      topLeft: chip,
      version: entry.version.isEmpty ? null : fmtVersion(entry.version),
      peekText: entry.tags.take(4).join(', '),
      semanticLabel: entry.title,
      picked: selected,
      onOpen: () => setState(() => _selectedPath = selected ? null : item.archivePath.path),
      onHover: (on) => setAmbientHover(ref, on ? art : null),
      onSecondaryTapDown: (d) => more(d.globalPosition),
      actions: [
        if (exState.isActive || exState.isQueued)
          const SizedBox.shrink()
        else if (installed && game != null)
          VpButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            tone: VpTone.primary,
            small: true,
            onTap: () => playGame(context, ref, game),
          )
        else if (canExtract)
          VpButton(
            label: 'Extract',
            icon: Icons.unarchive_outlined,
            tone: VpTone.primary,
            small: true,
            onTap: () => _enqueue(item),
          )
        else
          VpButton(label: 'Assign', small: true, tone: VpTone.glass, onTap: () => _showAssignDialog(item)),
        Builder(
          builder: (context) => VpIconButton(
            icon: Icons.more_horiz,
            tooltip: 'More actions',
            onArt: true,
            onTap: () {
              final box = context.findRenderObject() as RenderBox;
              more(box.localToGlobal(Offset(0, box.size.height + 4)));
            },
          ),
        ),
      ],
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
        side: BorderSide(color: AppColors.borderLight),
      ),
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (canExtract)
          _ctxItem('extract', Icons.unarchive_outlined, 'Extract',
              enabled: exState.status != _ExStatus.running && exState.status != _ExStatus.queued),
        _ctxItem('delete_archive', Icons.delete_outline, 'Delete Archive'),
        _ctxItem('open_folder', Icons.folder_open_outlined, 'Open Folder'),
        _ctxItem('assign_patch', Icons.extension_outlined, 'Assign…'),
        if (isExtracted) ...[
          const PopupMenuDivider(height: 1),
          _ctxItem('delete_extracted', Icons.delete_sweep_outlined, 'Delete Extracted'),
          _ctxItem('clear_and_delete', Icons.delete_forever_outlined, 'Clear & Delete Archive',
              danger: true),
        ],
        const PopupMenuDivider(height: 1),
        _ctxItem('copy_path', Icons.copy_outlined, 'Copy Path'),
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

  /// Queues the downloads the Feed asked for, once a scan has listed them.
  void _startRequested(LibraryState library) {
    final requests = ref.read(extractRequestsProvider);
    if (requests.isEmpty) return;
    final archives = _allArchives(library.groups);
    final found = <String>[];
    for (final path in requests) {
      final item = archives.where((a) => p.equals(a.archivePath.path, path)).firstOrNull;
      if (item == null) continue;
      found.add(path);
      _enqueue(item);
    }
    final notifier = ref.read(extractRequestsProvider.notifier);
    notifier.state = notifier.state.where((r) => !found.contains(r)).toList();
  }

  void _enqueue(ArchiveItem item) {
    final key = item.archivePath.path;
    final exNotifier = ref.read(_exProvider.notifier);
    final qNotifier  = ref.read(_queueProvider.notifier);

    // Already running or queued — ignore
    final current = ref.read(_exProvider)[key];
    if (current?.isActive == true || current?.isQueued == true) return;

    final running = ref.read(_exProvider).values.where((e) => e.isActive).length;

    if (running >= ref.read(settingsProvider).concurrentExtractions) {
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

    final job = _jobs[key] = ExtractionJob();
    final clock = Stopwatch()..start();
    void onProgress(ExtractionProgress update) {
      if (!mounted) return;
      exNotifier.state = {
        ...exNotifier.state,
        key: _ExState(
          status: _ExStatus.running,
          progress: update.fraction,
          currentFile: update.currentFile,
          filesCompleted: update.filesDone,
          totalFiles: update.filesTotal,
          measured: update,
          elapsed: clock.elapsed,
        ),
      };
    }

    try {
      if (item.type == ArchiveType.zip) {
        await _extractZip(item, job, onProgress);
      } else if (item.type == ArchiveType.rar) {
        await _extractRar(item, job, onProgress);
      } else {
        throw 'Extraction not supported for ${item.type.label} files.';
      }
      exNotifier.state = {
        ...exNotifier.state,
        key: const _ExState(status: _ExStatus.done, progress: 1.0),
      };
      ref.read(libraryProvider.notifier).scan();
    } on ExtractionCancelled {
      exNotifier.state = Map.of(exNotifier.state)..remove(key);
    } catch (e) {
      exNotifier.state = {
        ...exNotifier.state,
        key: _ExState(status: _ExStatus.failed, error: e.toString()),
      };
    }
    _jobs.remove(key);

    // Process next in queue, up to the Simultaneous Extractions setting.
    while (mounted && qNotifier.state.isNotEmpty) {
      final running = exNotifier.state.values.where((e) => e.isActive).length;
      if (running >= ref.read(settingsProvider).concurrentExtractions) break;
      final nextPath = qNotifier.state.first;
      qNotifier.state = qNotifier.state.skip(1).toList();
      final allItems = _allArchives(ref.read(libraryProvider).groups);
      final nextItem = allItems.where((a) => a.archivePath.path == nextPath).firstOrNull;
      if (nextItem != null) _startExtraction(nextItem);
    }
  }

  Future<void> _extractZip(
      ArchiveItem item, ExtractionJob job, void Function(ExtractionProgress) onProgress) async {
    final staging = _stagingDir(item);
    try {
      await job.extractZip(item.archivePath.path, staging.path, onProgress);
    } catch (_) {
      await compute(_deleteDir, staging.path);
      rethrow;
    }
    await _placeExtracted(item, staging);
    if (ref.read(settingsProvider).deleteAfterExtract) await item.archivePath.delete();
  }

  Future<void> _extractRar(
      ArchiveItem item, ExtractionJob job, void Function(ExtractionProgress) onProgress) async {
    final sevenZip = _findSevenZip();
    if (sevenZip == null) throw '7-Zip not found. Install 7-Zip to extract RAR archives.';

    final staging = _stagingDir(item);
    try {
      await job.extractWith7Zip(sevenZip, item.archivePath.path, staging.path, onProgress);
    } catch (_) {
      await compute(_deleteDir, staging.path);
      rethrow;
    }
    await _placeExtracted(item, staging);
    if (ref.read(settingsProvider).deleteAfterExtract) await item.archivePath.delete();
  }

  /// A fresh hidden folder next to the archive (same drive, so the result can
  /// be moved into place with a rename). The library scan skips dot-folders.
  Directory _stagingDir(ArchiveItem item) {
    final dir = Directory(p.join(p.dirname(item.archivePath.path),
        '.vnp-extract-${DateTime.now().microsecondsSinceEpoch}'));
    dir.createSync(recursive: true);
    return dir;
  }

  /// Moves an extraction out of [staging] into the library, named by
  /// planExtractFolderName from the archive's name and the single folder
  /// inside it — which is flattened, so the game sits directly in the library
  /// folder where the scanner recognises it. Re-extracting an archive merges
  /// into the folder it went to before; any other existing folder is left
  /// alone and the new one gets a "-dupN" suffix.
  Future<void> _placeExtracted(ArchiveItem item, Directory staging) async {
    final entries = staging
        .listSync()
        .where((e) => p.basename(e.path) != '__MACOSX')
        .toList();
    final singleRoot =
        entries.length == 1 && entries.first is Directory ? entries.first as Directory : null;
    final content = singleRoot ?? staging;

    final libraryKeys = ref
        .read(libraryProvider)
        .groups
        .where((g) => g.versions.isNotEmpty)
        .map((g) => g.baseKey)
        .toSet();
    final library = ref.read(settingsProvider).libraryDir;
    final card = library.isEmpty
        ? null
        : ArchiveCards.all(library).where((c) => c.fileName == item.name).firstOrNull;
    final name = card?.extractName ??
        planExtractFolderName(
          archiveStem: p.basenameWithoutExtension(item.archivePath.path),
          innerFolder: singleRoot == null ? null : p.basename(singleRoot.path),
          libraryKeys: libraryKeys,
        );

    final parent = staging.parent.path;
    var target = p.join(parent, name);
    final previous = _extractedDirPath(item);
    if (Directory(target).existsSync() && target != previous) {
      var n = 2;
      while (Directory(p.join(parent, '$name-dup$n')).existsSync()) {
        n++;
      }
      target = p.join(parent, '$name-dup$n');
    }

    if (Directory(target).existsSync()) {
      await compute(_mergeInto, (content.path, target));
    } else {
      await content.rename(target);
    }
    if (staging.existsSync()) await compute(_deleteDir, staging.path);
    ExtractionLog.record(item.archivePath.path, target);
    card?.moveInto(Directory(target));
    ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
    debugPrint('Extracted ${p.basename(item.archivePath.path)} → $name');
  }

  // ═══════════════════════════════════════════════════════════════════
  // DELETION
  // ═══════════════════════════════════════════════════════════════════

  /// Pick archives whose game is already extracted, and delete them to get
  /// the disk space back. The extracted games aren't touched.
  void _deleteCardsFor(Iterable<ArchiveItem> items) {
    final names = items.map((i) => i.name).toSet();
    for (final card in ref.read(archiveCardsProvider)) {
      if (names.contains(card.fileName)) card.delete();
    }
    ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
  }

  Future<void> _showCleanUp(List<ArchiveItem> extracted) async {
    final chosen = await showDialog<List<ArchiveItem>>(
      context: context,
      builder: (_) => _CleanUpDialog(archives: extracted),
    );
    if (chosen == null || chosen.isEmpty) return;
    var freed = 0;
    for (final item in chosen) {
      try {
        freed += item.sizeBytes ?? 0;
        await item.archivePath.delete();
      } catch (e) {
        debugPrint('Clean up: $e');
      }
    }
    _deleteCardsFor(chosen);
    ref.read(libraryProvider.notifier).scan();
    ref.read(notificationProvider.notifier).success(
        'Deleted ${chosen.length} archive${chosen.length == 1 ? '' : 's'}, freed ${fmtBytes(freed)}');
  }

  Future<void> _deleteArchive(ArchiveItem item) async {
    if (_refuseIfBusy(item)) return;
    final ok = await _confirmDialog(
      title: 'Delete Archive?',
      body: 'Delete "${item.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await item.archivePath.delete();
      _deleteCardsFor([item]);
      ref.read(libraryProvider.notifier).scan();
    } catch (e) { debugPrint('deleteArchive: $e'); }
  }

  Future<void> _deleteSingleExtracted(ArchiveItem item) async {
    final dirPath = _extractedDirPath(item);
    try {
      await compute(_deleteDir, dirPath);
      ExtractionLog.forget(item.archivePath.path);
      if (mounted) setState(() {});
    } catch (e) { debugPrint('deleteSingleExtracted: $e'); }
  }

  Future<void> _clearAndDeleteSingle(ArchiveItem item) async {
    if (_refuseIfBusy(item)) return;
    final ok = await _confirmDialog(
      title: 'Clear & Delete?',
      body: 'Delete the extracted folder and the archive file "${item.name}"?\nThis cannot be undone.',
      confirmLabel: 'Clear & Delete',
    );
    if (!ok) return;
    try {
      await compute(_deleteDirsAndFiles, ([_extractedDirPath(item)], [item.archivePath.path]));
      ExtractionLog.forget(item.archivePath.path);
      _deleteCardsFor([item]);
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
      List<ArchiveItem> all, Map<String, _ExState> exStates) async {
    final items = all.where((a) => !_isBusy(a)).toList();
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
    for (final path in files) {
      ExtractionLog.forget(path);
    }
    _deleteCardsFor(items);
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
    Clipboard.setData(ClipboardData(text: item.archivePath.path));
    ref.read(notificationProvider.notifier).info('Path copied');
  }

  // ═══════════════════════════════════════════════════════════════════
  // ASSIGN PATCH
  // ═══════════════════════════════════════════════════════════════════

  void _showAssignDialog(ArchiveItem item) {
    final groups = ref.read(libraryProvider).groups;
    final files = _allArchives(groups).map((a) => a.name).toSet();
    final games = groups.where((g) => g.versions.isNotEmpty).toList()
      ..sort((a, b) => a.effectiveTitle.toLowerCase().compareTo(b.effectiveTitle.toLowerCase()));
    showDialog<bool>(
      context: context,
      builder: (_) => _AssignPatchDialog(item: item, groups: games, files: files),
    ).then((changed) {
      if (changed == true && mounted) ref.read(libraryProvider.notifier).scan();
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Where [item] was extracted: the recorded folder, or the archive-named
  /// folder that extractions used before the naming planner.
  String _extractedDirPath(ArchiveItem item) =>
      ExtractionLog.folderFor(item.archivePath.path) ??
      p.join(
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
          side: BorderSide(color: AppColors.border),
        ),
        title: Text(title,
            style: AppText.ui(
                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: Text(body,
            style: AppText.ui(fontSize: 12, color: AppColors.textSecondary,
                height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppText.ui(fontSize: 12, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: AppText.ui(fontSize: 12, color: AppColors.danger,
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

  /// Moves every file under `from` into `to`, keeping relative paths and
  /// replacing files that already exist (same drive, so these are renames).
  static Future<void> _mergeInto((String, String) args) async {
    final (from, to) = args;
    for (final f in Directory(from).listSync(recursive: true).whereType<File>()) {
      final dest = File(p.join(to, p.relative(f.path, from: from)));
      dest.parent.createSync(recursive: true);
      if (dest.existsSync()) dest.deleteSync();
      f.renameSync(dest.path);
    }
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
  final String cleanUpLabel;
  final VoidCallback onCleanUp;
  final VoidCallback onOrphans;

  const _ArchiveHeader({
    required this.query,
    required this.typeFilter,
    required this.unmatchedOnly,
    required this.onQueryChanged,
    required this.onTypeFilter,
    required this.onUnmatchedOnly,
    required this.onRefresh,
    required this.cleanUpLabel,
    required this.onCleanUp,
    required this.onOrphans,
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
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Subtitle
          Expanded(
            child: Text(
              'Archives (.zip, .rar, .rpa, .rpy)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.ui(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),

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
              style: AppText.ui(fontSize: 11, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search archives…',
                hintStyle: AppText.ui(fontSize: 11, color: AppColors.textMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                isDense: true,
                prefixIcon:
                    Icon(Icons.search, size: 13, color: AppColors.textMuted),
              ),
            ),
          ),

          const SizedBox(width: 12),

          _HeaderBtn(
            label: widget.cleanUpLabel,
            onTap: widget.onCleanUp,
          ),
          const SizedBox(width: 6),
          _HeaderBtn(
            label: 'Orphans',
            onTap: widget.onOrphans,
          ),
          const SizedBox(width: 6),

          // Refresh button
          _HeaderBtn(
            label: 'Refresh',
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

  /// The extraction to explain when nothing's running.
  final MapEntry<String, _ExState>? failure;
  final VoidCallback? onCancel;
  const _ExtractionHero({required this.activeEntry, this.failure, this.onCancel});

  @override
  Widget build(BuildContext context) {
    if (activeEntry != null) return _buildActive(activeEntry!);
    return failure == null ? _buildIdle() : _buildFailed(failure!);
  }

  Widget _buildFailed(MapEntry<String, _ExState> entry) {
    final why = entry.value.error ?? 'The extraction stopped.';
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Flexible(
            child: Tooltip(
              message: why,
              child: Text(
                "Couldn't extract ${p.basename(entry.key)}\n$why",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.unarchive_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            'No active extraction — select an archive and press Extract.\nFiles are extracted into a folder next to the archive. The library rescans automatically when done.',
            style: AppText.ui(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(MapEntry<String, _ExState> entry) {
    final ex       = entry.value;
    final fileName = p.basename(entry.key);
    final pct      = (ex.progress * 100);
    final measured = ex.measured;

    return Container(
      decoration: BoxDecoration(
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
                          _ExStat(label: 'Speed',
                              value: measured == null
                                  ? '—'
                                  : '${fmtBytes(measured.speed(ex.elapsed).round())}/s'),
                          const SizedBox(width: 20),
                          _ExStat(label: 'Done',
                              value: measured == null ? '—' : fmtBytes(measured.bytesDone)),
                          const SizedBox(width: 20),
                          _ExStat(label: 'Time left',
                              value: _timeLeft(measured?.timeLeft(ex.elapsed))),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Status lines
                      Text(
                        ex.currentFile != null
                            ? 'Extracting: ${ex.currentFile}'
                            : 'Preparing…',
                        style: AppText.ui(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (ex.totalFiles > 0)
                        Text(
                          'File ${ex.filesCompleted} of ${ex.totalFiles}',
                          style: AppText.ui(
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
                              style: AppText.ui(
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
                            style: AppText.mono(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                          if (onCancel != null) ...[
                            const SizedBox(width: 12),
                            _HeaderBtn(label: 'Cancel', onTap: onCancel!),
                          ],
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
                            valueColor: AlwaysStoppedAnimation<Color>(
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
                            ex.totalFiles > 0
                                ? '${ex.filesCompleted} / ${ex.totalFiles} files'
                                : '${ex.filesCompleted} files',
                            style: AppText.mono(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}% complete',
                            style: AppText.mono(
                                fontSize: 11, color: AppColors.textMuted),
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

String _timeLeft(Duration? left) {
  if (left == null) return '—';
  final m = left.inMinutes;
  final s = (left.inSeconds % 60).toString().padLeft(2, '0');
  return m >= 60 ? '${left.inHours}h ${m % 60}m' : '$m:$s';
}

class _CleanUpDialog extends StatefulWidget {
  final List<ArchiveItem> archives;
  const _CleanUpDialog({required this.archives});

  @override
  State<_CleanUpDialog> createState() => _CleanUpDialogState();
}

class _CleanUpDialogState extends State<_CleanUpDialog> {
  late final _chosen = {...widget.archives};

  @override
  Widget build(BuildContext context) {
    final total = _chosen.fold<int>(0, (sum, a) => sum + (a.sizeBytes ?? 0));
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: Text('Delete Extracted Archives',
          style: AppText.ui(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 480,
        height: 360,
        child: widget.archives.isEmpty
            ? Center(
                child: Text('No extracted archives to clean up.',
                    style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
              )
            : ListView(
                children: [
                  Row(
                    children: [
                      VpButton(
                        label: 'Select all',
                        tone: VpTone.quiet,
                        small: true,
                        onTap: () => setState(() => _chosen.addAll(widget.archives)),
                      ),
                      VpButton(
                        label: 'Select none',
                        tone: VpTone.quiet,
                        small: true,
                        onTap: () => setState(_chosen.clear),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'These games are already extracted. Deleting the archives frees disk space and leaves the games alone.',
                      style: AppText.ui(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
                    ),
                  ),
                  for (final a in widget.archives)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.accent,
                      value: _chosen.contains(a),
                      onChanged: (v) => setState(() => v == true ? _chosen.add(a) : _chosen.remove(a)),
                      title: Text(a.name,
                          style: AppText.ui(fontSize: 12, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      secondary: Text(fmtBytes(a.sizeBytes ?? 0),
                          style: AppText.mono(fontSize: 11, color: AppColors.textMuted)),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, _chosen.toList()),
          child: Text(
            'Delete ${_chosen.length} (${fmtBytes(total)})',
            style: TextStyle(color: _chosen.isEmpty ? AppColors.textMuted : AppColors.danger),
          ),
        ),
      ],
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
            style: AppText.ui(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            style: AppText.mono(
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
      decoration: BoxDecoration(
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
                    style: AppText.ui(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '($count)',
                    style: AppText.ui(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more,
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
              style: AppText.ui(
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
              style: AppText.ui(
                  fontSize: 11,
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
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Left border placeholder
          const SizedBox(width: 3),
          _TH('Name',     _SortKey.name,     flex: 4, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('Size',     _SortKey.size,     width: 80, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('Type',     _SortKey.type,     width: 70, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('Modified', _SortKey.modified, width: 100, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
          _TH('Status',   _SortKey.status,   width: 130, sortKey: sortKey, sortDir: sortDir, onSort: onSort),
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
                style: AppText.ui(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 3),
                Text(
                  widget.sortDir == _SortDir.asc ? '↑' : '↓',
                  style: TextStyle(fontSize: 11, color: AppColors.accent),
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
              bottom: BorderSide(color: AppColors.border, width: 0.5),
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
                    style: AppText.ui(
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
                  style: AppText.ui(
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
                  style: AppText.ui(
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
    ArchiveType.zip => AppColors.statusUpdated.withValues(alpha: 0.15),
    ArchiveType.rar => AppColors.statusSkimmed.withValues(alpha: 0.15),
    ArchiveType.rpa => AppColors.accent.withValues(alpha: 0.15),
    ArchiveType.rpy || ArchiveType.py => AppColors.accent.withValues(alpha: 0.15),
    _ => AppColors.bgHover,
  };

  Color get _fg => switch (type) {
    ArchiveType.zip => AppColors.statusUpdated,
    ArchiveType.rar => AppColors.statusSkimmed,
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
        style: AppText.ui(
          fontSize: 11,
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
              style: AppText.ui(fontSize: 11, color: AppColors.accent)),
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
              style: AppText.ui(
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
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: exState.error ?? '',
              child: Text('Failed',
                  style: AppText.ui(
                      fontSize: 11, color: AppColors.danger),
                  overflow: TextOverflow.ellipsis),
            ),
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
              style: AppText.ui(
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
            style: AppText.ui(
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
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$total archives · ${fmtBytes(totalBytes)} total'
          '${extractedCount > 0 ? ' · $extractedCount extracted' : ''}',
          style: AppText.ui(fontSize: 11, color: AppColors.textMuted),
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
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _BarBtn(
            label: 'Extract',
            primary: true,
            enabled: _canExtract,
            onTap: onExtract,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: 'Delete Archive',
            danger: true,
            enabled: selected != null,
            onTap: onDeleteArchive,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: 'Open Folder',
            enabled: selected != null,
            onTap: onOpenFolder,
          ),
          const SizedBox(width: 8),
          _BarBtn(
            label: 'Assign…',
            enabled: selected != null,
            onTap: onAssignPatch,
          ),
          if (isExtracted) ...[
            const SizedBox(width: 8),
            _BarBtn(
              label: 'Delete Extracted',
              enabled: true,
              onTap: onDeleteExtracted,
            ),
          ],

          const SizedBox(width: 16),
          Expanded(
            child: Text(
              selected?.archivePath.path ?? 'Select an archive to enable actions',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.ui(fontSize: 11, color: AppColors.textMuted),
            ),
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
              style: AppText.ui(fontSize: 11, color: text)),
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
              style: AppText.ui(fontSize: 12, color: color)),
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
          Icon(Icons.archive_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            hasLibrary ? 'No archives found in library' : 'Set a library directory in Settings',
            style: AppText.ui(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            hasLibrary
                ? 'Place .zip, .rar, or .rpa files in your library folder.'
                : 'Archives will appear here once your library is configured.',
            style: AppText.ui(fontSize: 12, color: AppColors.textMuted),
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
            style: AppText.ui(
              fontSize: 11,
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
    final c = AppColors.textSecondary;
    final hc = AppColors.textPrimary;
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
            style: AppText.ui(
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

/// Game data a file can be linked to: a saved download that lost its file, or
/// a copy of a game's own.
class _DataTarget {
  final ArchiveCard? card;
  final GameGroup? game;
  final String label;
  const _DataTarget(this.label, {this.card, this.game});
}

class _AssignPatchDialog extends ConsumerStatefulWidget {
  final ArchiveItem item;
  final List<GameGroup> groups;

  /// Every archive's name, to tell which saved data has lost its file.
  final Set<String> files;
  const _AssignPatchDialog({required this.item, required this.groups, required this.files});
  @override
  ConsumerState<_AssignPatchDialog> createState() => _AssignPatchDialogState();
}

class _AssignPatchDialogState extends ConsumerState<_AssignPatchDialog> {
  GameGroup? _selectedGroup;
  String?    _selectedVersion;
  bool       _working = false;
  String?    _error;

  /// Linking to game data rather than installing as a patch.
  bool _asData = false;
  late final List<_DataTarget> _targets;
  _DataTarget? _target;
  ArchiveCard? _linked;

  bool get _canHoldGame =>
      widget.item.type == ArchiveType.zip || widget.item.type == ArchiveType.rar;

  @override
  void initState() {
    super.initState();
    _selectedGroup = guessPatchGame(p.basenameWithoutExtension(widget.item.name), widget.groups);
    _selectedVersion = _selectedGroup?.latestVersion?.versionStr;

    final cards = ref.read(archiveCardsProvider);
    _linked = cards.where((c) => c.fileName == widget.item.name).firstOrNull;
    final waiting = cards.where((c) => !widget.files.contains(c.fileName));
    _targets = [
      for (final c in waiting)
        _DataTarget('${c.title}${c.version.isEmpty ? '' : ' ${fmtVersion(c.version)}'} (saved download)', card: c),
      for (final g in widget.groups.where((g) => g.versions.any((v) => v.hasVnpf)))
        _DataTarget(g.effectiveTitle, game: g),
    ];
    _target = _targets.where((t) => identical(t.game, _selectedGroup)).firstOrNull;
    _asData = _canHoldGame && (_linked != null || waiting.isNotEmpty);
  }

  /// Links this file to the chosen data.
  Future<void> _assignData() async {
    final target = _target!;
    setState(() { _working = true; _error = null; });
    try {
      _linked?.linkTo('');
      final game = target.game;
      if (target.card != null) {
        target.card!.linkTo(widget.item.name);
      } else if (game != null) {
        await ArchiveCards.fromGame(
          ref.read(settingsProvider).libraryDir,
          widget.item.name,
          game.versions.lastWhere((v) => v.hasVnpf),
          version: widget.item.versionStr,
          nameHint: game.displayName,
        );
      }
      ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _working = false; _error = e.toString(); });
    }
  }

  void _removeLink() {
    _linked?.linkTo('');
    ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: BorderSide(color: AppColors.border),
      ),
      title: Text('Assign',
          style: AppText.ui(
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
                style: AppText.mono(
                    fontSize: 11, color: AppColors.textSecondary)),
            if (_canHoldGame) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  VpChip(
                    label: 'Game data',
                    selected: _asData,
                    onTap: () => setState(() => _asData = true),
                  ),
                  const SizedBox(width: 6),
                  VpChip(
                    label: 'Patch for a game',
                    selected: !_asData,
                    onTap: () => setState(() => _asData = false),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (_asData) ...[
              if (_linked != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('Linked to ${_linked!.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(color: AppColors.textSecondary)),
                    ),
                    VpButton(label: 'Remove link', tone: VpTone.quiet, small: true, onTap: _removeLink),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Text('Use the data from',
                  style: AppText.ui(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              _PickList<_DataTarget>(
                items: _targets,
                selected: _target,
                labelOf: (t) => t.label,
                onSelect: (t) => setState(() => _target = t),
                onConfirm: _working ? null : _assignData,
              ),
              const SizedBox(height: 8),
              Text('It shows as a card here, and the game gets this data when you extract it.',
                  style: AppText.meta(color: AppColors.textMuted)),
            ] else ...[
            Text('Target game',
                style: AppText.ui(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            _PickList<GameGroup>(
              items: widget.groups,
              selected: _selectedGroup,
              labelOf: (g) => g.effectiveTitle,
              onSelect: (g) => setState(() {
                _selectedGroup = g;
                _selectedVersion = g.latestVersion?.versionStr;
              }),
              onConfirm: _working ? null : _assign,
            ),
            if (_selectedGroup != null && _selectedGroup!.versions.length > 1) ...[
              const SizedBox(height: 12),
              Text('Target version',
                  style: AppText.ui(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              _Dropdown<String>(
                value: _selectedVersion,
                hint: 'Select version…',
                items: _selectedGroup!.versions.map((v) => v.versionStr).toList(),
                labelOf: fmtVersion,
                onChanged: (v) => setState(() => _selectedVersion = v),
              ),
            ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: AppText.ui(
                      fontSize: 11, color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: AppText.ui(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _working || (_asData ? _target == null : _selectedGroup == null)
              ? null
              : (_asData ? _assignData : _assign),
          child: _working
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent))
              : Text('Assign',
                  style: AppText.ui(
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

      if (patchExtensions.contains(suffix)) {
        await _assignLoose(patchesDir, metaKey);
      } else if (suffix == '.zip' || suffix == '.rar') {
        await _assignArchive(patchesDir, metaKey);
      } else {
        throw 'Unsupported patch format: $suffix';
      }

      ref.read(notificationProvider.notifier).success(
          'Stored with ${group.effectiveTitle}. Turn it on in Properties, Patches.');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _working = false; _error = e.toString(); });
    }
  }

  /// Move a loose file (.rpa, .rpy, .rpyc, .py) directly into .patches/.
  Future<void> _assignLoose(Directory patchesDir, String metaKey) async {
    var patchName = widget.item.name;
    if (_nameTaken(patchName, patchesDir)) {
      final chosen = await _askPatchName(patchName, patchesDir);
      if (chosen == null) throw 'Not assigned: a patch named $patchName already exists.';
      patchName = chosen;
    }
    final dest = File(p.join(patchesDir.path, patchName));
    await widget.item.archivePath.rename(dest.path);
    ref.read(userDataProvider.notifier).setPatchState(metaKey, patchName, false);
  }

  bool _nameTaken(String name, Directory dir) =>
      File(p.join(dir.path, name)).existsSync() || Directory(p.join(dir.path, name)).existsSync();

  /// Asks for a new name when a patch with this one already exists, suggesting
  /// the old name with today's date. Null if the user cancels.
  Future<String?> _askPatchName(String name, Directory dir) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final ctrl = TextEditingController(
        text: '${p.basenameWithoutExtension(name)}_$today${p.extension(name)}');
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        final value = ctrl.text.trim();
        final valid = value.isNotEmpty && !_nameTaken(value, dir);
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text('Rename Patch',
              style: AppText.ui(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A patch named "$name" is already assigned to this version.',
                    style: AppText.ui(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  onChanged: (_) => setDialog(() {}),
                  style: AppText.mono(fontSize: 12, color: AppColors.textPrimary),
                ),
                if (value.isNotEmpty && !valid) ...[
                  const SizedBox(height: 6),
                  Text('That name is taken too.',
                      style: AppText.ui(fontSize: 11, color: AppColors.danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: valid ? () => Navigator.pop(ctx, value) : null,
              child: Text('Rename',
                  style: TextStyle(color: valid ? AppColors.accent : AppColors.textMuted)),
            ),
          ],
        );
      }),
    ).whenComplete(ctrl.dispose);
  }

  /// A patch that comes in an archive. Loose patch files go straight into
  /// .patches/. Anything else stays together as one folder named after the
  /// archive, so a mod with its own images or folders keeps them, as in 1.0.
  Future<void> _assignArchive(Directory patchesDir, String metaKey) async {
    final archive = widget.item.archivePath.path;
    // Inside patchesDir so rename() never crosses drive boundaries.
    final tmp = Directory(p.join(patchesDir.path, '.tmp_${DateTime.now().millisecondsSinceEpoch}'));
    tmp.createSync(recursive: true);
    try {
      if (widget.item.type == ArchiveType.rar) {
        final sevenZip = _findSevenZip();
        if (sevenZip == null) throw '7-Zip not found. Install 7-Zip to assign RAR patches.';
        final result = await Process.run(sevenZip, ['x', archive, '-o${tmp.path}', '-y']);
        if (result.exitCode != 0) throw '7-Zip extraction failed:\n${result.stderr}';
      } else {
        await ExtractionJob().extractZip(archive, tmp.path, (_) {});
      }

      final names = await storeUnpackedPatch(
        tmp,
        patchesDir,
        folderName: p.basenameWithoutExtension(widget.item.name),
        chooseName: (taken) => _askPatchName(taken, patchesDir),
      );
      for (final name in names) {
        ref.read(userDataProvider.notifier).setPatchState(metaKey, name, false);
      }
      await widget.item.archivePath.delete();
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  }
}

/// A list you can search, for picking one game out of hundreds. A second click
/// on the same row confirms, as a double-click did in 1.0.
class _PickList<T> extends StatefulWidget {
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;
  final VoidCallback? onConfirm;

  const _PickList({
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
    required this.onConfirm,
  });

  @override
  State<_PickList<T>> createState() => _PickListState<T>();
}

class _PickListState<T> extends State<_PickList<T>> {
  static const _rowHeight = 32.0;
  String _query = '';
  DateTime? _lastTap;
  late final _scroll = ScrollController(
    initialScrollOffset: () {
      final index = widget.selected == null ? -1 : widget.items.indexOf(widget.selected as T);
      return index < 3 ? 0.0 : (index - 2) * _rowHeight;
    }(),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _tap(T item) {
    final now = DateTime.now();
    final again = item == widget.selected &&
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 400);
    _lastTap = now;
    widget.onSelect(item);
    if (again) widget.onConfirm?.call();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? widget.items
        : widget.items.where((i) => widget.labelOf(i).toLowerCase().contains(query)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VpField(hint: 'Search', icon: Icons.search, onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 6),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.borderMd,
          ),
          child: items.isEmpty
              ? Center(child: Text('Nothing matches.', style: AppText.body(color: AppColors.textMuted)))
              : ListView.builder(
                  controller: _scroll,
                  itemExtent: _rowHeight,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final on = item == widget.selected;
                    return Pressable(
                      onTap: () => _tap(item),
                      selected: on,
                      label: widget.labelOf(item),
                      radius: BorderRadius.zero,
                      builder: (context, states) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        color: on
                            ? AppColors.bgActive
                            : states.contains(WidgetState.hovered)
                                ? AppColors.bgHover
                                : Colors.transparent,
                        child: Text(widget.labelOf(item),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body()),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
              style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
          isDense: true,
          isExpanded: true,
          style: AppText.ui(fontSize: 12, color: AppColors.textPrimary),
          dropdownColor: AppColors.bgCard,
          icon: Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
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
