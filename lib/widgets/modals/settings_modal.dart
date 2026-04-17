import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void showSettingsModal(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const SettingsModal(),
  );
}

// ── Tab enum ──────────────────────────────────────────────────────────────────

enum _Tab { general, network, appearance, archives, about }

// ── Root modal widget ─────────────────────────────────────────────────────────

class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key});

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal> {
  _Tab _tab = _Tab.general;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
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
                _ModalHeader(onClose: () => Navigator.of(context).pop()),
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
                      Expanded(child: _buildPanel()),
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

  Widget _buildPanel() {
    return switch (_tab) {
      _Tab.general    => const _GeneralPanel(),
      _Tab.network    => const _NetworkPanel(),
      _Tab.appearance => const _AppearancePanel(),
      _Tab.archives   => const _ArchivesPanel(),
      _Tab.about      => const _AboutPanel(),
    };
  }
}

// ── Modal header ──────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _ModalHeader({required this.onClose});

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
          const Icon(Icons.settings_outlined,
              size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            'Settings',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _CloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0x33C94040)
                : Colors.transparent,
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
    (_Tab.general,    Icons.tune_outlined,        'General'),
    (_Tab.network,    Icons.wifi_outlined,         'Network'),
    (_Tab.appearance, Icons.palette_outlined,      'Appearance'),
    (_Tab.archives,   Icons.folder_zip_outlined,   'Archives'),
    (_Tab.about,      Icons.info_outline,          'About'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: ColoredBox(
        color: AppColors.bgCard,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: _tabs
              .map((t) => _SidebarTab(
                    icon: t.$2,
                    label: t.$3,
                    selected: selected == t.$1,
                    onTap: () => onSelect(t.$1),
                  ))
              .toList(),
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarTab> createState() => _SidebarTabState();
}

class _SidebarTabState extends State<_SidebarTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.bgActive
        : _hovered
            ? AppColors.bgHover
            : Colors.transparent;
    final fg = widget.selected ? AppColors.accentLight : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              if (widget.selected)
                Container(
                  width: 2,
                  height: 14,
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
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PANELS
// ══════════════════════════════════════════════════════════════════════════════

// ── Shared panel scaffold ─────────────────────────────────────────────────────

class _PanelScroll extends StatelessWidget {
  final List<Widget> children;
  const _PanelScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgSecondary,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: children,
      ),
    );
  }
}

// ── Shared setting widgets ────────────────────────────────────────────────────

class _SettingGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.borderMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: children
                .expand((w) sync* {
                  yield w;
                  if (w != children.last) {
                    yield const Divider(
                        height: 1, thickness: 1, color: AppColors.border);
                  }
                })
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.label,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}

class _ToggleSwitch extends ConsumerWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;

  const _ToggleSwitch({
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: disabled ? null : () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.bgHover
              : value
                  ? AppColors.accent
                  : AppColors.bgInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: disabled
                ? AppColors.border
                : value
                    ? AppColors.accentDim
                    : AppColors.borderLight,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: disabled
                  ? AppColors.textMuted
                  : value
                      ? Colors.white
                      : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _SmallButton(this.label,
      {this.onTap, this.primary = false});

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hovered ? AppColors.accentLight : AppColors.accent)
        : (_hovered ? AppColors.bgActive : AppColors.bgHover);

    final fg = widget.primary ? Colors.white : AppColors.textSecondary;

    final border =
        widget.primary ? AppColors.accentDim : AppColors.borderLight;

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
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w500, color: fg),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GENERAL PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _GeneralPanel extends ConsumerWidget {
  const _GeneralPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _PanelScroll(children: [
      _SettingGroup(title: 'LIBRARY', children: [
        _SettingRow(
          label: 'Library Directory',
          subtitle: 'Root folder containing your visual novels',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  settings.libraryDir.isEmpty
                      ? 'Not set'
                      : settings.libraryDir,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: settings.libraryDir.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(
                'Browse',
                onTap: () async {
                  final result = await FilePicker.platform.getDirectoryPath(
                    dialogTitle: 'Select your library directory',
                    lockParentWindow: true,
                  );
                  if (result != null) {
                    notifier.setLibraryDir(result);
                    ref.read(libraryProvider.notifier).scan();
                  }
                },
              ),
            ],
          ),
        ),
        _SettingRow(
          label: 'Slideshow Interval',
          subtitle: 'Auto-advance time for screenshot carousel',
          trailing: _SliderRow(
            value: settings.slideshowInterval,
            min: 0.5,
            max: 30.0,
            divisions: 59,
            label: '${settings.slideshowInterval.toStringAsFixed(1)}s',
            onChanged: notifier.setSlideshowInterval,
          ),
        ),
        _SettingRow(
          label: 'Auto-Backup',
          subtitle: 'Backup library data on startup',
          trailing: _ToggleSwitch(
            value: settings.autoBackup,
            onChanged: notifier.setAutoBackup,
          ),
        ),
      ]),
      _SettingGroup(title: 'MAINTENANCE', children: [
        _SettingRow(
          label: 'Orphaned File Scanner',
          subtitle: 'Find unrecognised files in your library root',
          trailing: _SmallButton(
            '🔍  Scan Now',
            onTap: () {
              // TODO: Phase 9 — orphan scanner modal
            },
          ),
        ),
      ]),
    ]);
  }
}

