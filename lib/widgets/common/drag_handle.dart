import 'package:flutter/material.dart';
import '../../theme.dart';

/// A thin separator between two panes that can be dragged to resize them.
/// [axis] is the direction the handle moves: horizontal for a side-by-side
/// split, vertical for a stacked one.
class DragHandle extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  /// Double-click: back to the default size.
  final VoidCallback onReset;

  const DragHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final active = _hovered || _dragging;

    return MouseRegion(
      cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: horizontal ? (_) => setState(() => _dragging = true) : null,
        onHorizontalDragUpdate: horizontal ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onVerticalDragStart: horizontal ? null : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: horizontal ? null : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        child: SizedBox(
          width: horizontal ? 7 : null,
          height: horizontal ? null : 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: horizontal ? (active ? 3 : 1) : null,
              height: horizontal ? null : (active ? 3 : 1),
              color: active ? AppColors.accent : AppColors.border,
            ),
          ),
        ),
      ),
    );
  }

  void _end() {
    setState(() => _dragging = false);
    widget.onDragEnd();
  }
}
