import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/crash_log.dart';
import '../theme.dart';
import 'common/kit.dart';

/// The report from a run that ended badly, if there is one. Set at start.
final crashReportProvider = StateProvider<CrashReport?>((ref) => null);

/// Shows the "closed unexpectedly" dialog once, after the first frame.
class CrashReportPrompt extends ConsumerStatefulWidget {
  const CrashReportPrompt({super.key});

  @override
  ConsumerState<CrashReportPrompt> createState() => _CrashReportPromptState();
}

class _CrashReportPromptState extends ConsumerState<CrashReportPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final report = ref.read(crashReportProvider);
      if (report == null || !mounted) return;
      ref.read(crashReportProvider.notifier).state = null;
      showDialog<void>(
        context: context,
        builder: (_) => CrashReportDialog(
          text: report.text(libraryDirs: ref.read(settingsProvider).libraryDirs),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class CrashReportDialog extends StatefulWidget {
  final String text;
  const CrashReportDialog({super.key, required this.text});

  @override
  State<CrashReportDialog> createState() => _CrashReportDialogState();
}

class _CrashReportDialogState extends State<CrashReportDialog> {
  bool _showing = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderMd,
        side: BorderSide(color: AppColors.border),
      ),
      title: Text('VN Pathfinder closed unexpectedly last time',
          style: AppText.ui(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A short report was saved on this PC. Nothing was sent anywhere. '
              'To help fix it, copy the report and paste it wherever you report problems. '
              'Your folders and Windows user name are left out.',
              style: AppText.ui(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            ),
            if (_showing) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: AppRadius.borderSm,
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.text,
                      style: AppText.mono(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        VpButton(
          label: 'Open logs folder',
          tone: VpTone.quiet,
          small: true,
          onTap: () => Process.run('explorer', [CrashLog.logsDir.path]),
        ),
        VpButton(
          label: _showing ? 'Hide report' : 'View report',
          tone: VpTone.quiet,
          small: true,
          onTap: () => setState(() => _showing = !_showing),
        ),
        VpButton(
          label: _copied ? 'Copied' : 'Copy',
          icon: _copied ? Icons.check : Icons.copy_outlined,
          tone: VpTone.primary,
          small: true,
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.text));
            setState(() => _copied = true);
          },
        ),
        VpButton(label: 'Close', small: true, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}
