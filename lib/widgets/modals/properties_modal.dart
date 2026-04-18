import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/game_version.dart';
import '../../models/user_data.dart';
import '../../providers/library_provider.dart';
import '../../services/scanner_service.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void showPropertiesModal(BuildContext context, GameGroup group) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => PropertiesModal(group: group),
  );
}

// ── Tab enum ──────────────────────────────────────────────────────────────────

enum _Tab { general, launch, versions, patches, art }

// ── Root modal ────────────────────────────────────────────────────────────────

class PropertiesModal extends ConsumerStatefulWidget {
  final GameGroup group;
  const PropertiesModal({super.key, required this.group});

  @override
  ConsumerState<PropertiesModal> createState() => _PropertiesModalState();
}

class _PropertiesModalState extends ConsumerState<PropertiesModal> {
  _Tab _tab = _Tab.general;

  @override
  Widget build(BuildContext context) {
    // Always read freshest group from provider
    final libState = ref.watch(libraryProvider);
    final group = libState.groups.firstWhere(
      (g) => g.baseKey == widget.group.baseKey,
      orElse: () => widget.group,
    );
    final ud = ref.watch(userDataProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 580),
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
                _ModalHeader(
                  title: group.effectiveTitle,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TabSidebar(
                        selected: _tab,
                        onSelect: (t) => setState(() => _tab = t),
                      ),
                      const VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.border),
                      Expanded(child: _buildPanel(group, ud)),
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

  Widget _buildPanel(GameGroup group, UserData ud) {
    return switch (_tab) {
      _Tab.general  => _GeneralPanel(group: group, userData: ud),
      _Tab.launch   => _LaunchPanel(group: group),
      _Tab.versions => _VersionsPanel(group: group),
      _Tab.patches  => _PatchesPanel(group: group, userData: ud),
      _Tab.art      => _ArtPanel(group: group, userData: ud),
    };
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _ModalHeader({required this.title, required this.onClose});

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
          const Icon(Icons.tune_outlined, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            'Properties',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 14,
            color: AppColors.border,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _CloseBtn(onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseBtn({required this.onTap});
  @override
  State<_CloseBtn> createState() => _CloseBtnState();
}

class _CloseBtnState extends State<_CloseBtn> {
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
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x33C94040) : Colors.transparent,
            borderRadius: AppRadius.borderXs,
          ),
          child: Icon(Icons.close,
              size: 14,
              color: _hovered ? AppColors.danger : AppColors.textMuted),
        ),
      ),
    );
  }
}

// ── Tab sidebar ───────────────────────────────────────────────────────────────

class _TabSidebar extends StatelessWidget {
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;
  const _TabSidebar({required this.selected, required this.onSelect});

  static const _tabs = [
    (_Tab.general,  Icons.info_outline,         'General'),
    (_Tab.launch,   Icons.rocket_launch_outlined, 'Launch Options'),
    (_Tab.versions, Icons.layers_outlined,       'Versions'),
    (_Tab.patches,  Icons.extension_outlined,    'Patches'),
    (_Tab.art,      Icons.image_outlined,        'Art'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: ColoredBox(
        color: AppColors.bgCard,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: _tabs.map((t) => _SidebarTab(
            icon: t.$2,
            label: t.$3,
            selected: selected == t.$1,
            onTap: () => onSelect(t.$1),
          )).toList(),
        ),
      ),
    );
  }
}

class _SidebarTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarTab({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });
  @override
  State<_SidebarTab> createState() => _SidebarTabState();
}

