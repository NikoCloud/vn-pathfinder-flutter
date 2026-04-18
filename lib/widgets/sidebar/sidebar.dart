import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../providers/library_provider.dart';
import 'filter_panel.dart';
import 'game_list.dart';

// Tracks list vs grid view mode
final gridViewProvider = StateProvider<bool>((ref) => false);

class LibrarySidebar extends ConsumerWidget {
  final VoidCallback onAddGame;

  const LibrarySidebar({super.key, required this.onAddGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGrid = ref.watch(gridViewProvider);

    return Container(
      width: AppLayout.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header always present (never remounted) to avoid dropdown dispose crash
          _SidebarHeader(isGrid: isGrid, ref: ref),
          const Divider(height: 1, color: AppColors.border),
          // Game list only in list mode; grid fills the main content area
          if (!isGrid) const Expanded(child: GameList()),
          if (isGrid) const Spacer(),
          const Divider(height: 1, color: AppColors.border),
          _AddGameButton(onTap: onAddGame),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool isGrid;
  final WidgetRef ref;

  const _SidebarHeader({required this.isGrid, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Home button + view toggle
          Row(
            children: [
              _HomeButton(onTap: () {
                ref.read(libraryProvider.notifier).clearSelection();
              }),
              const Spacer(),
              _ViewToggle(isGrid: isGrid, onToggle: (v) {
                ref.read(gridViewProvider.notifier).state = v;
              }),
            ],
          ),
          const SizedBox(height: 6),
          const FilterPanel(),
        ],
      ),
    );
  }
}

class _HomeButton extends StatefulWidget {
  final VoidCallback onTap;
  const _HomeButton({required this.onTap});

  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgActive : AppColors.bgHover,
            borderRadius: AppRadius.borderSm,
          ),
          child: Text(
            'Home',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _hovered ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool isGrid;
  final ValueChanged<bool> onToggle;

  const _ViewToggle({required this.isGrid, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ToggleBtn(
          icon: Icons.view_list,
          active: !isGrid,
          tooltip: 'List View',
          onTap: () => onToggle(false),
        ),
        const SizedBox(width: 2),
        _ToggleBtn(
          icon: Icons.grid_view,
          active: isGrid,
          tooltip: 'Grid View',
          onTap: () => onToggle(true),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatefulWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ToggleBtn> createState() => _ToggleBtnState();
}

class _ToggleBtnState extends State<_ToggleBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? AppColors.accent
        : _hovered
            ? AppColors.textSecondary
            : AppColors.textMuted;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 24,
            decoration: BoxDecoration(
              color: widget.active
                  ? AppColors.bgActive
                  : _hovered
                      ? AppColors.bgHover
                      : Colors.transparent,
              borderRadius: AppRadius.borderXs,
            ),
            child: Icon(widget.icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class _AddGameButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddGameButton({required this.onTap});

  @override
  State<_AddGameButton> createState() => _AddGameButtonState();
}

class _AddGameButtonState extends State<_AddGameButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0x0D4A9E6E)
                  : Colors.transparent,
              border: Border.all(
                color: _hovered ? AppColors.accent : AppColors.borderLight,
              ),
              borderRadius: AppRadius.borderSm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add,
                    size: 13,
                    color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  '＋ Add a Game',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _hovered ? AppColors.accent : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
