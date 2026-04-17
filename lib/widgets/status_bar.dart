import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/filter_provider.dart';

// Status text provider — surfaces current operation messages
final statusTextProvider = StateProvider<String>((ref) {
  final lib = ref.watch(libraryProvider);
  if (lib.loading) return 'Scanning library…';
  if (lib.error != null) return 'Error: ${lib.error}';
  final count = ref.watch(filteredGroupsProvider).length;
  return 'Ready — $count game${count == 1 ? '' : 's'} in library';
});

class AppStatusBar extends ConsumerWidget {
  final VoidCallback onAddGame;

  const AppStatusBar({super.key, required this.onAddGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusTextProvider);
    final locked = ref.watch(lockdownProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: AppColors.border),
        Container(
          height: AppLayout.statusbarHeight,
          color: AppColors.bgSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Left — Add a Game
              _AddGameButton(onTap: onAddGame),
              // Center — status text
              Expanded(
                child: Center(
                  child: Text(
                    status,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Right — lockdown indicator (compact)
              _StatusLockdownBadge(locked: locked),
            ],
          ),
        ),
      ],
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              'Add a Game',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _hovered ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLockdownBadge extends StatelessWidget {
  final bool locked;
  const _StatusLockdownBadge({required this.locked});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(locked ? '🔒' : '🔓', style: const TextStyle(fontSize: 10)),
        const SizedBox(width: 4),
        Text(
          locked ? 'Lockdown' : 'Online',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: locked ? AppColors.danger : AppColors.accent,
          ),
        ),
      ],
    );
  }
}