class _SliderRow extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late double _val;

  @override
  void initState() {
    super.initState();
    _val = widget.value;
  }

  @override
  void didUpdateWidget(_SliderRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _val = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 140,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.bgInput,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accentGlow,
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _val.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) => setState(() => _val = v),
              onChangeEnd: widget.onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NETWORK PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _NetworkPanel extends ConsumerWidget {
  const _NetworkPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final locked = settings.lockdown;

    return _PanelScroll(children: [
      _SettingGroup(title: 'ACCESS CONTROL', children: [
        // Lockdown row — highlighted
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: locked
                ? const Color(0x0FC94040)
                : Colors.transparent,
            borderRadius: AppRadius.borderSm,
            border: Border.all(
              color: locked
                  ? const Color(0x33C94040)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCKDOWN MODE',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: locked
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Master kill-switch for all network access.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              _ToggleSwitch(
                value: locked,
                onChanged: notifier.setLockdown,
              ),
            ],
          ),
        ),
        _SettingRow(
          label: 'Update Checks',
          subtitle: 'Check for VN Pathfinder updates on startup',
          trailing: _ToggleSwitch(
            value: settings.checkUpdates,
            onChanged: notifier.setCheckUpdates,
            disabled: locked,
          ),
        ),
        _SettingRow(
          label: 'Metadata Scraping',
          subtitle: 'Fetch game info from F95Zone, LewdCorner, itch.io',
          trailing: _ToggleSwitch(
            value: settings.fetchMetadata,
            onChanged: notifier.setFetchMetadata,
            disabled: locked,
          ),
        ),
        _SettingRow(
          label: 'Site Logins',
          subtitle: 'Enable authentication to access restricted content',
          trailing: _ToggleSwitch(
            value: settings.allowProviderLogin,
            onChanged: notifier.setAllowProviderLogin,
            disabled: locked,
          ),
        ),
        _SettingRow(
          label: 'Download Page Links',
          subtitle: 'Show links to game source pages',
          trailing: _ToggleSwitch(
            value: settings.allowDownloadLinks,
            onChanged: notifier.setAllowDownloadLinks,
            disabled: locked,
          ),
        ),
      ]),
      _SettingGroup(title: 'SITE LOGINS', children: [
        _LoginCard(
          site: 'F95Zone',
          credentials: settings.siteCredentials['f95zone'] ?? {},
          onSave: (u, p) => notifier.update(
            (s) => s.copyWith(siteCredentials: {
              ...s.siteCredentials,
              'f95zone': {'username': u, 'password': p},
            }),
          ),
          disabled: locked,
        ),
        _LoginCard(
          site: 'Lewd Corner',
          credentials: settings.siteCredentials['lewdcorner'] ?? {},
          onSave: (u, p) => notifier.update(
            (s) => s.copyWith(siteCredentials: {
              ...s.siteCredentials,
              'lewdcorner': {'username': u, 'password': p},
            }),
          ),
          disabled: locked,
        ),
      ]),
    ]);
  }
}

class _LoginCard extends StatefulWidget {
  final String site;
  final Map<String, String> credentials;
  final void Function(String user, String pass) onSave;
  final bool disabled;

