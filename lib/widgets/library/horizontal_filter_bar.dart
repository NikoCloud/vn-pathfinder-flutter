import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../providers/filter_provider.dart';
import '../sidebar/sidebar.dart';

class HorizontalFilterBar extends ConsumerWidget {
  const HorizontalFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final allTags = ref.watch(allTagsProvider);
    final count = ref.watch(filteredGroupsProvider).length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Search + Mode Toggle
          _HorizontalSearch(
            query: filter.query,
            mode: filter.searchMode,
            onChanged: notifier.setQuery,
            onToggleMode: () => notifier.setSearchMode(
              filter.searchMode == SearchMode.title
                  ? SearchMode.creator
                  : SearchMode.title,
            ),
          ),
          const SizedBox(width: 20),

          // Tag Dropdowns
          _HorizontalTagDropdown(
            label: 'TAGS',
            placeholder: 'Include...',
            options: allTags,
            selected: filter.includeTags,
            onSelect: notifier.addIncludeTag,
            onRemove: notifier.removeIncludeTag,
            matchMode: filter.tagMatchMode,
            onToggleMatch: () => notifier.setTagMatchMode(
              filter.tagMatchMode == TagMatchMode.any
                  ? TagMatchMode.all
                  : TagMatchMode.any,
            ),
          ),
          const SizedBox(width: 12),
          _HorizontalTagDropdown(
            label: 'EXCLUDE',
            placeholder: 'Exclude...',
            options: allTags,
            selected: filter.excludeTags,
            onSelect: notifier.addExcludeTag,
            onRemove: notifier.removeExcludeTag,
          ),

          const Spacer(),

          // Results count
          Text(
            '$count Result${count == 1 ? '' : 's'}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 16),

          // Sort Buttons
          _SortGroup(
            currentSort: filter.sort,
            onSort: notifier.setSort,
          ),
          const SizedBox(width: 16),

          // Back to List Button
          _BackButton(onTap: () {
            ref.read(gridViewProvider.notifier).state = false;
          }),
        ],
      ),
    );
  }
}

class _HorizontalSearch extends StatefulWidget {
  final String query;
  final SearchMode mode;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleMode;

  const _HorizontalSearch({
    required this.query,
    required this.mode,
    required this.onChanged,
    required this.onToggleMode,
  });

  @override
  State<_HorizontalSearch> createState() => _HorizontalSearchState();
}

class _HorizontalSearchState extends State<_HorizontalSearch> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(_HorizontalSearch old) {
    super.didUpdateWidget(old);
    if (widget.query != _ctrl.text) {
      _ctrl.text = widget.query;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.search, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onChanged,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: widget.mode == SearchMode.title ? 'Search titles...' : 'Search creators...',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          _SearchModeToggle(
            label: widget.mode == SearchMode.title ? 'TITLE' : 'DEV',
            onTap: widget.onToggleMode,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _SearchModeToggle extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SearchModeToggle({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.bgActive,
          borderRadius: AppRadius.borderXs,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.accentLight,
          ),
        ),
      ),
    );
  }
}

class _HorizontalTagDropdown extends StatefulWidget {
  final String label;
  final String placeholder;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final TagMatchMode? matchMode;
  final VoidCallback? onToggleMatch;

  const _HorizontalTagDropdown({
    required this.label,
    required this.placeholder,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
    this.matchMode,
    this.onToggleMatch,
  });

  @override
  State<_HorizontalTagDropdown> createState() => _HorizontalTagDropdownState();
}

class _HorizontalTagDropdownState extends State<_HorizontalTagDropdown> {
  final _link = LayerLink();
  OverlayEntry? _overlay;
  bool _open = false;

  void _hide() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _open = false);
  }

  void _show() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          GestureDetector(
            onTap: _hide,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
          CompositedTransformFollower(
            link: _link,
            offset: Offset(0, size.height + 4),
            child: Material(
              color: Colors.transparent,
              child: _TagPicker(
                options: widget.options,
                selected: widget.selected,
                onSelect: (t) {
                   widget.onSelect(t);
                   _hide();
                },
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlay!);
    setState(() => _open = true);
  }

  @override
  void dispose() {
    _overlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, 
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _open ? _hide : _show,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                border: Border.all(color: _open ? AppColors.accent : AppColors.border),
                borderRadius: AppRadius.borderSm,
              ),
              child: Row(
                children: [
                  Text(
                    widget.selected.isEmpty ? widget.placeholder : '${widget.selected.length} Selected',
                    style: GoogleFonts.inter(fontSize: 11, color: widget.selected.isEmpty ? AppColors.textMuted : AppColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (widget.matchMode != null) ...[
            const SizedBox(width: 4),
            _MatchModeToggle(mode: widget.matchMode!, onTap: widget.onToggleMatch!),
          ],
        ],
      ),
    );
  }
}

class _TagPicker extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onSelect;

  const _TagPicker({required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: options.isEmpty 
          ? [Padding(padding: const EdgeInsets.all(12), child: Text('No tags available', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)))]
          : options.map((t) => _TagTile(
              label: t, 
              selected: selected.contains(t),
              onTap: () => onSelect(t),
            )).toList(),
      ),
    );
  }
}

class _TagTile extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagTile({required this.label, required this.selected, required this.onTap});

  @override
  State<_TagTile> createState() => _TagTileState();
}

class _TagTileState extends State<_TagTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.label, 
                  style: GoogleFonts.inter(fontSize: 12, color: widget.selected ? AppColors.accentLight : AppColors.textSecondary)),
              ),
              if (widget.selected) const Icon(Icons.check, size: 14, color: AppColors.accentLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchModeToggle extends StatelessWidget {
  final TagMatchMode mode;
  final VoidCallback onTap;
  const _MatchModeToggle({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.bgActive,
          borderRadius: AppRadius.borderXs,
        ),
        child: Text(
          mode == TagMatchMode.any ? 'OR' : 'AND',
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

class _SortGroup extends StatelessWidget {
  final SortMode currentSort;
  final ValueChanged<SortMode> onSort;
  const _SortGroup({required this.currentSort, required this.onSort});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortBtn(icon: Icons.sort_by_alpha, active: currentSort == SortMode.alpha, onTap: () => onSort(SortMode.alpha)),
        _SortBtn(icon: Icons.access_time, active: currentSort == SortMode.recentlyPlayed, onTap: () => onSort(SortMode.recentlyPlayed)),
        _SortBtn(icon: Icons.calendar_today, active: currentSort == SortMode.dateAdded, onTap: () => onSort(SortMode.dateAdded)),
      ],
    );
  }
}

class _SortBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _SortBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sort',
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onTap,
        color: active ? AppColors.accent : AppColors.textMuted,
        splashRadius: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back to List View',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderSm,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.menu, size: 20, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
