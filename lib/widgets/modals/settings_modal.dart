import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../theme.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/feed_provider.dart';
import '../../services/metadata_service.dart';
import '../../services/scraping_service.dart';
import 'orphan_scanner_modal.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void showSettingsModal(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const SettingsModal(),
  );
}

// ── Tab enum ──────────────────────────────────────────────────────────────────

enum _Tab { general, network, appearance, archives, feed, about }

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
      _Tab.feed       => const _FeedPanel(),
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
    (_Tab.feed,       Icons.rss_feed_outlined,     'Feed'),
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
              showOrphanScannerModal(context);
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
        const _VndbInfoCard(),
        _XenforoLoginCard(
          site: 'F95Zone',
          baseUrl: 'https://f95zone.to',
          credentials: settings.siteCredentials['f95zone'] ?? {},
          onLogin: (cookies) => notifier.setSiteCredentials('f95zone', cookies),
          onDisconnect: () => notifier.clearSiteCredentials('f95zone'),
          disabled: locked,
        ),
        _XenforoLoginCard(
          site: 'Lewd Corner',
          baseUrl: 'https://lewdcorner.com',
          credentials: settings.siteCredentials['lewdcorner'] ?? {},
          onLogin: (cookies) => notifier.setSiteCredentials('lewdcorner', cookies),
          onDisconnect: () => notifier.clearSiteCredentials('lewdcorner'),
          disabled: locked,
        ),
        _ItchioLoginCard(
          cookies: settings.siteCredentials['itchio'] ?? {},
          onUpdateCookies: (ck) => notifier.setSiteCredentials('itchio', ck),
          onClearCookies: () => notifier.clearSiteCredentials('itchio'),
          disabled: locked,
        ),
      ]),
    ]);
  }
}

// ── XenForo browser login card (F95Zone / LewdCorner) ─────────────────────────
// Uses WebView2 instead of plain HTTP so Cloudflare / bot-protection is bypassed.

class _XenforoLoginCard extends ConsumerStatefulWidget {
  final String site;
  final String baseUrl;
  final Map<String, String> credentials;
  final void Function(Map<String, String> cookies) onLogin;
  final VoidCallback onDisconnect;
  final bool disabled;

  const _XenforoLoginCard({
    required this.site,
    required this.baseUrl,
    required this.credentials,
    required this.onLogin,
    required this.onDisconnect,
    required this.disabled,
  });

  @override
  ConsumerState<_XenforoLoginCard> createState() => _XenforoLoginCardState();
}

class _XenforoLoginCardState extends ConsumerState<_XenforoLoginCard> {
  bool _refreshing = false;

  bool get _connected =>
      widget.credentials['connected'] == 'true' ||
      (widget.credentials['xf_session'] ?? '').isNotEmpty ||
      (widget.credentials['xf_user'] ?? '').isNotEmpty;

  String get _displayName {
    final u = widget.credentials['username'] ?? '';
    return u.isNotEmpty ? u : 'Connected';
  }

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
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x1A4A9E6E),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Browser Login',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: AppColors.accentSilver,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (!_connected || _refreshing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: _refreshing
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          )
                        : IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.refresh,
                                size: 16, color: AppColors.textMuted),
                            onPressed: widget.disabled ? null : _refreshSession,
                            tooltip: 'Refresh session',
                          ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _connected
                      ? const Color(0x1A4A9E6E)
                      : const Color(0x1AC94040),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                   _connected ? '✓ $_displayName' : '✕ Not connected',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _connected ? AppColors.accent : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.site} requires a logged-in browser session. '
            'Click "Login with browser" to open an in-app login window.',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SmallButton(
                'Login with browser',
                primary: !_connected,
                onTap: widget.disabled ? null : () => _openLogin(context),
              ),
              if (_connected) ...[
                const SizedBox(width: 8),
                _SmallButton(
                  'Disconnect',
                  onTap: widget.disabled ? null : widget.onDisconnect,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSession() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      final scraper = ref.read(scrapingServiceProvider);
      // Wait for it to be ready
      await scraper.ready;

      // Extract cookies and check login state
      final js = """
        (() => {
          const loggedIn = !!(
            document.querySelector('a[href*="/logout/"]') || 
            document.querySelector('.p-navgroup-link--user') ||
            document.documentElement.getAttribute('data-logged-in') === 'true'
          );
          if (!loggedIn) return null;
          
          let username = null;
          const userEl = document.querySelector('.p-navgroup-link--user .p-navgroup-linkText') || 
                         document.querySelector('.p-account .p-navgroup-linkText');
          if (userEl) username = userEl.innerText.trim();
          
          return { loggedIn, username };
        })()
      """;

      final result = await scraper.evalOnPage('${widget.baseUrl}/', js);
      
      if (result != null && result['loggedIn'] == true) {
        widget.onLogin(<String, String>{
          'connected': 'true',
          if (result['username'] != null) 'username': result['username'] as String,
        });
      } else {
        // Not logged in or detection failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not detect an active session.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openLogin(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _XenforoLoginDialog(
        site: widget.site,
        baseUrl: widget.baseUrl,
        onSuccess: widget.onLogin,
      ),
    );
  }
}

