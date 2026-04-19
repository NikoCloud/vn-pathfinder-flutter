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

// ── Extraction state ──────────────────────────────────────────────────────────

enum _ExStatus { idle, running, done, failed }

class _ExState {
  final _ExStatus status;
  final double progress; // 0.0–1.0
  final String? error;
  final String? currentFile; // file being extracted
  final int filesCompleted; // number of files done
  final int totalFiles; // total files to extract
  const _ExState({
    this.status = _ExStatus.idle,
    this.progress = 0,
    this.error,
    this.currentFile,
    this.filesCompleted = 0,
    this.totalFiles = 0,
  });
  bool get isActive => status == _ExStatus.running;
}

// Map from archive path → extraction state
final _extractionProvider =
    StateProvider<Map<String, _ExState>>((ref) => {});

// ── Extraction Hero Panel ─────────────────────────────────────────────────────

class _ExtractionHeroPanel extends StatelessWidget {
  final Map<String, _ExState> extractionStates;
  const _ExtractionHeroPanel({required this.extractionStates});

  @override
  Widget build(BuildContext context) {
    // Find the first active extraction
    final activeEntry = extractionStates.entries.firstWhere(
      (e) => e.value.isActive,
      orElse: () => MapEntry('', const _ExState()),
    );

    if (!activeEntry.value.isActive) {
      // Idle state
      return Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Text('📦',
                style: TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Text(
              'No active extraction — select an archive and press Extract',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Active state
    final ex = activeEntry.value;
    final fileName = p.basename(activeEntry.key);
    final progress = (ex.progress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _ExtractionStat(
                label: 'READ',
                value: '${(ex.filesCompleted * 0.5).toStringAsFixed(1)} MB/s',
              ),
              const SizedBox(width: 32),
              _ExtractionStat(
                label: 'WRITE',
                value: '${(ex.filesCompleted * 0.3).toStringAsFixed(1)} MB/s',
              ),
              const SizedBox(width: 32),
              _ExtractionStat(
                label: 'DISK USAGE',
                value: '${(ex.filesCompleted * 2).toStringAsFixed(0)} MB',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status lines
          Text(
            'Extracting: ${ex.currentFile ?? 'preparing…'}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'File ${ex.filesCompleted} of ${ex.totalFiles}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),

          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fileName,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$progress%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadius.borderSm,
                child: LinearProgressIndicator(
                  value: ex.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.bgInput,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExtractionStat extends StatelessWidget {
  final String label;
  final String value;
  const _ExtractionStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Archive screen ────────────────────────────────────────────────────────────

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  String _query = '';
  ArchiveType? _typeFilter; // null = all
  bool _unmatchedOnly = false;

  List<ArchiveItem> _allArchives(List<GameGroup> groups) {
    final all = <ArchiveItem>[];
    for (final g in groups) {
      all.addAll(g.archives);
    }
    all.sort((a, b) => b.modTime.compareTo(a.modTime));
    return all;
  }

  List<ArchiveItem> _filtered(List<ArchiveItem> all) {
    return all.where((a) {
      if (_query.isNotEmpty &&
          !a.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_typeFilter != null && a.type != _typeFilter) return false;
      if (_unmatchedOnly && a.matchedFolder != null) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final libState = ref.watch(libraryProvider);
    final settings = ref.watch(settingsProvider);
    final extractionStates = ref.watch(_extractionProvider);
    final all = _allArchives(libState.groups);
    final visible = _filtered(all);

    // Stats
    final totalBytes =
        all.fold<int>(0, (sum, a) => sum + (a.sizeBytes ?? 0));

    // Count extracted folders
    final extractedCount = all.where((a) {
      final extracted = Directory(p.join(
        p.dirname(a.archivePath.path),
        p.basenameWithoutExtension(a.archivePath.path),
      ));
      return extracted.existsSync();
    }).length;

    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top bar ─────────────────────────────────────────────────────────
          _ArchiveTopBar(
            count: all.length,
            totalBytes: totalBytes,
            extractedCount: extractedCount,
            query: _query,
            typeFilter: _typeFilter,
            unmatchedOnly: _unmatchedOnly,
            onQueryChanged: (q) => setState(() => _query = q),
            onTypeFilter: (t) => setState(() => _typeFilter = t),
            onUnmatchedOnly: (v) => setState(() => _unmatchedOnly = v),
            onClearAllExtracted: () => _clearAllExtracted(all),
          ),

          // ── Extraction Hero Panel ────────────────────────────────────────────
          _ExtractionHeroPanel(
            extractionStates: extractionStates,
          ),

          // ── Table ────────────────────────────────────────────────────────────
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(hasLibrary: settings.libraryDir.isNotEmpty)
                : _ArchiveTable(
                    items: visible,
                    groups: libState.groups,
                    extractionStates: extractionStates,
                    settings: settings,
                    onExtract: (item) => _extract(item),
                    onAssignPatch: (item) => _showAssignDialog(item),
                    onDelete: (item) => _deleteArchive(item),
                    onClearExtracted: (item) => _clearExtracted(item),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _extract(ArchiveItem item) async {
    final key = item.archivePath.path;
    final type = item.type;
    final notifier = ref.read(_extractionProvider.notifier);

    notifier.state = {
      ...notifier.state,
      (key): const _ExState(status: _ExStatus.running),
    };

    try {
      if (type == ArchiveType.zip) {
        await _extractZip(item, notifier);
      } else if (type == ArchiveType.rar) {
        await _extractRar(item, notifier);
      } else {
        throw 'Extraction not supported for ${type.label} files.';
      }

      notifier.state = {
        ...notifier.state,
        (key): const _ExState(status: _ExStatus.done, progress: 1.0),
      };

      // Rescan so new folders appear in library
      ref.read(libraryProvider.notifier).scan();
    } catch (e) {
      notifier.state = {
        ...notifier.state,
        (key): _ExState(status: _ExStatus.failed, error: e.toString()),
      };
    }
  }

  Future<void> _extractZip(
      ArchiveItem item, StateController<Map<String, _ExState>> notifier) async {
    final destDir = p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    );
    Directory(destDir).createSync(recursive: true);
    final key = item.archivePath.path;

    final bytes = await item.archivePath.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final total = archive.files.length;
    var done = 0;

    for (final file in archive.files) {
      if (file.isFile) {
        final outPath = p.join(destDir, file.name);
        await compute(_writeFileInBackground,
            (outPath, file.content as List<int>));
      }
      done++;
      if (mounted) {
        notifier.state = {
          ...notifier.state,
          (key): _ExState(
            status: _ExStatus.running,
            progress: done / total.clamp(1, total),
            currentFile: p.basename(file.name),
            filesCompleted: done,
            totalFiles: total,
          ),
        };
      }
      // Yield to UI thread after every file so progress updates are visible
      await Future.delayed(Duration.zero);
    }

    final settings = ref.read(settingsProvider);
    if (settings.deleteAfterExtract) {
      item.archivePath.deleteSync();
    }
  }

  // Static helper for compute() — runs in background isolate
  static Future<void> _writeFileInBackground(
      (String path, List<int> bytes) params) async {
    final (path, bytes) = params;
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsBytesSync(bytes);
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
    if (sevenZip.isEmpty) {
      throw '7-Zip not found. Install 7-Zip to extract RAR archives.';
    }
    final destDir = p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    );
    Directory(destDir).createSync(recursive: true);
    final result = await Process.run(sevenZip, [
      'x', item.archivePath.path, '-o$destDir', '-y',
    ]);
    if (result.exitCode != 0) {
      throw '7-Zip extraction failed:\n${result.stderr}';
    }

    // Update state to done (like ZIP does)
    final settings = ref.read(settingsProvider);
    if (settings.deleteAfterExtract) {
      item.archivePath.deleteSync();
    }
  }

  void _showAssignDialog(ArchiveItem item) {
    final groups = ref.read(libraryProvider).groups;
    showDialog<void>(
      context: context,
      builder: (_) => _AssignPatchDialog(item: item, groups: groups),
    );
  }

  Future<void> _clearAllExtracted(List<ArchiveItem> items) async {
    final count = items.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Clear All Extracted?',
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        content: Text(
            'This will delete $count extracted folders. This cannot be undone.',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear All',
                style: GoogleFonts.inter(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final item in items) {
      final extracted = Directory(p.join(
        p.dirname(item.archivePath.path),
        p.basenameWithoutExtension(item.archivePath.path),
      ));
      if (extracted.existsSync()) {
        try {
          extracted.deleteSync(recursive: true);
        } catch (e) {
          debugPrint('Failed to delete extracted folder: $e');
        }
      }
    }

    setState(() {}); // Refresh to update extracted count
  }

  Future<void> _clearExtracted(ArchiveItem item) async {
    final extracted = Directory(p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    ));
    if (extracted.existsSync()) {
      try {
        await extracted.delete(recursive: true);
        setState(() {});
      } catch (e) {
        debugPrint('Failed to clear extracted: $e');
      }
    }
  }

  Future<void> _deleteArchive(ArchiveItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Delete Archive?',
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        content: Text('Delete ${item.name}? This cannot be undone.',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.inter(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      item.archivePath.deleteSync();
      ref.read(libraryProvider.notifier).scan();
    } catch (e) {
      debugPrint('Failed to delete archive: $e');
    }
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _ArchiveTopBar extends StatelessWidget {
  final int count;
  final int totalBytes;
  final int extractedCount;
  final String query;
  final ArchiveType? typeFilter;
  final bool unmatchedOnly;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ArchiveType?> onTypeFilter;
  final ValueChanged<bool> onUnmatchedOnly;
  final VoidCallback onClearAllExtracted;

  const _ArchiveTopBar({
    required this.count,
    required this.totalBytes,
    required this.extractedCount,
    required this.query,
    required this.typeFilter,
    required this.unmatchedOnly,
    required this.onQueryChanged,
    required this.onTypeFilter,
    required this.onUnmatchedOnly,
    required this.onClearAllExtracted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Title + count
          Text('Archives',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.bgActive,
              borderRadius: AppRadius.borderXs,
            ),
            child: Text('$count',
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Text(fmtBytes(totalBytes),
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textMuted)),

          const Spacer(),

          // Clear All Extracted button
          if (extractedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _ActionBtnTopBar(
                label: '🗑 Clear All Extracted ($extractedCount)',
                onTap: onClearAllExtracted,
              ),
            ),

          // Unmatched toggle
          _FilterChip(
            label: 'Unmatched only',
            active: unmatchedOnly,
            onTap: () => onUnmatchedOnly(!unmatchedOnly),
          ),
          const SizedBox(width: 6),

          // Type filters
          for (final type in [null, ArchiveType.zip, ArchiveType.rar, ArchiveType.rpa])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _FilterChip(
                label: type == null ? 'All' : type.label,
                active: typeFilter == type,
                onTap: () => onTypeFilter(type),
              ),
            ),
          const SizedBox(width: 12),

          // Search
          SizedBox(
            width: 200,
            height: 28,
            child: TextField(
              onChanged: onQueryChanged,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search archives…',
                hintStyle: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 0),
                isDense: true,
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.borderSm,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.borderSm,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.borderSm,
                  borderSide:
                      const BorderSide(color: AppColors.accent, width: 1.5),
                ),
                prefixIcon: const Icon(Icons.search,
                    size: 14, color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtnTopBar extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionBtnTopBar({required this.label, required this.onTap});
  @override
  State<_ActionBtnTopBar> createState() => _ActionBtnTopBarState();
}

class _ActionBtnTopBarState extends State<_ActionBtnTopBar> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.danger.withValues(alpha: 0.15) : AppColors.bgCard,
            border: Border.all(
              color: _hovered ? AppColors.danger : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _hovered ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.active, required this.onTap});
  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
              fontSize: 11,
              fontWeight:
                  widget.active ? FontWeight.w600 : FontWeight.w400,
              color: widget.active
                  ? AppColors.accentLight
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _ArchiveTable extends StatelessWidget {
  final List<ArchiveItem> items;
  final List<GameGroup> groups;
  final Map<String, _ExState> extractionStates;
  final AppSettings settings;
  final ValueChanged<ArchiveItem> onExtract;
  final ValueChanged<ArchiveItem> onAssignPatch;
  final ValueChanged<ArchiveItem> onDelete;
  final ValueChanged<ArchiveItem> onClearExtracted;

  const _ArchiveTable({
    required this.items,
    required this.groups,
    required this.extractionStates,
    required this.settings,
    required this.onExtract,
    required this.onAssignPatch,
    required this.onDelete,
    required this.onClearExtracted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _ColHdr('TYPE', width: 52),
              _ColHdr('FILE NAME', flex: 3),
              _ColHdr('MATCHED GAME', flex: 2),
              _ColHdr('SIZE', width: 80),
              _ColHdr('DATE', width: 90),
              _ColHdr('ACTIONS', width: 180),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemExtent: 52,
            itemBuilder: (context, i) {
              final item = items[i];
              final exState =
                  extractionStates[item.archivePath.path] ??
                      const _ExState();
              return _ArchiveRow(
                item: item,
                exState: exState,
                onExtract: () => onExtract(item),
                onAssignPatch: () => onAssignPatch(item),
                onDelete: () => onDelete(item),
                onClearExtracted: () => onClearExtracted(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColHdr extends StatelessWidget {
  final String label;
  final double? width;
  final int flex;
  const _ColHdr(this.label, {this.width, this.flex = 1});

  @override
  Widget build(BuildContext context) {
    final text = Text(label,
        style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textMuted));
    return width != null
        ? SizedBox(width: width, child: text)
        : Expanded(flex: flex, child: text);
  }
}

// ── Popup Menu Item ───────────────────────────────────────────────────────────

class PopupMenuItemLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const PopupMenuItemLabel({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 12)),
      ],
    );
  }
}

class _ArchiveRow extends StatefulWidget {
  final ArchiveItem item;
  final _ExState exState;
  final VoidCallback onExtract;
  final VoidCallback onAssignPatch;
  final VoidCallback onDelete;
  final VoidCallback onClearExtracted;

  const _ArchiveRow({
    required this.item,
    required this.exState,
    required this.onExtract,
    required this.onAssignPatch,
    required this.onDelete,
    required this.onClearExtracted,
  });

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _hovered = false;

  Color get _typeBg => switch (widget.item.type) {
        ArchiveType.zip => const Color(0x1A4A90D9),
        ArchiveType.rar => const Color(0x1AD4943A),
        ArchiveType.rpa => const Color(0x1A9B59B6),
        ArchiveType.rpy || ArchiveType.py => const Color(0x1A4A9E6E),
        _ => AppColors.bgHover,
      };

  Color get _typeColor => switch (widget.item.type) {
        ArchiveType.zip => AppColors.installBlue,
        ArchiveType.rar => AppColors.warning,
        ArchiveType.rpa => const Color(0xFF9B59B6),
        ArchiveType.rpy || ArchiveType.py => AppColors.accent,
        _ => AppColors.textMuted,
      };

  void _showContextMenu(BuildContext context, Offset position) {
    final item = widget.item;
    final canExtract =
        item.type == ArchiveType.zip || item.type == ArchiveType.rar;
    final extractedDir = Directory(p.join(
      p.dirname(item.archivePath.path),
      p.basenameWithoutExtension(item.archivePath.path),
    ));
    final isExtracted = extractedDir.existsSync();

    final items = <PopupMenuEntry<String>>[
      if (canExtract)
        PopupMenuItem<String>(
          value: 'extract',
          enabled: widget.exState.status != _ExStatus.running,
          child: const PopupMenuItemLabel(
            icon: Icons.unarchive_outlined,
            label: 'Extract',
          ),
        ),
      if (isExtracted)
        PopupMenuItem<String>(
          value: 'clear_extracted',
          child: const PopupMenuItemLabel(
            icon: Icons.delete_outline,
            label: 'Clear Extracted',
          ),
        ),
    ];

    if (items.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: items,
    ).then((value) {
      if (value == 'extract') {
        widget.onExtract();
      } else if (value == 'clear_extracted') {
        widget.onClearExtracted();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ex = widget.exState;
    final canExtract =
        item.type == ArchiveType.zip || item.type == ArchiveType.rar;

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgHover : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Type badge
              SizedBox(
                width: 52,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeBg,
                    borderRadius: AppRadius.borderXs,
                  ),
                  child: Text(item.type.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _typeColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // File name
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ex.status == _ExStatus.running)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: LinearProgressIndicator(
                            value: ex.progress,
                            backgroundColor: AppColors.bgHover,
                            color: AppColors.accent,
                            minHeight: 2,
                          ),
                        )
                      else if (ex.status == _ExStatus.failed)
                        Text('Error: ${ex.error}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.danger,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (ex.status == _ExStatus.done)
                        Text('Extracted ✓',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Matched game
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    item.matchedFolder ?? '—',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: item.matchedFolder != null
                        ? AppColors.textSecondary
                        : AppColors.textMuted,
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
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // Date
              SizedBox(
                width: 90,
                child: Text(
                  item.modTime.isNotEmpty
                    ? item.modTime.substring(0, 10)
                    : '—',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),

              // Actions
              SizedBox(
                width: 180,
                child: Row(
                  children: [
                    if (canExtract)
                      _ActionBtn(
                        label: ex.status == _ExStatus.running
                          ? 'Extracting…'
                          : 'Extract',
                        icon: Icons.unarchive_outlined,
                        enabled: ex.status != _ExStatus.running,
                        onTap: widget.onExtract,
                      ),
                    const SizedBox(width: 4),
                    _ActionBtn(
                      label: 'Assign Patch',
                      icon: Icons.extension_outlined,
                      onTap: widget.onAssignPatch,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    this.enabled = true,
    required this.onTap,
  });
  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: active ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered && active ? AppColors.bgActive : AppColors.bgCard,
            border: Border.all(
              color: _hovered && active
                  ? AppColors.borderLight
                  : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 11,
                  color: active
                      ? AppColors.textSecondary
                      : AppColors.textMuted),
              const SizedBox(width: 4),
              Text(widget.label,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: active
                          ? AppColors.textSecondary
                          : AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasLibrary;
  const _EmptyState({required this.hasLibrary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.archive_outlined,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            hasLibrary
                ? 'No archives found in library'
                : 'Set a library directory in Settings',
            style: GoogleFonts.inter(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            hasLibrary
                ? 'Place .zip, .rar, or .rpa files in your library folder.'
                : 'Archives will appear here once your library is configured.',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Assign Patch dialog ───────────────────────────────────────────────────────

class _AssignPatchDialog extends ConsumerStatefulWidget {
  final ArchiveItem item;
  final List<GameGroup> groups;
  const _AssignPatchDialog({required this.item, required this.groups});

  @override
  ConsumerState<_AssignPatchDialog> createState() => _AssignPatchDialogState();
}

class _AssignPatchDialogState extends ConsumerState<_AssignPatchDialog> {
  GameGroup? _selectedGroup;
  String? _selectedVersion;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-select matched group if any
    if (widget.item.matchedFolder != null) {
      try {
        _selectedGroup = widget.groups.firstWhere(
          (g) => g.baseKey == widget.item.baseKey,
        );
        _selectedVersion =
            _selectedGroup?.latestVersion?.versionStr;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
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
            Text('Target game:',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.4)),
            const SizedBox(height: 6),
            _StyledDropdown<GameGroup>(
              value: _selectedGroup,
              hint: 'Select game…',
              items: widget.groups,
              labelOf: (g) => g.effectiveTitle,
              onChanged: (g) => setState(() {
                _selectedGroup = g;
                _selectedVersion = g?.latestVersion?.versionStr;
              }),
            ),
            if (_selectedGroup != null &&
                (_selectedGroup!.versions.length) > 1) ...[
              const SizedBox(height: 12),
              Text('Target version:',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4)),
              const SizedBox(height: 6),
              _StyledDropdown<String>(
                value: _selectedVersion,
                hint: 'Select version…',
                items: _selectedGroup!.versions
                    .map((v) => v.versionStr)
                    .toList(),
                labelOf: (v) => v.isEmpty ? 'Unknown' : 'v$v',
                onChanged: (v) =>
                    setState(() => _selectedVersion = v),
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
              style: GoogleFonts.inter(color: AppColors.textSecondary)),
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
                  style: GoogleFonts.inter(color: AppColors.accent)),
        ),
      ],
    );
  }

  Future<void> _assign() async {
    final group = _selectedGroup!;
    final versionStr = _selectedVersion ?? '';
    final version = group.versions.firstWhere(
      (v) => v.versionStr == versionStr,
      orElse: () => group.latestVersion!,
    );

    setState(() { _working = true; _error = null; });

    try {
      final patchesDir = Directory(
          p.join(version.folderPath.path, 'game', '.patches'));
      patchesDir.createSync(recursive: true);

      final dest = File(
          p.join(patchesDir.path, widget.item.name));
      await widget.item.archivePath.copy(dest.path);

      // Register in UserData
      final metaKey =
          '${group.baseKey}::${versionStr.isEmpty ? '_' : versionStr}';
      ref.read(userDataProvider.notifier)
          .setPatchState(metaKey, widget.item.name, false);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _working = false; _error = e.toString(); });
    }
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
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
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textMuted)),
          isDense: true,
          isExpanded: true,
          style: GoogleFonts.inter(
              fontSize: 12, color: AppColors.textPrimary),
          dropdownColor: AppColors.bgCard,
          icon: const Icon(Icons.expand_more,
              size: 14, color: AppColors.textMuted),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelOf(item),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