  const _LoginCard({
    required this.site,
    required this.credentials,
    required this.onSave,
    required this.disabled,
  });

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  late final TextEditingController _user;
  late final TextEditingController _pass;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(
        text: widget.credentials['username'] ?? '');
    _pass = TextEditingController(
        text: widget.credentials['password'] ?? '');
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _connected =>
      (widget.credentials['username'] ?? '').isNotEmpty &&
      (widget.credentials['password'] ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.site,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _connected
                      ? const Color(0x1A4A9E6E)
                      : const Color(0x1AC94040),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _connected ? '✓ Connected' : '✕ Not connected',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _connected
                        ? AppColors.accent
                        : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CredField(
              label: 'Username',
              controller: _user,
              obscure: false,
              disabled: widget.disabled),
          const SizedBox(height: 4),
          _CredField(
              label: 'Password',
              controller: _pass,
              obscure: true,
              disabled: widget.disabled),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _SmallButton(
              'Save',
              primary: true,
              onTap: widget.disabled
                  ? null
                  : () => widget.onSave(_user.text, _pass.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool disabled;

  const _CredField({
    required this.label,
    required this.controller,
    required this.obscure,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textMuted)),
        ),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: disabled ? AppColors.bgCard : AppColors.bgInput,
              border: Border.all(color: AppColors.border),
              borderRadius: AppRadius.borderSm,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: controller,
              obscureText: obscure,
              enabled: !disabled,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// APPEARANCE PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _AppearancePanel extends ConsumerWidget {
  const _AppearancePanel();

  static const _accentColors = [
    (Color(0xFF4A9E6E), 'Emerald'),
    (Color(0xFF4A90D9), 'Ocean Blue'),
    (Color(0xFF9B59B6), 'Amethyst'),
    (Color(0xFFE67E22), 'Amber'),
    (Color(0xFFC94040), 'Ruby'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _PanelScroll(children: [
      _SettingGroup(title: 'THEME', children: [
        _SettingRow(
          label: 'Color Theme',
          subtitle: 'Choose your preferred color scheme',
          trailing: _DropdownRow(
            value: settings.theme,
            items: const ['dark', 'light', 'system'],
            labels: const ['Dark', 'Light', 'System'],
            onChanged: notifier.setTheme,
          ),
        ),
        _SettingRow(
          label: 'Accent Color',
          subtitle: 'Primary accent for highlights and buttons',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: _accentColors
                .map((c) => _ColorSwatch(
                      color: c.$1,
                      tooltip: c.$2,
                      selected:
                          settings.accentColor == _colorHex(c.$1),
                      onTap: () =>
                          notifier.setAccentColor(_colorHex(c.$1)),
                    ))
                .toList(),
          ),
        ),
        _SettingRow(
          label: 'Font Size',
          subtitle: 'Adjust the base interface font size',
          trailing: _SliderRow(
            value: settings.fontSize,
            min: 11,
            max: 16,
            divisions: 5,
            label: '${settings.fontSize.toInt()}px',
            onChanged: notifier.setFontSize,
          ),
        ),
      ]),
    ]);
  }

  static String _colorHex(Color c) =>
      '#${c.r.round().toRadixString(16).padLeft(2, '0')}'
      '${c.g.round().toRadixString(16).padLeft(2, '0')}'
      '${c.b.round().toRadixString(16).padLeft(2, '0')}';
}

class _ColorSwatch extends StatefulWidget {
  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.selected
                    ? Colors.white
                    : _hovered
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.transparent,
                width: 2,
              ),
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                          color: widget.color.withValues(alpha: 0.5),
                          blurRadius: 6)
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String value;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String> onChanged;

  const _DropdownRow({
    required this.value,
    required this.items,
    required this.labels,
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
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: GoogleFonts.inter(
              fontSize: 12, color: AppColors.textPrimary),
          dropdownColor: AppColors.bgCard,
          icon: const Icon(Icons.expand_more,
              size: 14, color: AppColors.textMuted),
          items: List.generate(
            items.length,
            (i) => DropdownMenuItem(
              value: items[i],
              child: Text(labels[i]),
            ),
          ),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ARCHIVES PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _ArchivesPanel extends ConsumerWidget {
  const _ArchivesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final sevenZipOk = _check7zip();

    return _PanelScroll(children: [
      _SettingGroup(title: 'REQUIREMENTS', children: [
        _SettingRow(
          label: '7-Zip Status',
          subtitle: 'Required for .rar and .rpa formats',
          trailing: sevenZipOk
              ? Text('✓ Installed',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent))
              : Text('✕ Not found',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
        ),
      ]),
      _SettingGroup(title: 'EXTRACTION', children: [
        _SettingRow(
          label: 'Simultaneous Extractions',
          subtitle: 'Number of concurrent extraction jobs',
          trailing: _SliderRow(
            value: settings.concurrentExtractions.toDouble(),
            min: 1,
            max: 4,
            divisions: 3,
            label: '${settings.concurrentExtractions}',
            onChanged: (v) =>
                notifier.setConcurrentExtractions(v.round()),
          ),
        ),
        _SettingRow(
          label: 'Delete After Extract',
          subtitle: 'Auto-delete .zip archives after successful extraction',
          trailing: _ToggleSwitch(
            value: settings.deleteAfterExtract,
            onChanged: notifier.setDeleteAfterExtract,
          ),
        ),
      ]),
    ]);
  }

  bool _check7zip() {
    for (final path in [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ]) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ABOUT PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return _PanelScroll(children: [
      Center(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accent, AppColors.accentDim],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                'VP',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'VN Pathfinder',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 2.0.0-alpha · Flutter Rewrite',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              'Your complete visual novel library manager.\nTrack, organise, launch, and maintain your collection.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Made with ♥ by NikoCloud\nApache License 2.0 — No telemetry. No accounts. Zero network by default.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textMuted, height: 1.8),
            ),
          ],
        ),
      ),
    ]);
  }
}
