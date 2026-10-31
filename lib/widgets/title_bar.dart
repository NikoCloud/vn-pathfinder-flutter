import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../providers/update_provider.dart';
import '../theme.dart';
import 'common/kit.dart';
import 'modals/help_modal.dart';
import 'modals/settings_modal.dart';

/// The app's only chrome: tabs, quick find, Discreet, the network state and
/// the window buttons, all in one bar. Empty space drags the window.
class AppTitleBar extends ConsumerWidget {
  const AppTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(activeTabProvider);
    final page = ref.watch(gamePageProvider);
    final updates = ref.watch(availableUpdatesProvider).length;
    final scanning = ref.watch(libraryProvider.select((s) => s.loading));

    void open(AppTab t) {
      ref.read(gamePageProvider.notifier).state = null;
      ref.read(activeTabProvider.notifier).state = t;
    }

    return SizedBox(
      height: AppLayout.titleBarHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary.withValues(alpha: 0.78),
          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.7))),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
            LayoutBuilder(builder: (context, constraints) {
              final roomy = constraints.maxWidth >= 1120;
              return Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.route_outlined, size: 22, color: AppColors.accent),
                  const SizedBox(width: 12),
                  for (final t in AppTab.values)
                    _TabButton(
                      tab: t,
                      selected: page == null && t == tab,
                      count: t == AppTab.feed ? updates : 0,
                      onTap: () => open(t),
                    ),
                  const Spacer(),
                  _FindButton(wide: roomy),
                  const SizedBox(width: 6),
                  const _DiscreetButton(),
                  const _NetworkPill(),
                  VpIconButton(
                    icon: Icons.help_outline,
                    tooltip: 'Help (F1)',
                    onTap: () => showHelpModal(context),
                  ),
                  VpIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings (Ctrl+,)',
                    onTap: () => showSettingsModal(context),
                  ),
                  const SizedBox(width: 6),
                  const _CaptionButtons(),
                ],
              );
            }),
            if (scanning)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Semantics(
                  label: 'Scanning the library',
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  const _TabButton({required this.tab, required this.selected, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      selected: selected,
      label: count > 0 ? '${tab.label}, $count new versions for your games' : tab.label,
      radius: BorderRadius.zero,
      builder: (context, states) {
        final hot = states.contains(WidgetState.hovered);
        return SizedBox(
          height: AppLayout.titleBarHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tab.label,
                        style: AppText.ui(
                          fontSize: 14,
                          height: 18 / 14,
                          fontWeight: FontWeight.w500,
                          color: selected || hot ? AppColors.textPrimary : AppColors.textSecondary,
                        )),
                    if (count > 0) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.newVersion,
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Text('$count',
                            style: AppText.ui(
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onNewVersion,
                            )),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FindButton extends ConsumerWidget {
  final bool wide;
  const _FindButton({required this.wide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => ref.read(finderOpenProvider.notifier).state = true;
    if (!wide) {
      return VpIconButton(icon: Icons.search, tooltip: 'Find (Ctrl+K)', onTap: open);
    }
    return Pressable(
      onTap: open,
      label: 'Find',
      tooltip: 'Find a game (Ctrl+K)',
      builder: (context, states) => Container(
        width: 230,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard.withValues(alpha: states.contains(WidgetState.hovered) ? 1 : 0.8),
          border: Border.all(color: AppColors.border),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text('Find', style: AppText.body(color: AppColors.textMuted)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: AppRadius.borderXs,
              ),
              child: Text('Ctrl K', style: AppText.mono(fontSize: 11, height: 1, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscreetButton extends ConsumerWidget {
  const _DiscreetButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider.select((s) => s.discreet));
    return VpIconButton(
      icon: on ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      tooltip: on ? 'Discreet is on: art is blurred (Ctrl+Shift+D)' : 'Discreet: blur all art (Ctrl+Shift+D)',
      selected: on,
      onTap: () => ref.read(settingsProvider.notifier).setDiscreet(!on),
    );
  }
}

class _NetworkPill extends ConsumerWidget {
  const _NetworkPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(lockdownProvider);
    return Pressable(
      onTap: () => ref.read(settingsProvider.notifier).setLockdown(!locked),
      label: locked ? 'Lockdown, network off' : 'Online, network on',
      tooltip: locked ? 'Lockdown: nothing leaves this PC. Click to go online.' : 'Online. Click for Lockdown.',
      builder: (context, states) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) ? AppColors.bgHover : Colors.transparent,
          borderRadius: AppRadius.borderMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: locked ? AppColors.danger : AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(locked ? 'Lockdown' : 'Online',
                style: AppText.body(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _CaptionButtons extends StatefulWidget {
  const _CaptionButtons();

  @override
  State<_CaptionButtons> createState() => _CaptionButtonsState();
}

class _CaptionButtonsState extends State<_CaptionButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Caption(icon: Icons.remove, label: 'Minimize', onTap: () => windowManager.minimize()),
        _Caption(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          label: _maximized ? 'Restore' : 'Maximize',
          onTap: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _Caption(icon: Icons.close, label: 'Close', close: true, onTap: () => windowManager.close()),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool close;
  final VoidCallback onTap;

  const _Caption({required this.icon, required this.label, required this.onTap, this.close = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: label,
      radius: BorderRadius.zero,
      builder: (context, states) {
        final hot = states.contains(WidgetState.hovered);
        return Container(
          width: 46,
          height: AppLayout.titleBarHeight,
          color: !hot
              ? Colors.transparent
              : close
                  ? const Color(0xFFC42B1C)
                  : AppColors.bgHover,
          child: Icon(icon, size: 14, color: hot && close ? AppColors.onArt : AppColors.textSecondary),
        );
      },
    );
  }
}
