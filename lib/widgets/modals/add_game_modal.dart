import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../theme.dart';
import '../../models/game_version.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/scanner_service.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void showAddGameModal(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const AddGameModal(),
  );
}

// ── Modal ─────────────────────────────────────────────────────────────────────

class AddGameModal extends ConsumerStatefulWidget {
  const AddGameModal({super.key});

  @override
  ConsumerState<AddGameModal> createState() => _AddGameModalState();
}

class _AddGameModalState extends ConsumerState<AddGameModal> {
  File? _selectedFile;
  Directory? _selectedDir;
  GameVersion? _detected;
  bool _scanning = false;
  bool _extracting = false;
  double _extractionProgress = 0;
  String? _error;
  String? _warning;

  // Manual overrides
  late TextEditingController _nameCtrl;
  late TextEditingController _versionCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _versionCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _Header(onClose: () => Navigator.of(context).pop()),

                // Body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Folder picker
                      _FieldLabel('GAME FOLDER'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.bgInput,
                                border: Border.all(color: AppColors.border),
                                borderRadius: AppRadius.borderSm,
                              ),
                              child: Text(
                                _selectedFile != null
                                    ? p.basename(_selectedFile!.path)
                                    : (_selectedDir?.path ?? 'No selection'),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: (_selectedFile != null || _selectedDir != null)
                                      ? AppColors.textSecondary
                                      : AppColors.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Btn('Folder…', onTap: _pickFolder),
                          const SizedBox(width: 4),
                          _Btn('Archive…', primary: true, onTap: _pickArchive),
                        ],
                      ),

                      // Extraction Progress
                      if (_extracting) ...[
                        const SizedBox(height: 16),
                        _FieldLabel('EXTRACTING...'),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: AppRadius.borderXs,
                          child: LinearProgressIndicator(
                            value: _extractionProgress,
                            color: AppColors.accent,
                            backgroundColor: AppColors.bgHover,
                            minHeight: 8,
                          ),
                        ),
                      ],

                      // Scan result
                      if (_scanning) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(
                          color: AppColors.accent,
                          backgroundColor: AppColors.bgHover,
                        ),
                      ] else if (_error != null) ...[
                        const SizedBox(height: 12),
                        _StatusBox(message: _error!, isError: true),
                      ] else if (_detected != null) ...[
                        const SizedBox(height: 16),
                        _DetectedCard(version: _detected!),
                        if (_warning != null) ...[
                          const SizedBox(height: 8),
                          _StatusBox(message: _warning!, isError: false),
                        ],
                        const SizedBox(height: 16),
                        _FieldLabel('DISPLAY NAME OVERRIDE'),
                        const SizedBox(height: 6),
                        _TextField(
                          controller: _nameCtrl,
                          hint: _detected!.effectiveTitle,
                        ),
                        const SizedBox(height: 12),
                        _FieldLabel('VERSION OVERRIDE'),
                        const SizedBox(height: 6),
                        _TextField(
                          controller: _versionCtrl,
                          hint: _detected!.versionStr.isNotEmpty
                              ? _detected!.versionStr
                              : 'e.g. 1.0.0',
                        ),
                      ],
                    ],
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Btn('Cancel',
                          onTap: () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      _Btn(
                        'Add to Library',
                        primary: true,
                        onTap: _detected != null ? _addGame : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select game folder',
      lockParentWindow: true,
    );
    if (result == null) return;

    final dir = Directory(result);
    setState(() {
      _selectedDir = dir;
      _selectedFile = null;
      _scanning = true;
      _detected = null;
      _error = null;
      _warning = null;
    });

    try {
      final version = await Future(() => scanGameVersion(dir));
      _handleScanResult(version, dir);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Error scanning folder: $e';
      });
    }
  }

  Future<void> _pickArchive() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select game archive',
      type: FileType.custom,
      allowedExtensions: ['zip', 'rar', 'tar', 'gz'],
      lockParentWindow: true,
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    setState(() {
      _selectedFile = file;
      _selectedDir = null;
      _extracting = false;
      _scanning = true;
      _detected = null;
      _error = null;
      _warning = null;
    });

    // For archives, we don't scan until extracted, 
    // but we can parse the name to show intent.
    final (baseKey, versionStr, displayName) = parseFolderName(p.basenameWithoutExtension(file.path));
    
    setState(() {
      _scanning = false;
      _warning = 'Archive selected. It will be extracted to your library root upon adding.';
    });

    // Auto-detect version if possible from filename
    final mockVersion = GameVersion(
      folderName: p.basenameWithoutExtension(file.path),
      folderPath: Directory(''), // Not yet extracted
      baseKey: baseKey,
      versionStr: versionStr,
      displayName: displayName,
      exePath: null,
      localSaveDir: Directory(''),
      metadata: {},
      isRenpy: false,
    );

    setState(() {
      _detected = mockVersion;
    });
  }

  void _handleScanResult(GameVersion? version, Directory dir) {
    if (!mounted) return;
    if (version == null) {
      setState(() {
        _scanning = false;
        _error = 'No game detected in this folder.\n'
            'Expected a RenPy game (with game/ subfolder) or an executable game.';
      });
      return;
    }

    // Check if already in library
    final libDir = ref.read(libraryDirProvider);
    final isInsideLib =
        p.isWithin(libDir, dir.path) || p.equals(libDir, dir.path);
    String? warn;
    if (!isInsideLib) {
      warn = '⚠ This folder is outside your library directory.\n'
          'It will be scanned but won\'t appear on future library rescans.';
    }

    // Check for duplicate
    final existing = ref
        .read(libraryProvider)
        .groups
        .where((g) => g.baseKey == version.baseKey)
        .toList();
    if (existing.isNotEmpty) {
      warn =
          '⚠ A game with this base name already exists: "${existing.first.effectiveTitle}".\n'
          'Adding will create an additional version entry.';
    }

    _nameCtrl.text = '';
    _versionCtrl.text = '';
    setState(() {
      _scanning = false;
      _detected = version;
      _warning = warn;
    });
  }

  Future<void> _addGame() async {
    if (_detected == null) return;

    if (_selectedFile != null) {
      // Handle extraction
      final libDir = ref.read(libraryDirProvider);
      if (libDir.isEmpty) {
        setState(() => _error = 'Library directory not set in Settings.');
        return;
      }

      final targetName = _nameCtrl.text.isNotEmpty 
          ? _nameCtrl.text 
          : p.basenameWithoutExtension(_selectedFile!.path);
      final targetDir = Directory(p.join(libDir, targetName));

      if (targetDir.existsSync()) {
        setState(() => _error = 'Target folder already exists in library: $targetName');
        return;
      }

      setState(() {
        _extracting = true;
        _extractionProgress = 0.1; // Initial kick
      });

      try {
        await ScannerService.extractArchive(_selectedFile!, targetDir);
        setState(() => _extractionProgress = 1.0);
        
        // Now scan the extracted folder
        final version = await Future(() => scanGameVersion(targetDir));
        if (version != null) {
          _detected = version;
          // Apply overrides if any
          final name = _nameCtrl.text.trim();
          final ver = _versionCtrl.text.trim();
          if (name.isNotEmpty || ver.isNotEmpty) {
            final meta = Map<String, dynamic>.from(version.metadata);
            if (name.isNotEmpty) meta['title'] = name;
            if (ver.isNotEmpty) meta['version_override'] = ver;
            await saveGameMetadata(version.folderPath, meta);
          }
        }
      } catch (e) {
        setState(() {
          _extracting = false;
          _error = 'Extraction failed: $e';
        });
        return;
      }
    } else {
      // Normal folder add
      final version = _detected!;
      final name = _nameCtrl.text.trim();
      final ver = _versionCtrl.text.trim();

      if (name.isNotEmpty || ver.isNotEmpty) {
        final meta = Map<String, dynamic>.from(version.metadata);
        if (name.isNotEmpty) meta['title'] = name;
        if (ver.isNotEmpty) meta['version_override'] = ver;
        await saveGameMetadata(version.folderPath, meta);
      }
    }

    // Rescan library
    ref.read(libraryProvider.notifier).scan();
    if (mounted) Navigator.of(context).pop();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

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
          const Icon(Icons.add_circle_outline, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Text('Add Game',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const Spacer(),
          _CloseX(onTap: onClose),
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
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x33C94040) : Colors.transparent,
            borderRadius: AppRadius.borderXs,
          ),
          child: Icon(Icons.close, size: 14,
              color: _hovered ? AppColors.danger : AppColors.textMuted),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 9, fontWeight: FontWeight.w700,
          letterSpacing: 0.6, color: AppColors.textMuted));
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _TextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

