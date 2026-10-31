import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';

/// The app's controls. Each has hover, pressed, disabled and focus states and
/// a label for screen readers, so screens don't build their own.

enum VpTone {
  /// The one action that matters on a surface.
  primary,

  /// Get a newer version. Amber means a new version and nothing else.
  update,

  secondary,
  quiet,

  /// On top of art, in either theme.
  glass,

  danger,
}

/// Hover, pressed and focus state for a control, with the focus ring drawn
/// around it. Space and Enter activate it.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final String? label;
  final String? tooltip;
  final BorderRadius radius;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final GestureTapDownCallback? onSecondaryTapDown;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;

  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.label,
    this.tooltip,
    this.radius = AppRadius.borderMd,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onSecondaryTapDown,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false, _pressed = false, _focused = false;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final states = <WidgetState>{
      if (_hovered && enabled) WidgetState.hovered,
      if (_pressed && enabled) WidgetState.pressed,
      if (_focused) WidgetState.focused,
      if (!enabled) WidgetState.disabled,
      if (widget.selected) WidgetState.selected,
    };

    Widget child = FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _activate();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            border: _focused ? Border.all(color: AppColors.accent, width: 2) : null,
          ),
          child: widget.builder(context, states),
        ),
      ),
    );

    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label ?? widget.tooltip,
      excludeSemantics: widget.label != null,
      child: child,
    );
  }
}

class VpButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VpTone tone;
  final bool small;
  final bool busy;
  final String? tooltip;

  const VpButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.tone = VpTone.secondary,
    this.small = false,
    this.busy = false,
    this.tooltip,
  });

  (Color fill, Color fg, Color? line) _colors(Set<WidgetState> states) {
    final hot = states.contains(WidgetState.hovered);
    final down = states.contains(WidgetState.pressed);
    switch (tone) {
      case VpTone.primary:
        final fill = AppColors.accent;
        return (down ? AppColors.accentDim : hot ? AppColors.accentLight : fill, AppColors.onAccent, null);
      case VpTone.update:
        final fill = AppColors.newVersion;
        return (hot || down ? Color.lerp(fill, const Color(0xFFFFFFFF), down ? 0 : 0.14)! : fill, AppColors.onNewVersion, null);
      case VpTone.secondary:
        return (down ? AppColors.bgActive : hot ? AppColors.bgHover : AppColors.bgCard, AppColors.textPrimary, AppColors.border);
      case VpTone.quiet:
        return (down ? AppColors.bgActive : hot ? AppColors.bgHover : Colors.transparent, hot ? AppColors.textPrimary : AppColors.textSecondary, null);
      case VpTone.glass:
        return (Colors.white.withValues(alpha: down ? 0.26 : hot ? 0.2 : 0.12), AppColors.onArt, Colors.white.withValues(alpha: 0.16));
      case VpTone.danger:
        return (AppColors.danger.withValues(alpha: down ? 0.28 : hot ? 0.2 : 0.12), AppColors.danger, AppColors.danger.withValues(alpha: 0.4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = small ? 30.0 : 38.0;
    return Pressable(
      onTap: busy ? null : onTap,
      label: label,
      tooltip: tooltip,
      builder: (context, states) {
        final (fill, fg, line) = _colors(states);
        final off = states.contains(WidgetState.disabled);
        return AnimatedOpacity(
          duration: AppMotion.of(context, AppMotion.hover),
          opacity: off && !busy ? 0.5 : 1,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.hover),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: small ? 10 : 15),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: line ?? Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: small ? 15 : 17, color: fg),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class VpIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final bool onArt;
  final double size;
  final GestureTapDownCallback? onSecondaryTapDown;

  const VpIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.onArt = false,
    this.size = 30,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      tooltip: tooltip,
      selected: selected,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, states) {
        final hot = states.contains(WidgetState.hovered);
        final fill = selected
            ? AppColors.accent
            : onArt
                ? Colors.white.withValues(alpha: hot ? 0.22 : 0.12)
                : hot
                    ? AppColors.bgHover
                    : Colors.transparent;
        final fg = selected
            ? AppColors.onAccent
            : onArt
                ? AppColors.onArt
                : hot
                    ? AppColors.textPrimary
                    : AppColors.textSecondary;
        return AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.hover),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, borderRadius: AppRadius.borderMd),
          child: Icon(icon, size: 16, color: states.contains(WidgetState.disabled) ? AppColors.textMuted : fg),
        );
      },
    );
  }
}

