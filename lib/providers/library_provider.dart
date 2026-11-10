import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';
import '../models/game_status.dart';
import '../models/user_data.dart';
import '../services/library_cache.dart';
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

  /// The running scan's progress, for the loading screen. Null when idle.
  final ScanProgress? progress;

  const LibraryState({
    this.groups = const [],
    this.loading = false,
    this.error,
    this.selectedBaseKey,
    this.progress,
  });

  LibraryState copyWith({
    List<GameGroup>? groups,
    bool? loading,
    String? error,
    String? selectedBaseKey,
    bool clearSelection = false,
    ScanProgress? progress,
    bool clearProgress = false,
  }) => LibraryState(
    groups: groups ?? this.groups,
    loading: loading ?? this.loading,
    error: error,
    selectedBaseKey: clearSelection ? null : (selectedBaseKey ?? this.selectedBaseKey),
    progress: clearProgress ? null : (progress ?? this.progress),
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

  /// The real list, set aside while the tour shows sample games.
  LibraryState? _real;
  bool _scanWanted = false;

  /// Shows [groups] in place of the library until [endSample]. Nothing is
  /// written, and a scan that comes in meanwhile waits.
  void showSample(List<GameGroup> groups) {
    _real ??= state;
    state = LibraryState(groups: groups);
  }

  void endSample() {
    final real = _real;
    if (real == null) return;
    _real = null;
    state = real;
    if (_scanWanted) {
      _scanWanted = false;
      scan();
    }
  }

  /// The library cache: loaded once, replaced after every full scan.
  Map<String, dynamic>? _cache;
  bool _quickDone = false;

  /// The scan in progress, if any. Only one runs at a time: adding folders
  /// quickly used to start overlapping scans, and whichever finished last won,
  /// even when it didn't include the newest folder.
  Future<void>? _running;
  bool _rescan = false;

  Future<void> scan() async {
    if (_real != null) {
      _scanWanted = true;
      return;
    }
    final running = _running;
    if (running != null) {
      // Picked up by the loop below once the current pass ends.
      _rescan = true;
      return running;
    }
    final run = _scanLoop();
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
  }

  /// Scans again while requests keep arriving mid-scan, so everyone waiting
  /// on [scan] gets a list that includes their change.
  Future<void> _scanLoop() async {
    do {
      _rescan = false;
      await _scanOnce();
    } while (_rescan && _real == null);
    if (_rescan) {
      _rescan = false;
      _scanWanted = true;
    }
  }

  Future<void> _scanOnce() async {
    final dirs = _ref.read(libraryDirsProvider);
    if (dirs.isEmpty) {
      state = state.copyWith(error: 'No library directory set. Open Settings to configure.');
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final ud = _ref.read(userDataProvider);
      final libraryDirs = [for (final d in dirs) Directory(d)];
      final cache = _cache ??= LibraryCache.load();

      // The first scan of a session with a cache: show the games it knows
      // first (saves reread where they changed), then search for the rest.
      // `loading` stays on, so update checks wait for the full search.
      if (!_quickDone && cache.isNotEmpty) {
        _quickDone = true;
        final quick = await ScannerService.scanCached(libraryDirs, cache, merges: ud.gameMerges);
        ScannerService.autoDetectPatches(quick.groups, ud);
        if (_real != null) {
          _real = _real!.copyWith(groups: quick.groups);
        } else if (quick.groups.isNotEmpty) {
          state = state.copyWith(groups: quick.groups);
        }
      }
      _quickDone = true;

      var lastShown = DateTime(0);
      final result = await ScannerService.scanLibrary(libraryDirs,
          merges: ud.gameMerges,
          noSubfolders: _ref.read(settingsProvider).noSubfolderDirs.toSet(),
          cache: cache, onProgress: (prog) {
        // About ten updates a second is plenty for a progress bar.
        final now = DateTime.now();
        if (now.difference(lastShown).inMilliseconds < 100 || _real != null) return;
        lastShown = now;
        state = state.copyWith(progress: prog);
      });
      _cache = result.cache;
      LibraryCache.save(result.cache);
      final groups = result.groups;
      ScannerService.autoDetectPatches(groups, ud);
      // A scan that was already running when the tour began lands in the
      // real list, not over the samples.
      if (_real != null) {
        _real = _real!.copyWith(groups: groups, loading: false);
        return;
      }
      state = state.copyWith(groups: groups, loading: false, clearProgress: true);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString(), clearProgress: true);
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
  final dirs = ref.read(libraryDirsProvider);
  if (dirs.isNotEmpty) {
    Future.microtask(() => ref.read(libraryProvider.notifier).scan());
  }
  // Re-scan whenever a folder is added or removed. Reordering doesn't change
  // what's found, so it doesn't rescan.
  // Turning Search subfolders on or off for a folder changes what's found.
  ref.listen<List<String>>(settingsProvider.select((s) => s.noSubfolderDirs), (prev, next) {
    if (!listEquals(prev, next)) ref.read(libraryProvider.notifier).scan();
  });
  ref.listen<List<String>>(libraryDirsProvider, (prev, next) {
    final before = {...?prev}, after = {...next};
    if (before.length != after.length || !before.containsAll(after)) {
      ref.read(libraryProvider.notifier).scan();
    }
  });
});
