import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../providers/settings_provider.dart';
import 'modals/settings_modal.dart';

class AppNavbar extends ConsumerWidget implements PreferredSizeWidget {
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  const AppNavbar({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppLayout.navbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(lockdownProvider);

    return Container(
      height: AppLayout.navbarHeight,
      color: AppColors.bgSecondary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 12),
                _Brand(),
                const SizedBox(width: 24),
                _NavTab(label: 'LIBRARY', index: 0, selected: selectedTab == 0,
                    onTap: () => onTabChanged(0)),
                _NavTab(label: 'ARCHIVE', index: 1, selected: selectedTab == 1,
                    onTap: () => onTabChanged(1)),
                _NavTab(label: 'FEED', index: 2, selected: selectedTab == 2,
                    onTap: () => onTabChanged(2)),
                const Spacer(),
                _SettingsButton(),
                const SizedBox(width: 6),
                _LockdownBadge(locked: locked),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // VP logo box
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.accentDim],
            ),
            borderRadius: AppRadius.borderSm,
          ),
          alignment: Alignment.center,
          child: Text('VP',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0)),
        ),
        const SizedBox(width: 8),
        Text(
          'VN PATHFINDER',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _NavTab extends StatefulWidget {
  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.accentLight
        : _hovered
            ? AppColors.textPrimary
            : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: AppLayout.navbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: _hovered && !widget.selected
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              if (widget.selected)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(2)),
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

class _SettingsButton extends StatefulWidget {
  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Settings  (Ctrl+,)',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showSettingsModal(context),
          child: Container(
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.bgHover : Colors.transparent,
              borderRadius: AppRadius.borderSm,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.settings_outlined,
                size: 16, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _LockdownBadge extends StatelessWidget {
  final bool locked;

  const _LockdownBadge({required this.locked});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: locked
          ? 'Network access is disabled. Click to open Settings.'
          : 'Network access is enabled. Click to open Settings.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: locked
              ? const Color(0x26C94040)
              : const Color(0x264A9E6E),
          borderRadius: AppRadius.borderSm,
          border: Border.all(
            color: locked
                ? const Color(0x4DC94040)
                : AppColors.borderAccent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(locked ? '🔒' : '🔓', style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            Text(
              locked ? 'LOCKDOWN' : 'ONLINE',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: locked ? AppColors.danger : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
