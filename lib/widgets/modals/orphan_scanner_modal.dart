import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/scanner_service.dart';

void showOrphanScannerModal(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const OrphanScannerModal(),
  );
}

class OrphanScannerModal extends ConsumerStatefulWidget {
  const OrphanScannerModal({super.key});

  @override
  ConsumerState<OrphanScannerModal> createState() => _OrphanScannerModalState();
}

class _OrphanScannerModalState extends ConsumerState<OrphanScannerModal> {
  List<FileSystemEntity> _orphans = [];
  bool _scanning = true;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final libDir = ref.read(libraryDirProvider);
    final groups = ref.read(libraryProvider).groups;
    
    if (libDir.isEmpty) {
      setState(() {
        _orphans = [];
        _scanning = false;
      });
      return;
    }

    final result = await Future(() => ScannerService.findOrphans(Directory(libDir), groups));
    
    if (mounted) {
      setState(() {
        _orphans = result;
        _scanning = false;
      });
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        title: Text('Delete Files?', style: GoogleFonts.inter(color: Colors.white)),
        content: Text('Are you sure you want to delete ${_selectedPaths.length} selected items? This cannot be undone.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final path in _selectedPaths) {
        final entity = _orphans.firstWhere((e) => e.path == path);
        try {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else {
            await entity.delete();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete $path: $e')),
            );
          }
        }
      }
      _selectedPaths.clear();
      _scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: AppRadius.borderLg,
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadius.borderLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _Header(onClose: () => Navigator.of(context).pop(), onRefresh: _scan),

                // Content
                Expanded(
                  child: _scanning
                      ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                      : _orphans.isEmpty
                          ? _EmptyState()
                          : _OrphanList(
                              orphans: _orphans,
                              selectedPaths: _selectedPaths,
                              onToggle: _toggleSelection,
                            ),
                ),

                // Footer
                if (!_scanning && _orphans.isNotEmpty)
                  _Footer(
                    selectedCount: _selectedPaths.length,
                    onDelete: _deleteSelected,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  const _Header({required this.onClose, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Orphaned File Scanner',
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text('Files in library root not recognized as games',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
            onPressed: onRefresh,
            tooltip: 'Rescan',
          ),
          const SizedBox(width: 8),
          _CloseX(onTap: onClose),
        ],
      ),
    );
  }
}

class _OrphanList extends StatelessWidget {
  final List<FileSystemEntity> orphans;
  final Set<String> selectedPaths;
  final Function(String) onToggle;

  const _OrphanList({
    required this.orphans,
    required this.selectedPaths,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: orphans.length,
      itemBuilder: (context, index) {
        final item = orphans[index];
        final name = p.basename(item.path);
        final isDir = item is Directory;
        final isSelected = selectedPaths.contains(item.path);

        return _OrphanTile(
          name: name,
          path: item.path,
          isDir: isDir,
          isSelected: isSelected,
          onToggle: () => onToggle(item.path),
        );
      },
    );
  }
}

class _OrphanTile extends StatefulWidget {
  final String name;
  final String path;
  final bool isDir;
  final bool isSelected;
  final VoidCallback onToggle;

  const _OrphanTile({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_OrphanTile> createState() => _OrphanTileState();
}

class _OrphanTileState extends State<_OrphanTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.accent.withValues(alpha: 0.1)
                : (_hovered ? AppColors.bgHover : Colors.transparent),
            borderRadius: AppRadius.borderMd,
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : (_hovered ? AppColors.borderLight : Colors.transparent),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: widget.isSelected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Icon(
                widget.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                size: 18,
                color: widget.isDir ? Colors.amber.withValues(alpha: 0.7) : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    Text(widget.path,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis),
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

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: AppColors.accent.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No orphaned files found',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Everything in your library root is accounted for.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onDelete;

  const _Footer({required this.selectedCount, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text('$selectedCount items selected',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: selectedCount > 0 ? onDelete : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete Selected'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.bgHover,
              disabledForegroundColor: AppColors.textMuted,
              textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.borderSm),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseX extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseX({required this.onTap});
  @override
  State<_CloseX> createState() => _CloseXState();
}

class _CloseXState extends State<_CloseX> {
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
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x33C94040) : Colors.transparent,
            borderRadius: AppRadius.borderXs,
          ),
          child: Icon(Icons.close, size: 16,
              color: _hovered ? AppColors.danger : AppColors.textMuted),
        ),
      ),
    );
  }
}