class _SidebarTabState extends State<_SidebarTab> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final fg = widget.selected ? AppColors.accentLight : AppColors.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: widget.selected
              ? AppColors.bgActive
              : _hovered ? AppColors.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              if (widget.selected)
                Container(
                  width: 2, height: 14,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(width: 12),
              Icon(widget.icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared panel helpers ──────────────────────────────────────────────────────

class _PanelScroll extends StatelessWidget {
  final List<Widget> children;
  const _PanelScroll({required this.children});
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgSecondary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text,
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.textMuted)),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onEditingComplete;
  const _StyledField({
    required this.controller,
    required this.hint,
    this.onEditingComplete,
  });
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
        maxLines: 1,
        onEditingComplete: onEditingComplete,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

Widget _sectionGap() => const SizedBox(height: 20);

// ══════════════════════════════════════════════════════════════════════════════
// GENERAL PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _GeneralPanel extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  const _GeneralPanel({required this.group, required this.userData});

  @override
  ConsumerState<_GeneralPanel> createState() => _GeneralPanelState();
}

class _GeneralPanelState extends ConsumerState<_GeneralPanel> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.userData.customDisplayNames[widget.group.baseKey] ??
            widget.group.effectiveTitle);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final ud = widget.userData;
    final isHidden = ud.hidden.contains(g.baseKey);
    final v = g.latestVersion;

    return _PanelScroll(children: [
      // Display Name
      const _FieldLabel('DISPLAY NAME'),
      _StyledField(
        controller: _nameCtrl,
        hint: g.displayName,
        onEditingComplete: _saveName,
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: _SmBtn('Save Name', primary: true, onTap: _saveName),
      ),

      _sectionGap(),

      // Folder info
      const _FieldLabel('FOLDER'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadius.borderSm,
        ),
        child: Text(
          v?.folderPath.path ?? '—',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 11, color: AppColors.textSecondary),
        ),
      ),

      _sectionGap(),

      // Hide toggle
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hide from Library',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Hidden games are excluded from all views',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          _ToggleSwitch(
            value: isHidden,
            onChanged: (v) {
              ref.read(userDataProvider.notifier).setHidden(g.baseKey, v);
            },
          ),
        ],
      ),
    ]);
  }

  void _saveName() {
    final name = _nameCtrl.text.trim();
    ref.read(userDataProvider.notifier).setCustomDisplayName(
          widget.group.baseKey,
          name.isNotEmpty ? name : widget.group.displayName,
        );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LAUNCH PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _LaunchPanel extends ConsumerStatefulWidget {
  final GameGroup group;
  const _LaunchPanel({required this.group});

  @override
  ConsumerState<_LaunchPanel> createState() => _LaunchPanelState();
}

class _LaunchPanelState extends ConsumerState<_LaunchPanel> {
  late TextEditingController _argsCtrl;

  @override
  void initState() {
    super.initState();
    _argsCtrl = TextEditingController(
        text: widget.group.latestVersion?.metaLaunchArgs ?? '');
  }

  @override
  void dispose() {
    _argsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final v = g.latestVersion;

    return _PanelScroll(children: [
      // Executable Path
      const _FieldLabel('EXECUTABLE PATH'),
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                border: Border.all(color: AppColors.border),
                borderRadius: AppRadius.borderSm,
              ),
              child: Text(
                v?.exePath?.path ?? 'Auto-detected',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: v?.exePath != null
                      ? AppColors.textSecondary
                      : AppColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SmBtn('Browse', onTap: () => _pickExe(v)),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'The main executable used to launch this game. If not specified, we will attempt to auto-detect it.',
        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
      ),

      _sectionGap(),

      // Launch Arguments
      const _FieldLabel('LAUNCH ARGUMENTS'),
      _StyledField(
        controller: _argsCtrl,
        hint: 'e.g. -v --windowed',
        onEditingComplete: _saveArgs,
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: Text(
              'Advanced users only. Arguments will be passed to the game executable on launch.',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          _SmBtn('Save Arguments', primary: true, onTap: _saveArgs),
        ],
      ),
    ]);
  }

  void _saveArgs() async {
    final v = widget.group.latestVersion;
    if (v == null) return;

    final args = _argsCtrl.text.trim();
    final meta = Map<String, dynamic>.from(v.metadata)
      ..['launch_arguments'] = args;
    
    await saveGameMetadata(v.folderPath, meta);
    ref.read(libraryProvider.notifier).scan();
  }

  Future<void> _pickExe(GameVersion? v) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select executable',
      type: FileType.custom,
      allowedExtensions: ['exe'],
      lockParentWindow: true,
      initialDirectory: v?.folderPath.path,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (v != null) {
        final meta = Map<String, dynamic>.from(v.metadata)
          ..['exe_override'] = path;
        await saveGameMetadata(v.folderPath, meta);
        ref.read(libraryProvider.notifier).scan();
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VERSIONS PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _VersionsPanel extends ConsumerWidget {
  final GameGroup group;
  const _VersionsPanel({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = group.versions;

    if (versions.isEmpty) {
      return const Center(
        child: Text('No versions installed.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      );
    }

    return _PanelScroll(
      children: versions.reversed.map((v) {
        final isLatest = v == group.latestVersion;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.borderMd,
            border: Border.all(
              color: isLatest ? AppColors.accentDim : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          v.versionStr.isNotEmpty ? 'v${v.versionStr}' : 'Unknown version',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentGlow,
                              borderRadius: AppRadius.borderXs,
                            ),
                            child: Text('LATEST',
                                style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accentLight,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      v.folderPath.path,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (v.exePath != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '▶ ${p.basename(v.exePath!.path)}',
                        style: GoogleFonts.inter(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SmBtn(
                'Open Folder',
                onTap: () async {
                  await Process.run('explorer', [v.folderPath.path]);
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PATCHES PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _PatchesPanel extends ConsumerWidget {
  final GameGroup group;
  final UserData userData;
  const _PatchesPanel({required this.group, required this.userData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = group.versions;

    if (versions.isEmpty) {
      return const Center(
        child: Text('No versions installed.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      );
    }

    final items = <Widget>[];

    for (final v in versions.reversed) {
      final metaKey = '${group.baseKey}::${v.versionStr.isEmpty ? '_' : v.versionStr}';
      final patchDir = Directory(p.join(v.folderPath.path, 'game', '.patches'));
      final gameDir = Directory(p.join(v.folderPath.path, 'game'));

      // Collect all known patch files: active (in game/) + inactive (in .patches/)
      final Map<String, bool> patchStates = {
        ...userData.appliedPatches[metaKey] ?? {},
      };

      // Discover .rpyc/.rpy/.py patches on disk
      if (patchDir.existsSync()) {
        for (final f in patchDir.listSync().whereType<File>()) {
          final name = p.basename(f.path);
          patchStates.putIfAbsent(name, () => false);
        }
      }
      if (gameDir.existsSync()) {
        for (final f in gameDir.listSync().whereType<File>()) {
          final name = p.basename(f.path);
          if (name.endsWith('.rpyc') || name.endsWith('.rpy') || name.endsWith('.py')) {
            if (userData.appliedPatches[metaKey]?.containsKey(name) == true) {
              patchStates[name] = true;
            }
          }
        }
      }

      if (patchStates.isEmpty) continue;

      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            v.versionStr.isNotEmpty ? 'v${v.versionStr}' : 'Unknown version',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.4),
          ),
        ),
      );

      for (final entry in patchStates.entries) {
        final patchName = entry.key;
        final isActive = entry.value;
        items.add(_PatchRow(
          patchName: patchName,
          isActive: isActive,
          onToggle: (active) async {
            final error = await _togglePatch(v, metaKey, patchName, active, ref);
            if (error != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error), backgroundColor: AppColors.danger),
              );
            }
          },
        ));
      }
      items.add(const SizedBox(height: 8));
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No patches found.\nPlace .rpyc/.rpy/.py files in\ngame/.patches/ to manage them here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.7),
          ),
        ),
      );
    }

    return _PanelScroll(children: items);
  }

  Future<String?> _togglePatch(
    GameVersion v,
    String metaKey,
    String patchName,
    bool activate,
    WidgetRef ref,
  ) async {
    final gameDir = p.join(v.folderPath.path, 'game');
    final patchesDir = p.join(gameDir, '.patches');
    final activeFile = File(p.join(gameDir, patchName));
    final inactiveFile = File(p.join(patchesDir, patchName));

    try {
      Directory(patchesDir).createSync(recursive: true);
      if (activate) {
        // Move from .patches/ → game/
        if (inactiveFile.existsSync()) {
          await inactiveFile.rename(activeFile.path);
        }
      } else {
        // Move from game/ → .patches/
        if (activeFile.existsSync()) {
          await activeFile.rename(inactiveFile.path);
        }
      }
      ref.read(userDataProvider.notifier).setPatchState(metaKey, patchName, activate);
      return null;
    } catch (e) {
      return 'Failed to toggle patch: $e';
    }
  }
}

class _PatchRow extends StatelessWidget {
  final String patchName;
  final bool isActive;
  final ValueChanged<bool> onToggle;

  const _PatchRow({
    required this.patchName,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0x0A4A9E6E)
            : AppColors.bgCard,
        border: Border.all(
          color: isActive ? AppColors.accentDim : AppColors.border,
        ),
        borderRadius: AppRadius.borderSm,
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.extension : Icons.extension_off_outlined,
            size: 14,
            color: isActive ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              patchName,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          _ToggleSwitch(value: isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ART PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _ArtPanel extends ConsumerWidget {
  final GameGroup group;
  final UserData userData;
  const _ArtPanel({required this.group, required this.userData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customArtPath = userData.customArt[group.baseKey];
    final customArtFile = customArtPath != null ? File(customArtPath) : null;
    final hasCustom = customArtFile != null && customArtFile.existsSync();

    // Auto-detected art
    final autoImages = groupCarouselPaths(group, null);
    final autoCover = autoImages.isEmpty ? null : autoImages.first;

    return _PanelScroll(children: [
      const _FieldLabel('CUSTOM COVER ART'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview
          Container(
            width: 100,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.hardEdge,
            child: hasCustom
                ? Image.file(customArtFile, fit: BoxFit.cover)
                : autoCover != null
                    ? Image.file(autoCover, fit: BoxFit.cover)
                    : const Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textMuted, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCustom ? 'Custom art set' : 'Using auto-detected art',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (hasCustom) ...[
                  const SizedBox(height: 4),
                  Text(
                    customArtPath!,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SmBtn(
                      'Browse…',
                      primary: true,
                      onTap: () => _pickArt(context, ref),
                    ),
                    if (hasCustom) ...[
                      const SizedBox(width: 8),
                      _SmBtn(
                        'Clear',
                        onTap: () {
                          ref.read(userDataProvider.notifier)
                              .setCustomArt(group.baseKey, '');
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Supported: JPG, PNG, WEBP',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),

      _sectionGap(),
      const _FieldLabel('AUTO-DETECTED IMAGES'),
      if (autoImages.isEmpty)
        Text('No images found in game folder.',
            style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.textMuted))
      else
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: autoImages.length,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              return ClipRRect(
                borderRadius: AppRadius.borderSm,
                child: Image.file(
                  autoImages[i],
                  width: 120,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    width: 120,
                    height: 80,
                    color: AppColors.bgCard,
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Future<void> _pickArt(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select cover art',
      type: FileType.image,
      lockParentWindow: true,
    );
    if (result != null && result.files.single.path != null) {
      ref.read(userDataProvider.notifier)
          .setCustomArt(group.baseKey, result.files.single.path!);
    }
  }
}

// ── Shared tiny widgets ───────────────────────────────────────────────────────

class _SmBtn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _SmBtn(this.label, {this.onTap, this.primary = false});
  @override
  State<_SmBtn> createState() => _SmBtnState();
}

class _SmBtnState extends State<_SmBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hovered ? AppColors.accentLight : AppColors.accent)
        : (_hovered ? AppColors.bgActive : AppColors.bgHover);
    final fg = widget.primary ? Colors.white : AppColors.textSecondary;
    final border = widget.primary ? AppColors.accentDim : AppColors.borderLight;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.bgInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value ? AppColors.accentDim : AppColors.borderLight),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14, height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: value ? Colors.white : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
