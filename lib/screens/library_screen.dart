import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../models/game_group.dart';
import '../models/game_version.dart';
import '../models/user_data.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/detail/hero_banner.dart';
import '../widgets/detail/meta_bar.dart';
import '../widgets/detail/detail_content.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libState = ref.watch(libraryProvider);
    final ud = ref.watch(userDataProvider);
    final selectedKey = libState.selectedBaseKey;

    GameGroup? selected;
    if (selectedKey != null) {
      try {
        selected =
            libState.groups.firstWhere((g) => g.baseKey == selectedKey);
      } catch (_) {}
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibrarySidebar(
          onAddGame: () {/* TODO: Phase 9 add-game flow */},
        ),
        Expanded(
          child: selected != null
              ? _DetailPane(group: selected, userData: ud)
              : const _EmptyState(),
        ),
      ],
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryDir = ref.watch(libraryDirProvider);

    if (libraryDir.isEmpty) {
      return const ColoredBox(
        color: AppColors.bgPrimary,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 48, color: AppColors.textMuted),
              SizedBox(height: 16),
              Text(
                'No library directory set',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              SizedBox(height: 8),
              Text(
                'Open Settings to choose your library folder.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return const ColoredBox(
      color: AppColors.bgPrimary,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_outlined,
                size: 32, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Select a game',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPane extends ConsumerStatefulWidget {
  final GameGroup group;
  final UserData userData;

  const _DetailPane({required this.group, required this.userData});

  @override
  ConsumerState<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends ConsumerState<_DetailPane> {
  String? _selectedVersion;

  @override
  void initState() {
    super.initState();
    _selectedVersion = widget.group.latestVersion?.versionStr;
  }

  @override
  void didUpdateWidget(_DetailPane old) {
    super.didUpdateWidget(old);
    if (old.group.baseKey != widget.group.baseKey) {
      _selectedVersion = widget.group.latestVersion?.versionStr;
    }
  }

  GameGroup get _effectiveGroup {
    if (_selectedVersion == null) return widget.group;
    // When a different version is selected, return a synthetic group
    // with that version promoted to latestVersion position.
    final versions = widget.group.versions;
    final idx = versions.indexWhere((v) => v.versionStr == _selectedVersion);
    if (idx < 0) return widget.group;
    final reordered = [
      ...versions.sublist(0, idx),
      ...versions.sublist(idx + 1),
      versions[idx],
    ];
    return GameGroup(
      baseKey: widget.group.baseKey,
      displayName: widget.group.displayName,
      versions: reordered,
      archives: widget.group.archives,
    );
  }

  void _play() {
    final v = _effectiveGroup.latestVersion;
    if (v?.exePath == null) return;
    _launchGame(v!);
  }

  void _launchGame(GameVersion gameVersion) async {
    try {
      await Process.start(
        gameVersion.exePath!.path,
        [],
        workingDirectory: gameVersion.folderPath.path,
        runInShell: false,
      );
      ref.read(userDataProvider.notifier).recordPlaySession(
            widget.group.baseKey,
            0,
          );
    } catch (e) {
      // TODO: show error snackbar in Phase 10
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _effectiveGroup;
    final ud = widget.userData;

    return ColoredBox(
      color: AppColors.bgPrimary,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeroBanner(
              group: g,
              userData: ud,
              onPlay: _play,
              onProperties: () {/* TODO: Phase 6 properties modal */},
              onVersionChanged: (v) => setState(() => _selectedVersion = v),
            ),
            MetaBar(group: g, userData: ud),
            DetailContent(
              group: g,
              userData: ud,
              onFetchMetadata: () {/* TODO: Phase 7 metadata fetch modal */},
            ),
          ],
        ),
      ),
    );
  }
}
