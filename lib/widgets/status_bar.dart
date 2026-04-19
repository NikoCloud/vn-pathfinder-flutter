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
  const AppStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusTextProvider);
    final locked = ref.watch(lockdownProvider);
    final isScanning = ref.watch(libraryProvider).loading;

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
              // Left — Rescan Library
              _RescanButton(
                isScanning: isScanning,
                onTap: () => ref.read(libraryProvider.notifier).scan(),
              ),
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

class _RescanButton extends StatefulWidget {
  final bool isScanning;
  final VoidCallback onTap;
  const _RescanButton({required this.isScanning, required this.onTap});

  @override
  State<_RescanButton> createState() => _RescanButtonState();
}

class _RescanButtonState extends State<_RescanButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.isScanning
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isScanning ? null : widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.isScanning
                ? const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.accent,
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    size: 13,
                    color: _hovered ? AppColors.accent : AppColors.textMuted,
                  ),
            const SizedBox(width: 4),
            Text(
              widget.isScanning ? 'Scanning…' : 'Rescan Library',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _hovered && !widget.isScanning
                    ? AppColors.accent
                    : AppColors.textMuted,
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