/// itch.io uses a browser-based login flow (adult content is gated behind
/// an authenticated session — a public API key is not sufficient).
/// Cookies extracted from the embedded WebView2 session are stored here.
/// The user opens the itch.io login page in a dialog, logs in, and the app
/// captures the session cookies automatically on successful navigation to /my-feed.
class _ItchioLoginCard extends ConsumerStatefulWidget {
  final Map<String, String> cookies;
  final void Function(Map<String, String> cookies) onUpdateCookies;
  final VoidCallback onClearCookies;
  final bool disabled;

  const _ItchioLoginCard({
    required this.cookies,
    required this.onUpdateCookies,
    required this.onClearCookies,
    required this.disabled,
  });

  @override
  ConsumerState<_ItchioLoginCard> createState() => _ItchioLoginCardState();
}

class _ItchioLoginCardState extends ConsumerState<_ItchioLoginCard> {
  bool _refreshing = false;

  bool get _connected => widget.cookies.isNotEmpty;

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
                'itch.io',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x1A4A9E6E),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Browser Login',
                  style: GoogleFonts.inter(
                      fontSize: 9,
                      color: AppColors.accentSilver,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (!_connected || _refreshing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: _refreshing
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          )
                        : IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.refresh,
                                size: 16, color: AppColors.textMuted),
                            onPressed: widget.disabled ? null : _refreshSession,
                            tooltip: 'Refresh session',
                          ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    color:
                        _connected ? AppColors.accent : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'itch.io requires a logged-in browser session to access adult content. '
            'Click "Login with browser" to open an in-app login window.',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SmallButton(
                'Login with browser',
                primary: !_connected,
                onTap: widget.disabled ? null : () => _openLogin(context),
              ),
              if (_connected) ...[
                const SizedBox(width: 8),
                _SmallButton(
                  'Disconnect',
                  onTap: widget.disabled ? null : widget.onClearCookies,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSession() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      final scraper = ref.read(scrapingServiceProvider);
      await scraper.ready;

      const js = """
        (() => {
          return !!(document.querySelector('.user_menu') || document.querySelector('a[href*="/logout"]'));
        })()
      """;

      final result = await scraper.evalOnPage('https://itch.io/', js);
      
      if (result == true) {
        final cookies = await scraper.getCookies('https://itch.io/');
        if (cookies.isNotEmpty) {
          widget.onUpdateCookies(cookies);
        }
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not detect an active itch.io session.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Itch.io refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openLogin(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ItchioLoginDialog(
        onSuccess: widget.onUpdateCookies,
      ),
    );
  }
}

/// Dialog that hosts an embedded WebView2 window for itch.io login.
/// Uses webview_windows (Windows-only, requires WebView2 Runtime — ships
/// with Windows 11 / Microsoft Edge).
///
/// Flow: open https://itch.io/login → user logs in → URL changes to /my-feed
/// → extract document.cookie → save to settings → dialog closes automatically.
///
/// Note: document.cookie returns only non-HTTP-only cookies.
/// The itchio_token cookie (non-HTTP-only) is sufficient for adult content access.
class _ItchioLoginDialog extends StatefulWidget {
  final void Function(Map<String, String> cookies) onSuccess;
  const _ItchioLoginDialog({required this.onSuccess});

  @override
  State<_ItchioLoginDialog> createState() => _ItchioLoginDialogState();
}

class _ItchioLoginDialogState extends State<_ItchioLoginDialog> {
  final _controller = WebviewController();
  StreamSubscription<String>? _urlSub;
  bool _ready = false;
  bool _extracting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _ready = true);
      _urlSub = _controller.url.listen(_onUrlChanged);
      await _controller.loadUrl('https://itch.io/login');
      // Catch existing sessions immediately
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _verifyAndFinish();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not start embedded browser.\n\n'
            'WebView2 Runtime is required — it ships with Windows 11\n'
            'and Microsoft Edge. Make sure Edge is up to date.\n\n'
            'Error: $e');
      }
    }
  }

  void _onUrlChanged(String url) {
    if (_extracting) return;
    if (url.contains('itch.io/my-feed') || url.contains('itch.io/dashboard') || url == 'https://itch.io/') {
      _verifyAndFinish();
    }
  }

  Future<void> _verifyAndFinish() async {
    if (_extracting) return;
    setState(() => _extracting = true);
    _urlSub?.cancel();
    try {
      final raw = await _controller.executeScript('document.cookie') as String? ?? '';
      final cookies = <String, String>{};
      cookies['connected'] = 'true';
      cookies['last_login'] = DateTime.now().toIso8601String();

      for (final part in raw.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length >= 2) {
          final key = kv[0].trim();
          final value = kv.sublist(1).join('=').trim();
          if (key.isNotEmpty) cookies[key] = value;
        }
      }

      // Try to get username from profile/nav
      try {
        final userJs = await _controller.executeScript(
          "document.querySelector('.user_menu .username')?.textContent?.trim() || ''"
        ) as String? ?? '';
        final cleaned = userJs.replaceAll('"', '').trim();
        if (cleaned.isNotEmpty) cookies['username'] = cleaned;
      } catch (_) {}

      if (mounted) {
        widget.onSuccess(cookies);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _error = 'Failed to read session: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: AppRadius.borderLg,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.borderLg,
            child: Column(
              children: [
                // Header
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_browser_outlined,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Text(
                        'itch.io — Login',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_extracting)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saving session…',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        )
                      else if (_ready && _error == null)
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          color: AppColors.accent,
                          tooltip: 'Confirm Connection',
                          onPressed: _verifyAndFinish,
                          splashRadius: 14,
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 14,
                        tooltip: 'Cancel',
                      ),
                    ],
                  ),
                ),
                // Info bar shown once webview is loaded
                if (_ready && !_extracting && _error == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    color: AppColors.accent.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 13, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Log in to your itch.io account. Click the checkmark icon above once you are connected.',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppColors.accentSilver),
                        ),
                      ],
                    ),
                  ),
                // Content area
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    size: 36, color: Colors.orange),
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.6,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _SmallButton(
                                      "I'm logged in — confirm connection",
                                      primary: true,
                                      onTap: () {
                                        setState(() => _error = null);
                                        _verifyAndFinish();
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _SmallButton(
                                      'Close',
                                      onTap: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : !_ready
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                                strokeWidth: 2,
                              ),
                            )
                          : Webview(_controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── XenForo browser login dialog (F95Zone / LewdCorner) ──────────────────────
//
// Hosts a full WebView2 window so Cloudflare/bot checks are bypassed.
// Detects a successful login when the URL leaves /login* on the target domain.

class _XenforoLoginDialog extends StatefulWidget {
  final String site;
  final String baseUrl;
  final void Function(Map<String, String> cookies) onSuccess;

  const _XenforoLoginDialog({
    required this.site,
    required this.baseUrl,
    required this.onSuccess,
  });

  @override
  State<_XenforoLoginDialog> createState() => _XenforoLoginDialogState();
}

class _XenforoLoginDialogState extends State<_XenforoLoginDialog> {
  final _controller = WebviewController();
  StreamSubscription<String>? _urlSub;
  bool _ready = false;
  bool _extracting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _ready = true);
      _urlSub = _controller.url.listen(_onUrlChanged);
      await _controller.loadUrl('${widget.baseUrl}/login/');
      // Catch existing sessions immediately
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _verifyLogin();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not start embedded browser.\n\n'
            'WebView2 Runtime is required — it ships with Windows 11\n'
            'and Microsoft Edge. Make sure Edge is up to date.\n\n'
            'Error: $e');
      }
    }
  }

  void _onUrlChanged(String url) {
    if (_extracting) return;
    // Allow user to navigate freely. We'll wait for them to be logged in.
    // We check for login success if they are on a non-login page on the site.
    final isLoginPath = url.contains('/login') || url.contains('/register');
    final isOnSite = url.startsWith(widget.baseUrl);
    
    if (_ready && isOnSite && !isLoginPath) {
      _verifyLogin();
    }
  }

  Future<void> _verifyLogin() async {
    if (_extracting) return;
    
    // Check if we are logged in by looking for user navigation elements
    try {
      final isLoggedIn = await _controller.executeScript(
        "!!(document.querySelector('.p-navgroup-link--user') || "
        "document.querySelector('.p-nav-avatar') || "
        "document.querySelector('[data-xf-click=\"logout\"]') || "
        "document.documentElement.getAttribute('data-logged-in') === 'true')"
      ) as bool? ?? false;

      if (isLoggedIn) {
        _extractAndFinish();
      }
    } catch (_) {}
  }

  Future<void> _extractAndFinish() async {
    if (_extracting) return;
    setState(() => _extracting = true);
    _urlSub?.cancel();
    
    try {
      final cookies = <String, String>{};
      cookies['connected'] = 'true';
      cookies['last_login'] = DateTime.now().toIso8601String();

      // Attempt to extract the displayed username for UI
      try {
        final usernameJs = await _controller.executeScript(
          "document.querySelector('.p-navgroup-link--user .p-navgroup-linkText')?.textContent?.trim()"
          " || document.querySelector('.p-nav-avatar')?.getAttribute('aria-label')?.trim()"
          " || ''",
        ) as String? ?? '';
        final cleaned = usernameJs.replaceAll('"', '').trim();
        if (cleaned.isNotEmpty) cookies['username'] = cleaned;
      } catch (_) {}

      // Try to get non-HttpOnly cookies just in case any are useful (e.g. xf_user)
      try {
        final raw = await _controller.executeScript('document.cookie') as String? ?? '';
        for (final part in raw.split(';')) {
          final kv = part.trim().split('=');
          if (kv.length >= 2) {
            final key = kv[0].trim();
            final value = kv.sublist(1).join('=').trim();
            if (key == 'xf_user') cookies[key] = value;
          }
        }
      } catch (_) {}

      if (mounted) {
        widget.onSuccess(cookies);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _error = 'Failed to verify session: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: AppRadius.borderLg,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.borderLg,
            child: Column(
              children: [
                // Header
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_browser_outlined,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.site} — Login',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_extracting)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saving session…',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        )
                      else if (_ready && _error == null)
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          color: AppColors.accent,
                          tooltip: 'Confirm Connection',
                          onPressed: _extractAndFinish,
                          splashRadius: 14,
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 14,
                        tooltip: 'Cancel',
                      ),
                    ],
                  ),
                ),
                // Info bar
                if (_ready && !_extracting && _error == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    color: AppColors.accent.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 13, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Log in to your ${widget.site} account. The app will detect it automatically, or you can click the checkmark icon above to finish.',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppColors.accentSilver),
                        ),
                      ],
                    ),
                  ),
                // Content
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    size: 36, color: Colors.orange),
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.6,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _SmallButton(
                                      "I'm logged in — confirm connection",
                                      primary: true,
                                      onTap: () {
                                        setState(() => _error = null);
                                        _verifyLogin();
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _SmallButton(
                                      'Close',
                                      onTap: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : !_ready
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                                strokeWidth: 2,
                              ),
                            )
                          : Webview(_controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── VNDB info card ─────────────────────────────────────────────────────────────
// VNDB uses a free, public JSON API — no account or login is required.

class _VndbInfoCard extends StatefulWidget {
  const _VndbInfoCard();

  @override
  State<_VndbInfoCard> createState() => _VndbInfoCardState();
}

class _VndbInfoCardState extends State<_VndbInfoCard> {
  bool _testing = false;
  bool? _ok;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _ok = null;
    });
    try {
      final results = await MetadataService.searchVndb('Steins Gate');
      if (mounted) setState(() { _testing = false; _ok = results.isNotEmpty; });
    } catch (_) {
      if (mounted) setState(() { _testing = false; _ok = false; });
    }
  }

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
                'VNDB',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x1A4A9E6E),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Public API',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: AppColors.accentSilver,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (_ok != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _ok!
                        ? const Color(0x1A4A9E6E)
                        : const Color(0x1AC94040),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    _ok! ? '✓ Reachable' : '✕ Unreachable',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _ok! ? AppColors.accent : AppColors.danger,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'VNDB (Visual Novel Database) is a free public API — '
            'no account or login required.',
            style:
                GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          _SmallButton(
            _testing ? 'Testing…' : 'Test Connection',
            onTap: _testing ? null : _test,
          ),
        ],
      ),
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

  // In Flutter 3.27+, Color.r/g/b return double in 0.0–1.0
  static String _colorHex(Color c) =>
      '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';
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
// FEED PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _FeedPanel extends ConsumerStatefulWidget {
  const _FeedPanel();

  @override
  ConsumerState<_FeedPanel> createState() => _FeedPanelState();
}

