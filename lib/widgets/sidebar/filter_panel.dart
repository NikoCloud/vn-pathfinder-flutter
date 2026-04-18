import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../providers/filter_provider.dart';

class FilterPanel extends ConsumerWidget {
  const FilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _SearchSection(),
        _TagIncludeSection(),
        _TagExcludeSection(),
        _EngineSection(),
        _StatusSection(),
        _SortRow(),
      ],
    );
  }
}

// ── Search ────────────────────────────────────────────────────────────────────

class _SearchSection extends ConsumerStatefulWidget {
  const _SearchSection();
  @override
  ConsumerState<_SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends ConsumerState<_SearchSection> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);

    return _Section(
      label: 'SEARCH',
      trailing: _PillToggleButton(
        label: filter.searchMode == SearchMode.title ? 'TITLE' : 'CREATOR',
        onTap: () => notifier.setSearchMode(
          filter.searchMode == SearchMode.title
              ? SearchMode.creator
              : SearchMode.title,
        ),
      ),
      child: _SearchInput(
        controller: _ctrl,
        placeholder: filter.searchMode == SearchMode.title
            ? 'Search titles…'
            : 'Search creators…',
        onChanged: notifier.setQuery,
      ),
    );
  }
}

// ── Tag Include ───────────────────────────────────────────────────────────────

class _TagIncludeSection extends ConsumerWidget {
  const _TagIncludeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final allTags = ref.watch(allTagsProvider);

