import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/user_data.dart';
import '../services/scanner_service.dart';
import 'notification_provider.dart';
import 'settings_provider.dart';

// ── Image Epoch ───────────────────────────────────────────────────────────────

/// Bumped after Fetch Metadata rewrites a game's .vnpf images. Flutter caches
/// decoded images by file path and the new files reuse the old names, so the
/// widgets showing them key on this to rebuild and read the new files.
final imageEpochProvider = StateProvider<int>((ref) => 0);

// ── UserData Provider ─────────────────────────────────────────────────────────

File _userdataFile() {
  final appdata = Platform.environment['APPDATA'] ?? '';
  return File(p.join(appdata, 'VN Pathfinder', 'userdata.json'));
}

class UserDataNotifier extends StateNotifier<UserData> {
  final Ref _ref;

  /// Loads from disk unless given [initial] data.
  UserDataNotifier(this._ref, {UserData? initial}) : super(initial ?? UserData.empty()) {
    if (initial == null) _load();
  }

  void _load() {
    final f = _userdataFile();
    if (!f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      state = UserData.fromJson(raw);
    } catch (_) {}

    // Perform background backup on startup
    _performBackup();
  }

  Future<void> _performBackup() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.autoBackup) return;

      final f = _userdataFile();
      if (!f.existsSync()) return;

      final backupDir = Directory(p.join(f.parent.path, 'backups'));
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      // Format: userdata_20231027_153045.json
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.\-]'), '');
      final backupFile = File(p.join(backupDir.path, 'userdata_$timestamp.json'));
      
      await f.copy(backupFile.path);

      // Keep only last 5 backups
      final backups = backupDir.listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('userdata_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // Newest first

      if (backups.length > 5) {
        for (final old in backups.sublist(5)) {
          await old.delete();
        }
      }
    } catch (e) {
      debugPrint('Backup failed: $e');
    }
  }

  Future<void> save() async {
    final f = _userdataFile();
    f.parent.createSync(recursive: true);
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  void update(UserData Function(UserData) updater) {
    state = updater(state);
    save();
  }

  void setNote(String baseKey, String note) =>
      update((ud) => ud.copyWith(notes: {...ud.notes, baseKey: note}));

  void setTags(String baseKey, List<String> tags) =>
      update((ud) => ud.copyWith(tags: {...ud.tags, baseKey: tags}));

  void setCustomArt(String baseKey, String path) =>
      update((ud) => ud.copyWith(customArt: {...ud.customArt, baseKey: path}));

  void setCustomDisplayName(String baseKey, String name) =>
      update((ud) => ud.copyWith(
          customDisplayNames: {...ud.customDisplayNames, baseKey: name}));

  void recordPlaySession(String baseKey, int seconds, {String? versionStr}) {
    update((ud) {
      final playtime = Map<String, int>.from(ud.playtime);
      final playCount = Map<String, int>.from(ud.playCount);
      playtime[baseKey] = (playtime[baseKey] ?? 0) + seconds;
      playCount[baseKey] = (playCount[baseKey] ?? 0) + 1;
      return ud.copyWith(
        playtime: playtime,
        playCount: playCount,
        lastPlayed: {
          ...ud.lastPlayed,
          baseKey: DateTime.now().toIso8601String(),
        },
        lastPlayedVersion: versionStr == null
            ? null
            : {...ud.lastPlayedVersion, baseKey: versionStr},
        sessions: [...ud.sessions, PlaySession(baseKey, DateTime.now(), seconds)],
      );
    });
  }

  void setWatching(String titleKey, bool watching) => update((ud) => ud.copyWith(
        watching: watching ? {...ud.watching, titleKey} : ud.watching.difference({titleKey}),
      ));

  void setMuted(String titleKey, bool muted) => update((ud) => ud.copyWith(
        muted: muted ? {...ud.muted, titleKey} : ud.muted.difference({titleKey}),
      ));

  void setPatchState(String metaKey, String patchName, bool active) {
    update((ud) {
      final patches = Map<String, Map<String, bool>>.from(ud.appliedPatches);
      patches[metaKey] = Map<String, bool>.from(patches[metaKey] ?? {});
      patches[metaKey]![patchName] = active;
      return ud.copyWith(appliedPatches: patches);
    });
  }

  /// Atomically replace the entire patch map for [metaKey] with [states].
  /// Used by the patch scanner to purge ghosts and correct state drift in one write.
  void syncPatchStates(String metaKey, Map<String, bool> states) {
    update((ud) {
      final patches = Map<String, Map<String, bool>>.from(ud.appliedPatches);
      if (states.isEmpty) {
        patches.remove(metaKey);
      } else {
        patches[metaKey] = Map<String, bool>.from(states);
      }
      return ud.copyWith(appliedPatches: patches);
    });
  }

  void setHidden(String baseKey, bool hidden) {
    final newHidden = {...state.hidden};
    if (hidden) {
      newHidden.add(baseKey);
    } else {
      newHidden.remove(baseKey);
    }
    state = state.copyWith(hidden: newHidden);
    save();

    if (hidden) {
      _ref.read(notificationProvider.notifier).info('Game hidden from library');
    } else {
      _ref.read(notificationProvider.notifier).success('Game restored to library');
    }
  }

  /// Remembers [tag] as a preset offered when adding tags.
  void addCustomPreset(String tag) {
    if (state.customPresets.contains(tag)) return;
    update((ud) => ud.copyWith(customPresets: [...ud.customPresets, tag]));
  }

  /// Stops suggesting that games [a] and [b] are duplicates.
  void markNotDuplicate(String a, String b) => update((ud) =>
      ud.copyWith(notDuplicates: {...ud.notDuplicates, UserData.pairKey(a, b)}));

  /// Makes game [source] part of game [target]. No files move.
  void mergeGames(String source, String target) {
    update((ud) => ud.withGameMerged(source, target));
    _ref.read(libraryProvider.notifier).scan();
  }

  /// Undoes a merge: [source]'s folders are their own game again. Play
  /// history stays with the game it was merged into.
  void unmergeGame(String source) {
    update((ud) => ud.copyWith(gameMerges: {...ud.gameMerges}..remove(source)));
    _ref.read(libraryProvider.notifier).scan();
    _ref.read(notificationProvider.notifier).success('Game separated');
  }

  /// Sets a game's status by GameStatus id; '' clears it so the status is
  /// detected again ("Auto").
  void setStatus(String baseKey, String status) {
    final statuses = Map<String, String>.from(state.status);
    if (status.isEmpty) {
      statuses.remove(baseKey);
    } else {
      statuses[baseKey] = status;
    }
    state = state.copyWith(status: statuses);
    save();

    final label = GameStatus.fromId(status)?.label ?? 'Auto';
    _ref.read(notificationProvider.notifier).success('Status set to $label');
  }
}