class _FeedPanelState extends ConsumerState<_FeedPanel> {
  late TextEditingController _tokenCtrl;
  late TextEditingController _channelsCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _tokenCtrl = TextEditingController(text: s.discordBotToken);
    _channelsCtrl = TextEditingController(text: s.discordChannelIds.join('\n'));
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _channelsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _PanelScroll(children: [
      _SettingGroup(title: 'FEED', children: [
        _SettingRow(
          label: 'Enable Feed',
          subtitle: 'Show the Feed tab and allow background refresh.',
          trailing: _ToggleSwitch(
            value: s.feedEnabled,
            onChanged: (v) {
              notifier.setFeedEnabled(v);
              ref.read(feedProvider.notifier).updateSchedule(v, s.feedRefreshHours);
            },
          ),
        ),
        _SettingRow(
          label: 'Auto-Refresh Interval',
          subtitle: 'How often to fetch new items in the background.',
          trailing: DropdownButton<int>(
            value: s.feedRefreshHours,
            dropdownColor: AppColors.bgCard,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0,  child: Text('Manual only')),
              DropdownMenuItem(value: 6,  child: Text('Every 6 hours')),
              DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
            ],
            onChanged: (v) {
              if (v == null) return;
              notifier.setFeedRefreshHours(v);
              ref.read(feedProvider.notifier).updateSchedule(s.feedEnabled, v);
            },
          ),
        ),
      ]),

