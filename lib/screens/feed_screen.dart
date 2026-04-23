import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/feed_service.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  String _sourceFilter = 'all'; // 'all' | 'f95zone' | 'lewdcorner' | 'azc' | 'discord'

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    final settings = ref.watch(settingsProvider);

    // Filter items by selected source.
    // All view: deduplicate cross-source entries by publish time (first wins).
    // Per-source views: show everything from that source unfiltered.
    final items = _sourceFilter == 'all'
        ? FeedService.deduplicate(feedState.items)
        : feedState.items.where((i) => i.source == _sourceFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FeedToolbar(
          isLoading: feedState.isLoading,
          lastRefreshed: feedState.lastRefreshed,
          sourceFilter: _sourceFilter,
          onFilterChanged: (s) => setState(() => _sourceFilter = s),
          onRefresh: () => ref.read(feedProvider.notifier).refresh(),
          feedEnabled: settings.feedEnabled,
        ),
        if (!settings.feedEnabled)
          const _FeedDisabledBanner()
        else if (feedState.error != null)
          _FeedErrorBanner(error: feedState.error!)
        else if (feedState.items.isEmpty && !feedState.isLoading)
          const _FeedEmptyState()
        else
          Expanded(
            child: feedState.isLoading && feedState.items.isEmpty
                ? const _FeedLoading()
                : _FeedList(items: items),
          ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _FeedToolbar extends StatelessWidget {
  final bool isLoading;
  final DateTime? lastRefreshed;
  final String sourceFilter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onRefresh;
  final bool feedEnabled;

  const _FeedToolbar({
    required this.isLoading,
    required this.lastRefreshed,
    required this.sourceFilter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.feedEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final refreshLabel = lastRefreshed == null
        ? 'Never refreshed'
        : 'Updated ${_timeAgo(lastRefreshed!)}';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Source filter pills
          _SourcePill(label: 'All', value: 'all', current: sourceFilter, onTap: onFilterChanged),
          const SizedBox(width: 6),
          _SourcePill(label: 'F95Zone', value: 'f95zone', current: sourceFilter, onTap: onFilterChanged),
          const SizedBox(width: 6),
          _SourcePill(label: 'LewdCorner', value: 'lewdcorner', current: sourceFilter, onTap: onFilterChanged),
          const SizedBox(width: 6),
          _SourcePill(label: "Azkosel's", value: 'azc', current: sourceFilter, onTap: onFilterChanged),
          const SizedBox(width: 6),
          _SourcePill(label: 'Discord', value: 'discord', current: sourceFilter, onTap: onFilterChanged),

          const Spacer(),

          if (feedEnabled) ...[
            Text(
              refreshLabel,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(width: 12),
          ],

          // Refresh button
          _RefreshButton(isLoading: isLoading, onRefresh: feedEnabled ? onRefresh : null),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SourcePill extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;

  const _SourcePill({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
            borderRadius: AppRadius.borderSm,
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? AppColors.accentLight : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback? onRefresh;
  const _RefreshButton({required this.isLoading, this.onRefresh});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onRefresh != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onRefresh,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered && widget.onRefresh != null
                ? AppColors.bgActive
                : AppColors.bgCard,
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.accent,
                  ),
                )
              else
                Icon(Icons.refresh,
                    size: 13,
                    color: widget.onRefresh != null
                        ? AppColors.textSecondary
                        : AppColors.textMuted),
              const SizedBox(width: 5),
              Text(
                widget.isLoading ? 'Refreshing…' : 'Refresh',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: widget.onRefresh != null
                      ? AppColors.textSecondary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _FeedDisabledBanner extends StatelessWidget {
  const _FeedDisabledBanner();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.rss_feed_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Feed is disabled',
              style: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Enable it in Settings → Feed to start receiving updates.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No items yet',
              style: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Hit Refresh to fetch the latest updates from your sources.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
      ),
    );
  }
}

class _FeedErrorBanner extends StatelessWidget {
  final String error;
  const _FeedErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: AppColors.danger.withValues(alpha: 0.12),
      child: Text(
        'Error: $error',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger),
      ),
    );
  }
}

// ── Feed list ─────────────────────────────────────────────────────────────────

class _FeedList extends StatelessWidget {
  final List<RawFeedItem> items;
  const _FeedList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _FeedCard(item: items[i]),
    );
  }
}

// ── Feed card (raw view — intentionally shows everything as-is) ───────────────

class _FeedCard extends StatefulWidget {
  final RawFeedItem item;
  const _FeedCard({required this.item});

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final body = item.rawBody.trim();

    // For F95Zone SAM items the rawBody is plain-text structured data:
    //   Version: v0.4.8
    //   Developer: SRT
    //   Tags: rpg, corruption, ...
    //   [cover] https://...
    // Parse version and strip the [cover] line before display.
    String? parsedVersion;
    String processedBody = body;
    if (item.source == 'f95zone') {
      final versionMatch = RegExp(r'^Version:\s*(.+)$', multiLine: true)
          .firstMatch(body);
      if (versionMatch != null) {
        parsedVersion = versionMatch.group(1)?.trim();
      }
      // Strip [cover] lines from display
      processedBody = body
          .replaceAll(RegExp(r'^\[cover\]\s*\S+\s*$', multiLine: true), '')
          .trim();
    }

    // Strip obvious HTML tags for readability — this is RAW mode,
    // so we show the text content but skip rendering full HTML.
    final plainBody = processedBody
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    const previewLength = 300;
    final isLong = plainBody.length > previewLength;
    final displayBody = (!_expanded && isLong)
        ? '${plainBody.substring(0, previewLength)}…'
        : plainBody;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source pill
                _SourceBadge(item: item),
                const SizedBox(width: 8),
                // Channel / forum name
                if (item.channelName.isNotEmpty) ...[
                  Text(
                    item.channelName,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                // Timestamp
                Text(
                  item.timeAgo,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Title + version badge ────────────────────────────────────────
            if (item.title.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (parsedVersion != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadius.borderSm,
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        parsedVersion,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

            // ── Author ──────────────────────────────────────────────────────
            if (item.author.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'by ${item.author}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // ── Body (raw) ──────────────────────────────────────────────────
            if (plainBody.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                displayBody,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
              if (isLong) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      _expanded ? 'Show less' : 'Show more',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],

            // ── Footer row ──────────────────────────────────────────────────
            if (item.url.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _OpenButton(url: item.url),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final RawFeedItem item;
  const _SourceBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (item.source) {
      'f95zone'    => (const Color(0x264A9E6E), AppColors.accentLight),
      'lewdcorner' => (const Color(0x26C9904A), const Color(0xFFE8A86A)),
      'azc'        => (const Color(0x26B04AB0), const Color(0xFFCC80CC)),
      'discord'    => (const Color(0x265865F2), const Color(0xFF8B9CF4)),
      _            => (AppColors.bgSecondary,    AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.borderSm,
      ),
      child: Text(
        item.sourceLabel,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _OpenButton extends StatefulWidget {
  final String url;
  const _OpenButton({required this.url});

  @override
  State<_OpenButton> createState() => _OpenButtonState();
}

class _OpenButtonState extends State<_OpenButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(widget.url);
          if (uri != null) await launchUrl(uri);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgActive : Colors.transparent,
            border: Border.all(color: _hovered ? AppColors.borderLight : AppColors.border),
            borderRadius: AppRadius.borderSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new,
                  size: 11,
                  color: _hovered ? AppColors.textPrimary : AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                'Open',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _hovered ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
