import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../providers/feed_provider.dart';
import '../../utils/formatters.dart';

class MetaBar extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;

  const MetaBar({super.key, required this.group, required this.userData});

  @override
  ConsumerState<MetaBar> createState() => _MetaBarState();
}

class _MetaBarState extends ConsumerState<MetaBar> {
  Future<int>? _diskFuture;
  String? _lastPath;

  @override
  void didUpdateWidget(MetaBar old) {
    super.didUpdateWidget(old);
    final path = widget.group.latestVersion?.folderPath.path;
    if (path != _lastPath) {
      _lastPath = path;
      _diskFuture = path != null ? _computeSize(path) : null;
    }
  }

  @override
  void initState() {
    super.initState();
    final path = widget.group.latestVersion?.folderPath.path;
    _lastPath = path;
    _diskFuture = path != null ? _computeSize(path) : null;
  }

  static Future<int> _computeSize(String path) =>
      compute(_dirSizeIsolate, path);

  @override
  Widget build(BuildContext context) {
    final v = widget.group.latestVersion;
    final baseKey = widget.group.baseKey;
    final ud = widget.userData;

    final playtimeSeconds = ud.playtime[baseKey] ?? 0;
    final lastPlayed = ud.lastPlayed[baseKey];
    final playCount = ud.playCount[baseKey] ?? 0;

    // Look up whether the feed has seen a version for this game.
    // Matching is by normalised title — no version comparison, no "newer" logic.
    final feedMap = ref.watch(feedVersionMapProvider);
    final normTitle = widget.group.effectiveTitle
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .trim()
        .toLowerCase();
    final feedHint = feedMap[normTitle];

    final installedVersion = v?.versionStr.isNotEmpty == true
        ? (v!.versionStr.startsWith('v') ? v.versionStr : 'v${v.versionStr}')
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          FutureBuilder<int>(
            future: _diskFuture,
            builder: (context, snap) => _MetaStat(
              label: 'DISK SIZE',
              value: snap.hasData && snap.data! > 0
                  ? fmtBytes(snap.data!)
                  : snap.connectionState == ConnectionState.waiting
                      ? '…'
                      : '—',
            ),
          ),
          _Divider(),
          _MetaStat(
            label: 'LAST PLAYED',
            value: lastPlayed != null ? fmtDate(lastPlayed) : 'Never',
          ),
          _Divider(),
          _MetaStat(
            label: 'PLAY TIME',
            value: playtimeSeconds > 0 ? fmtTime(playtimeSeconds) : '—',
          ),
          _Divider(),
          _MetaStat(
            label: 'PLAY COUNT',
            value: playCount > 0 ? '$playCount' : '0',
            suffix: playCount == 1 ? 'session' : 'sessions',
          ),
          _Divider(),
          // VERSION — shows installed version; if the feed has seen a version
          // for this game, shows it as a second line so the user can compare.
          _VersionStat(
            installed: installedVersion,
            feedHint: feedHint,
          ),
        ],
      ),
    );
  }
}

int _dirSizeIsolate(String path) {
  int total = 0;
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += entity.lengthSync();
      } catch (_) {}
    }
  }
  return total;
}

// ── Version stat with optional feed hint ──────────────────────────────────────

class _VersionStat extends StatelessWidget {
  final String installed;
  final FeedVersionHint? feedHint;

  const _VersionStat({required this.installed, this.feedHint});

  String get _sourceLabel {
    if (feedHint == null) return '';
    return switch (feedHint!.source) {
      'f95zone'    => 'F95Zone',
      'lewdcorner' => 'LewdCorner',
      'itchio'     => 'itch.io',
      _            => feedHint!.source,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'VERSION',
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          installed,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (feedHint != null) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderSm,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$_sourceLabel: ${feedHint!.version}',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: AppColors.border,
    );
  }
}

class _MetaStat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;

  const _MetaStat({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 4),
              Text(
                suffix!,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