      _SettingGroup(title: 'RSS SOURCES', children: [
        _SettingRow(
          label: 'F95Zone',
          subtitle: 'Adult Games forum (requires F95Zone login in Network tab).',
          trailing: _ToggleSwitch(
            value: s.feedSourceF95,
            onChanged: notifier.setFeedSourceF95,
          ),
        ),
        _SettingRow(
          label: 'LewdCorner',
          subtitle: 'Games forum (requires LewdCorner login in Network tab).',
          trailing: _ToggleSwitch(
            value: s.feedSourceLC,
            onChanged: notifier.setFeedSourceLC,
          ),
        ),
      ]),

      _SettingGroup(title: 'DISCORD', children: [
        // Info note
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Use a registered bot token to read messages from announcement channels. '
            'The bot must already be invited to the target server.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
        ),
        // Bot token
        _SettingRow(
          label: 'Bot Token',
          subtitle: 'Stored locally in settings.json.',
          trailing: const SizedBox(),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _FeedTextField(
            controller: _tokenCtrl,
            hint: 'Bot XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
            obscure: true,
            onChanged: (v) => notifier.setDiscordBotToken(v.trim()),
          ),
        ),
        // Channel IDs
        _SettingRow(
          label: 'Channel IDs',
          subtitle: 'One per line — format: channelId:ServerName:#channelName',
          trailing: const SizedBox(),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _FeedTextField(
            controller: _channelsCtrl,
            hint: '123456789012345678:ServerName:#announcements',
            maxLines: 5,
            onChanged: (v) {
              final ids = v
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              notifier.setDiscordChannelIds(ids);
            },
          ),
        ),
      ]),

      // Normalization milestone note
      _SettingGroup(title: 'NOTE', children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            border: Border.all(color: AppColors.borderAccent),
            borderRadius: AppRadius.borderMd,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Feed normalization (uniform card format across all sources) '
                  'is planned for a future milestone. '
                  'Current output is raw — use it to see what the data looks like '
                  'before deciding on the final card design.',
                  style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.accentLight, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ]),
    ]);
  }
}

/// Simple text field for Feed panel inputs.
class _FeedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _FeedTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.maxLines = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        maxLines: maxLines,
        onChanged: onChanged,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none,
        ),
      ),
    );
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