/// A filter choice. [excluded] is the third state of a tri-state chip.
class VpChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool excluded;
  final VoidCallback? onTap;
  final String? count;

  const VpChip({
    super.key,
    required this.label,
    this.selected = false,
    this.excluded = false,
    this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      selected: selected,
      label: excluded ? 'Not $label' : label,
      builder: (context, states) {
        final hot = states.contains(WidgetState.hovered);
        final line = excluded
            ? AppColors.danger
            : selected
                ? AppColors.accent
                : AppColors.border;
        return AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.hover),
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : hot
                    ? AppColors.bgHover
                    : Colors.transparent,
            border: Border.all(color: line),
            borderRadius: AppRadius.borderMd,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppText.ui(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w500,
                  color: excluded
                      ? AppColors.danger
                      : selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                  decoration: excluded ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.danger,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(count!, style: AppText.data(color: AppColors.textMuted)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A short label on art or in a row.
class VpBadge extends StatelessWidget {
  final String label;
  final Color fill;
  final Color color;
  final IconData? icon;
  final bool mono;

  const VpBadge({
    super.key,
    required this.label,
    this.fill = const Color(0xB8080A0F),
    this.color = const Color(0xFFE8EBF1),
    this.icon,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: fill, borderRadius: const BorderRadius.all(Radius.circular(5))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? AppText.mono(fontSize: 12, height: 14 / 12, fontWeight: FontWeight.w500, color: color)
                  : AppText.ui(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral tag. Tags never carry colour, so no tag reads as more important.
class VpTag extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const VpTag({super.key, required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgHover,
        borderRadius: const BorderRadius.all(Radius.circular(5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.ui(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          if (onRemove != null) ...[
            const SizedBox(width: 5),
            Pressable(
              onTap: onRemove,
              label: 'Remove $label',
              radius: AppRadius.borderXs,
              builder: (context, states) => Icon(
                Icons.close,
                size: 13,
                color: states.contains(WidgetState.hovered) ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A search or text box.
class VpField extends StatefulWidget {
  final String hint;
  final IconData? icon;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;
  final bool autofocus;
  final FocusNode? focusNode;

  const VpField({
    super.key,
    required this.hint,
    this.icon,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.width,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<VpField> createState() => _VpFieldState();
}

class _VpFieldState extends State<VpField> {
  late final _focus = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.85),
        border: Border.all(color: _focused ? AppColors.accent : AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorColor: AppColors.accent,
              cursorHeight: 15,
              style: AppText.body(),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: widget.hint,
                hintStyle: AppText.body(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon choices in one joined box.
class VpSegmented<T> extends StatelessWidget {
  final T value;
  final List<(T value, IconData icon, String label)> options;
  final ValueChanged<T> onChanged;

  const VpSegmented({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderMd,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, icon, label) in options)
              Pressable(
                onTap: () => onChanged(v),
                tooltip: label,
                selected: v == value,
                radius: BorderRadius.zero,
                builder: (context, states) => Container(
                  width: 36,
                  height: 30,
                  alignment: Alignment.center,
                  color: v == value ? AppColors.bgActive : AppColors.bgCard.withValues(alpha: 0.85),
                  child: Icon(icon, size: 16, color: v == value ? AppColors.textPrimary : AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sticky-toolbar button with an optional count.
class VpTool extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool on;
  final int count;
  final VoidCallback? onTap;

  const VpTool({super.key, required this.label, this.icon, this.on = false, this.count = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: label,
      selected: on,
      builder: (context, states) => AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.hover),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) ? AppColors.bgHover : AppColors.bgCard.withValues(alpha: 0.85),
          border: Border.all(color: on ? AppColors.accent : AppColors.border),
          borderRadius: AppRadius.borderMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 7),
            ],
            Text(label, style: AppText.body(fontWeight: FontWeight.w500)),
            if (count > 0) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.borderMd),
                child: Text('$count',
                    style: AppText.ui(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w700, color: AppColors.onAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A view choice with a count, like the Feed's shelves or the Library's quick
/// views.
class VpShelf extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const VpShelf({super.key, required this.label, this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      selected: selected,
      label: count == null ? label : '$label, $count',
      builder: (context, states) => AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.hover),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.bgActive
              : states.contains(WidgetState.hovered)
                  ? AppColors.bgHover
                  : Colors.transparent,
          borderRadius: AppRadius.borderMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.body(
                  fontWeight: FontWeight.w500,
                  color: selected || states.contains(WidgetState.hovered) ? AppColors.textPrimary : AppColors.textSecondary,
                )),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text('$count', style: AppText.mono(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One entry of [showVpMenu].
class VpMenuItem<T> {
  final T? value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? hint;
  final bool checked;
  final bool danger;
  final bool divider;

  const VpMenuItem(this.value, this.label, {this.icon, this.iconColor, this.hint, this.checked = false, this.danger = false})
      : divider = false;
  const VpMenuItem.divider()
      : value = null,
        label = '',
        icon = null,
        iconColor = null,
        hint = null,
        checked = false,
        danger = false,
        divider = true;
}

/// A menu at [position], in the global coordinates of the app.
Future<T?> showVpMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<VpMenuItem<T>> items,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
    constraints: const BoxConstraints(minWidth: 210),
    menuPadding: const EdgeInsets.all(5),
    items: [
      for (final item in items)
        if (item.divider)
          const PopupMenuDivider(height: 9)
        else
          PopupMenuItem<T>(
            value: item.value,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 15, color: item.iconColor ?? (item.danger ? AppColors.danger : AppColors.textSecondary)),
                  const SizedBox(width: 9),
                ],
                Text(item.label,
                    style: AppText.body(
                      color: item.danger ? AppColors.danger : AppColors.textPrimary,
                      fontWeight: item.checked ? FontWeight.w600 : null,
                    )),
                if (item.hint != null) ...[
                  const SizedBox(width: 6),
                  Text(item.hint!, style: AppText.meta(color: AppColors.textMuted)),
                ],
                if (item.checked) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check, size: 14, color: AppColors.accent),
                ],
              ],
            ),
          ),
    ],
  );
}

/// A menu that opens under the widget at [context].
Future<T?> showVpMenuBelow<T>(BuildContext context, List<VpMenuItem<T>> items) {
  final box = context.findRenderObject() as RenderBox;
  return showVpMenu<T>(
    context: context,
    position: box.localToGlobal(Offset(0, box.size.height + 4)),
    items: items,
  );
}

/// A panel with a title that sits on the app background.
class VpCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets padding;

  const VpCard({super.key, this.title, required this.child, this.padding = const EdgeInsets.all(15)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.86),
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(title!, style: AppText.heading()),
            const SizedBox(height: 9),
          ],
          child,
        ],
      ),
    );
  }
}

/// A label and value line in a [VpCard].
class VpFact extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final bool mono;
  final bool last;

  const VpFact({super.key, required this.label, this.value, this.child, this.mono = false, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.body(color: AppColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: child ??
                  Text(
                    value ?? '',
                    textAlign: TextAlign.right,
                    style: mono ? AppText.data(color: AppColors.textPrimary, fontWeight: FontWeight.w500) : AppText.body(fontWeight: FontWeight.w500),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