final userDataProvider =
    StateNotifierProvider<UserDataNotifier, UserData>(
  (ref) => UserDataNotifier(ref),
);

// ── Library State ─────────────────────────────────────────────────────────────

class LibraryState {
  final List<GameGroup> groups;
  final bool loading;
  final String? error;
  final String? selectedBaseKey;

  const LibraryState({
    this.groups = const [],
    this.loading = false,
    this.error,
    this.selectedBaseKey,
  });

  LibraryState copyWith({
    List<GameGroup>? groups,
    bool? loading,
    String? error,
    String? selectedBaseKey,
    bool clearSelection = false,
  }) => LibraryState(
    groups: groups ?? this.groups,
    loading: loading ?? this.loading,
    error: error,
    selectedBaseKey: clearSelection ? null : (selectedBaseKey ?? this.selectedBaseKey),
  );

  GameGroup? get selectedGroup => selectedBaseKey == null
      ? null
      : groups.cast<GameGroup?>().firstWhere(
            (g) => g?.baseKey == selectedBaseKey,
            orElse: () => null);
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final Ref _ref;

  LibraryNotifier(this._ref) : super(const LibraryState());

  Future<void> scan() async {
    final libDir = _ref.read(libraryDirProvider);
    if (libDir.isEmpty) {
      state = state.copyWith(error: 'No library directory set. Open Settings to configure.');
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final ud = _ref.read(userDataProvider);
      final groups = await ScannerService.scanAll(Directory(libDir), merges: ud.gameMerges);
      ScannerService.autoDetectPatches(groups, ud);
      state = state.copyWith(groups: groups, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void select(String? baseKey) =>
      state = state.copyWith(selectedBaseKey: baseKey);

  void clearSelection() => state = state.copyWith(clearSelection: true);
}

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>(
  (ref) => LibraryNotifier(ref),
);

// Auto-scan on startup and whenever the library dir changes
/// The games alone, so selecting one doesn't recompute what depends on the list.
final libraryGroupsProvider = Provider<List<GameGroup>>((ref) {
  return ref.watch(libraryProvider.select((s) => s.groups));
});

final libraryScanProvider = Provider<void>((ref) {
  // Initial scan if dir is already configured
  final dir = ref.read(libraryDirProvider);
  if (dir.isNotEmpty) {
    Future.microtask(() => ref.read(libraryProvider.notifier).scan());
  }
  // Re-scan whenever the dir changes
  ref.listen<String>(libraryDirProvider, (prev, next) {
    if (next.isNotEmpty && next != prev) {
      ref.read(libraryProvider.notifier).scan();
    }
  });
});