class _DetectedCard extends StatelessWidget {
  final GameVersion version;
  const _DetectedCard({required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0A4A9E6E),
        border: Border.all(color: AppColors.accentDim),
        borderRadius: AppRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Game detected',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentLight)),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow('Title', version.effectiveTitle),
          _InfoRow('Version', version.versionStr.isNotEmpty ? version.versionStr : '—'),
          _InfoRow('Engine', version.isRenpy ? 'Ren\'Py' : 'Other'),
          if (version.exePath != null)
            _InfoRow('Exe', p.basename(version.exePath!.path)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final String message;
  final bool isError;
  const _StatusBox({required this.message, required this.isError});
  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: AppRadius.borderSm,
      ),
      child: Text(message,
          style: GoogleFonts.inter(fontSize: 11, color: color, height: 1.5)),
    );
  }
}

class _Btn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _Btn(this.label, {this.onTap, this.primary = false});
  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = widget.primary
        ? (enabled
            ? (_hovered ? AppColors.accentLight : AppColors.accent)
            : AppColors.bgHover)
        : (_hovered ? AppColors.bgActive : AppColors.bgHover);
    final fg = widget.primary
        ? (enabled ? Colors.white : AppColors.textMuted)
        : AppColors.textSecondary;
    final border = widget.primary
        ? (enabled ? AppColors.accentDim : AppColors.border)
        : AppColors.borderLight;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.borderSm,
            border: Border.all(color: border),
          ),
          child: Text(widget.label,
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
        ),
      ),
    );
  }
}
