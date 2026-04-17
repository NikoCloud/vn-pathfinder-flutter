import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../models/user_data.dart';
import '../../utils/formatters.dart';

class MetaBar extends StatefulWidget {
  final GameGroup group;
  final UserData userData;

  const MetaBar({super.key, required this.group, required this.userData});

  @override
  State<MetaBar> createState() => _MetaBarState();
}

class _MetaBarState extends State<MetaBar> {
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
          _MetaStat(
            label: 'VERSION',
            value: v?.versionStr.isNotEmpty == true ? 'v${v!.versionStr}' : '—',
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
