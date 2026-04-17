import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../providers/library_provider.dart';

class DetailContent extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;
  final VoidCallback? onFetchMetadata;

  const DetailContent({
    super.key,
    required this.group,
    required this.userData,
    this.onFetchMetadata,
  });

  @override
  ConsumerState<DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<DetailContent> {
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final key = widget.group.baseKey;
    _notesCtrl = TextEditingController(text: widget.userData.notes[key] ?? '');
  }

  @override
  void didUpdateWidget(DetailContent old) {
    super.didUpdateWidget(old);
    if (old.group.baseKey != widget.group.baseKey) {
      final key = widget.group.baseKey;
      _notesCtrl.text = widget.userData.notes[key] ?? '';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _saveNote(String value) {
    ref.read(userDataProvider.notifier).setNote(widget.group.baseKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final v = g.latestVersion;
    final synopsis = v?.metaSynopsis ?? '';
    final tags = widget.userData.tags[g.baseKey] ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Synopsis
          if (synopsis.isNotEmpty) ...[
            _SectionLabel('SYNOPSIS'),
            const SizedBox(height: 8),
            Text(
              synopsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Tags
          _SectionLabel('TAGS'),
          const SizedBox(height: 8),
          _TagsRow(
            tags: tags,
            onRemove: (t) => ref
                .read(userDataProvider.notifier)
                .setTags(g.baseKey, tags.where((x) => x != t).toList()),
            onAdd: () => _showAddTagDialog(context, g.baseKey, tags),
          ),
          const SizedBox(height: 24),

          // Actions
          _ActionRow(
            group: g,
            onFetchMetadata: widget.onFetchMetadata,
          ),
          const SizedBox(height: 24),

          // Notes
          _SectionLabel('NOTES'),
          const SizedBox(height: 8),
          _NotesField(controller: _notesCtrl, onChanged: _saveNote),
        ],
      ),
    );
  }

  void _showAddTagDialog(
      BuildContext context, String baseKey, List<String> current) {
    String value = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          'Add Tag',
          style: GoogleFonts.inter(color: AppColors.textPrimary),
        ),
        content: TextField(
          autofocus: true,
          style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'e.g. romance, sci-fi…',
            hintStyle: GoogleFonts.inter(
                color: AppColors.textMuted, fontSize: 13),
          ),
          onChanged: (v) => value = v.trim(),
          onSubmitted: (_) {
            if (value.isNotEmpty && !current.contains(value)) {
              ref
                  .read(userDataProvider.notifier)
                  .setTags(baseKey, [...current, value]);
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (value.isNotEmpty && !current.contains(value)) {
                ref
                    .read(userDataProvider.notifier)
                    .setTags(baseKey, [...current, value]);
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Add',
                style: GoogleFonts.inter(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

  const _TagsRow({
    required this.tags,
    required this.onRemove,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...tags.map((t) => _TagChip(label: t, onRemove: () => onRemove(t))),
        _AddTagButton(onTap: onAdd),
      ],
    );
  }
}

class _TagChip extends StatefulWidget {
  final String label;
  final VoidCallback onRemove;
  const _TagChip({required this.label, required this.onRemove});

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _hovered
              ? const Color(0x1A4A9E6E)
              : AppColors.bgSecondary,
          border: Border.all(
            color: _hovered ? AppColors.accent : AppColors.borderLight,
          ),
          borderRadius: AppRadius.borderSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _hovered
                    ? AppColors.accentLight
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            GestureDetector(
              onTap: widget.onRemove,
              child: Icon(
                Icons.close,
                size: 10,
                color: _hovered
                    ? AppColors.accentLight
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTagButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddTagButton({required this.onTap});

  @override
  State<_AddTagButton> createState() => _AddTagButtonState();
}

class _AddTagButtonState extends State<_AddTagButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: _hovered ? AppColors.accent : AppColors.border,
              style: BorderStyle.solid,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 11,
                  color: _hovered ? AppColors.accent : AppColors.textMuted),
              const SizedBox(width: 3),
              Text(
                'Add Tag',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _hovered ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final GameGroup group;
  final VoidCallback? onFetchMetadata;

  const _ActionRow({required this.group, this.onFetchMetadata});

  @override
  Widget build(BuildContext context) {
    final v = group.latestVersion;
    final sourceUrl = v?.metaSourceUrl ?? '';
    final f95Url = v?.metaF95Url ?? '';
    final vndbUrl = v?.metaVndbUrl ?? '';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          icon: Icons.download_outlined,
          label: 'Fetch Metadata',
          onTap: onFetchMetadata,
        ),
        if (sourceUrl.isNotEmpty)
          _ActionButton(
            icon: Icons.open_in_new,
            label: 'Source Page',
            onTap: () => _launch(sourceUrl),
          ),
        if (f95Url.isNotEmpty)
          _ActionButton(
            icon: Icons.open_in_new,
            label: 'F95Zone',
            onTap: () => _launch(f95Url),
          ),
        if (vndbUrl.isNotEmpty)
          _ActionButton(
            icon: Icons.open_in_new,
            label: 'VNDB',
            onTap: () => _launch(vndbUrl),
          ),
      ],
    );
  }

  void _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri);
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
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
            color: _hovered ? AppColors.bgActive : AppColors.bgSecondary,
            border: Border.all(
              color: _hovered ? AppColors.borderLight : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13,
                  color: _hovered
                      ? AppColors.textPrimary
                      : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _hovered
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _NotesField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 6,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText: 'Personal notes…',
          hintStyle: GoogleFonts.inter(
              fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.all(12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
