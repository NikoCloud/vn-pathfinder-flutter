import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_update_provider.dart';
import '../../services/app_update_service.dart';
import '../../theme.dart';
import '../common/kit.dart';

/// What's new in the available release, and the button that installs it.
void showAppUpdateDialog(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const _AppUpdateDialog());
}

class _AppUpdateDialog extends ConsumerWidget {
  const _AppUpdateDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appUpdateProvider);
    final release = st.release;
    if (release == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final installed = AppUpdateService.isInstalled;
    final working = st.phase == AppUpdatePhase.downloading || st.phase == AppUpdatePhase.installing;
    final canInstall = installed && release.hasInstaller;

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd, side: BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('VN Pathfinder ${release.version} is out',
                  style: AppText.ui(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('You have $appVersion.', style: AppText.ui(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: AppRadius.borderMd,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: _ReleaseNotes(release.notes),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (working) ...[
                LinearProgressIndicator(
                  value: st.phase == AppUpdatePhase.installing ? null : st.progress,
                  minHeight: 4,
                  color: AppColors.accent,
                  backgroundColor: AppColors.bgHover,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 8),
                Text(
                  st.phase == AppUpdatePhase.installing
                      ? 'Installing. VN Pathfinder will close and reopen by itself.'
                      : 'Downloading… ${(st.progress * 100).round()}%',
                  style: AppText.ui(fontSize: 12, color: AppColors.textSecondary),
                ),
              ] else if (st.phase == AppUpdatePhase.failed && st.error != null)
                Text(st.error!, style: AppText.ui(fontSize: 12, color: AppColors.danger))
              else
                Text(
                  canInstall
                      ? 'VN Pathfinder closes, updates and reopens. Your library, settings and games stay as they are.'
                      : installed
                          ? 'This release has no installer attached, so get it from the release page.'
                          : 'This copy is the portable version, so download the new one from the release page.',
                  style: AppText.ui(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  VpButton(
                    label: 'Release page',
                    icon: Icons.open_in_new,
                    tone: VpTone.quiet,
                    onTap: () => launchUrl(Uri.parse(release.pageUrl)),
                  ),
                  const Spacer(),
                  VpButton(
                    label: 'Later',
                    onTap: working ? null : () => Navigator.of(context).pop(),
                  ),
                  if (canInstall) ...[
                    const SizedBox(width: 8),
                    VpButton(
                      label: st.phase == AppUpdatePhase.failed ? 'Try again' : 'Update now',
                      icon: Icons.download_rounded,
                      tone: VpTone.primary,
                      busy: working,
                      onTap: working ? null : () => ref.read(appUpdateProvider.notifier).install(),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// GitHub release notes are Markdown. This shows headings, bullets and plain
/// lines, and drops the emphasis marks rather than pulling in a renderer.
class _ReleaseNotes extends StatelessWidget {
  final String notes;
  const _ReleaseNotes(this.notes);

  String _plain(String s) =>
      s.replaceAll(RegExp(r'\*\*|__|`'), '').replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!);

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Text('No release notes.', style: AppText.ui(fontSize: 13, color: AppColors.textMuted));
    }
    final lines = <Widget>[];
    for (final raw in notes.replaceAll('\r', '').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        lines.add(const SizedBox(height: 6));
        continue;
      }
      final heading = RegExp(r'^#{1,6}\s+(.*)').firstMatch(line);
      final bullet = RegExp(r'^(\s*)[-*]\s+(.*)').firstMatch(line);
      if (heading != null) {
        lines.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(_plain(heading[1]!),
              style: AppText.ui(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ));
      } else if (bullet != null) {
        lines.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + bullet[1]!.length * 6, bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: AppText.ui(fontSize: 13, color: AppColors.textMuted)),
            Expanded(
              child: Text(_plain(bullet[2]!),
                  style: AppText.ui(fontSize: 13, color: AppColors.textSecondary, height: 1.45)),
            ),
          ]),
        ));
      } else {
        lines.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(_plain(line), style: AppText.ui(fontSize: 13, color: AppColors.textSecondary, height: 1.45)),
        ));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines));
  }
}