    return _Section(
      label: 'TAGS',
      labelSuffix: ' (MAX 10)',
      trailing: _PillToggleButton(
        label: filter.tagMatchMode == TagMatchMode.any ? 'OR' : 'AND',
        onTap: () => notifier.setTagMatchMode(
          filter.tagMatchMode == TagMatchMode.any
              ? TagMatchMode.all
              : TagMatchMode.any,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TagDropdown(
            placeholder: 'Select a tag to filter…',
            options: allTags,
            selected: filter.includeTags,
            onSelect: notifier.addIncludeTag,
            maxReached: filter.includeTags.length >= 10,
          ),
          if (filter.includeTags.isNotEmpty) ...[
            const SizedBox(height: 3),
            _ChipRow(
              tags: filter.includeTags,
              exclude: false,
              onRemove: notifier.removeIncludeTag,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tag Exclude ───────────────────────────────────────────────────────────────

class _TagExcludeSection extends ConsumerWidget {
  const _TagExcludeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final allTags = ref.watch(allTagsProvider);

    return _Section(
      label: 'EXCLUDE TAGS',
      labelSuffix: ' (MAX 10)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TagDropdown(
            placeholder: 'Select to exclude…',
            options: allTags,
            selected: filter.excludeTags,
            onSelect: notifier.addExcludeTag,
            maxReached: filter.excludeTags.length >= 10,
          ),
          if (filter.excludeTags.isNotEmpty) ...[
            const SizedBox(height: 3),
            _ChipRow(
              tags: filter.excludeTags,
              exclude: true,
              onRemove: notifier.removeExcludeTag,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Engine ────────────────────────────────────────────────────────────────────

class _EngineSection extends ConsumerWidget {
  const _EngineSection();
  static const _engines = [
    ('renpy', "Ren'Py"),
    ('rpgm', 'RPGM'),
    ('unity', 'Unity'),
    ('html', 'HTML'),
    ('unreal', 'Unreal'),
    ('other', 'Others'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);

    return _Collapsible(
      label: 'ENGINE',
      children: _engines
          .map((e) => _FilterCheckbox(
                label: e.$2,
                value: filter.engines.contains(e.$1),
                onChanged: (v) => notifier.toggleEngine(e.$1, v),
              ))
          .toList(),
    );
  }
}

// ── Status ────────────────────────────────────────────────────────────────────

class _StatusSection extends ConsumerWidget {
  const _StatusSection();
  static const _statuses = [
    ('playing', 'Playing'),
    ('completed', 'Completed'),
    ('on-hold', 'On Hold'),
    ('unplayed', 'Unplayed'),
    ('abandoned', 'Abandoned'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);

    return _Collapsible(
      label: 'STATUS',
      children: _statuses
          .map((s) => _FilterCheckbox(
                label: s.$2,
                value: filter.statuses.contains(s.$1),
                onChanged: (v) => notifier.toggleStatus(s.$1, v),
              ))
          .toList(),
    );
  }
}

// ── Sort Row ──────────────────────────────────────────────────────────────────

class _SortRow extends ConsumerWidget {
  const _SortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final count = ref.watch(filteredGroupsProvider).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 0),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            '$count Result${count == 1 ? '' : 's'}',
            style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
          ),
          const Spacer(),
          _SortButton(
            tooltip: 'Sort A–Z',
            label: 'A↓',
            active: filter.sort == SortMode.alpha,
            onTap: () => notifier.setSort(SortMode.alpha),
          ),
          _SortButton(
            tooltip: 'Sort by Recently Played',
            label: '🕐',
            active: filter.sort == SortMode.recentlyPlayed,
            onTap: () => notifier.setSort(SortMode.recentlyPlayed),
          ),
          _SortButton(
            tooltip: 'Sort by Date Added',
            label: '📅',
            active: filter.sort == SortMode.dateAdded,
            onTap: () => notifier.setSort(SortMode.dateAdded),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final String labelSuffix;
  final Widget? trailing;
  final Widget child;

  const _Section({
    required this.label,
    this.labelSuffix = '',
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (labelSuffix.isNotEmpty)
                      TextSpan(
                        text: labelSuffix,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}

class _PillToggleButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PillToggleButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadius.borderXs,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;

  const _SearchInput({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.search, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagDropdown extends StatefulWidget {
  final String placeholder;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onSelect;
  final bool maxReached;

  const _TagDropdown({
    required this.placeholder,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.maxReached,
  });

  @override
  State<_TagDropdown> createState() => _TagDropdownState();
}

class _TagDropdownState extends State<_TagDropdown> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _close,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.transparent)),
            CompositedTransformFollower(
              link: _layerLink,
              offset: Offset(0, size.height + 2),
              child: Material(
                color: Colors.transparent,
                child: _DropdownMenu(
                  options: widget.options,
                  selected: widget.selected,
                  onSelect: (tag) {
                    widget.onSelect(tag);
                    _close();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_overlay!);
    setState(() => _open = true);
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _open = false);
  }

  @override
  void dispose() {
    // Remove overlay without calling setState — widget is already being unmounted
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: widget.maxReached ? null : _toggle,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            border: Border.all(
              color: _open ? AppColors.accent : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.maxReached ? 'Max 10 selected' : widget.placeholder,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownMenu extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onSelect;

  const _DropdownMenu({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 258),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: AppRadius.borderSm,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
        ),
        child: Text('No tags yet',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 258, maxHeight: 160),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: AppRadius.borderSm,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        children: options.map((tag) {
          final isSel = selected.contains(tag);
          return _DropdownOption(
            tag: tag,
            selected: isSel,
            onTap: () => onSelect(tag),
          );
        }).toList(),
      ),
    );
  }
}

class _DropdownOption extends StatefulWidget {
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const _DropdownOption({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DropdownOption> createState() => _DropdownOptionState();
}

class _DropdownOptionState extends State<_DropdownOption> {
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
          color: _hovered ? AppColors.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            widget.tag,
            style: GoogleFonts.inter(
              fontSize: 11,
              color:
                  widget.selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<String> tags;
  final bool exclude;
  final ValueChanged<String> onRemove;

  const _ChipRow({
    required this.tags,
    required this.exclude,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: tags
          .map((t) => _FilterChip(
                tag: t,
                exclude: exclude,
                onRemove: () => onRemove(t),
              ))
          .toList(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String tag;
  final bool exclude;
  final VoidCallback onRemove;

  const _FilterChip({
    required this.tag,
    required this.exclude,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bg = exclude
        ? const Color(0x1FC94040)
        : const Color(0x264A9E6E);
    final fg = exclude ? AppColors.danger : AppColors.accentLight;
    final border = exclude
        ? const Color(0x40C94040)
        : const Color(0x404A9E6E);

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 1, 4, 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag,
              style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 10, color: fg.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _Collapsible extends StatefulWidget {
  final String label;
  final List<Widget> children;

  const _Collapsible({required this.label, required this.children});

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more,
                        size: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 4.5,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FilterCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.accent,
                side: const BorderSide(color: AppColors.textMuted, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortButton extends StatefulWidget {
  final String tooltip;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortButton({
    required this.tooltip,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends State<_SortButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active || _hovered
        ? AppColors.accent
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
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
