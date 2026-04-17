import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/game_group.dart';
import '../models/user_data.dart';
import '../services/scanner_service.dart';
import 'settings_provider.dart';

// ── UserData Provider ─────────────────────────────────────────────────────────

File _userdataFile() {
  final appdata = Platform.environment['APPDATA'] ?? '';
  return File(p.join(appdata, 'VN Pathfinder', 'userdata.json'));
}

class UserDataNotifier extends StateNotifier<UserData> {
  UserDataNotifier() : super(UserData.empty()) {
    _load();
  }

  void _load() {
    final f = _userdataFile();
    if (!f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      state = UserData.fromJson(raw);
    } catch (_) {}
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

  void recordPlaySession(String folderName, int seconds) {
    update((ud) {
      final playtime = Map<String, int>.from(ud.playtime);
      final playCount = Map<String, int>.from(ud.playCount);
      playtime[folderName] = (playtime[folderName] ?? 0) + seconds;
      playCount[folderName] = (playCount[folderName] ?? 0) + 1;
      return ud.copyWith(
        playtime: playtime,
        playCount: playCount,
        lastPlayed: {
          ...ud.lastPlayed,
          folderName: DateTime.now().toIso8601String(),
        },
      );
    });
  }

  void setPatchState(String metaKey, String patchName, bool active) {
    update((ud) {
      final patches = Map<String, Map<String, bool>>.from(ud.appliedPatches);
      patches[metaKey] = Map<String, bool>.from(patches[metaKey] ?? {});
      patches[metaKey]![patchName] = active;
      return ud.copyWith(appliedPatches: patches);
    });
  }

  void setHidden(String baseKey, bool hidden) {
    update((ud) {
      final h = Set<String>.from(ud.hidden);
      hidden ? h.add(baseKey) : h.remove(baseKey);
      return ud.copyWith(hidden: h);
    });
  }
}

final userDataProvider =
    StateNotifierProvider<UserDataNotifier, UserData>(
  (ref) => UserDataNotifier(),
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
      final groups = await ScannerService.scanAll(Directory(libDir));
      final ud = _ref.read(userDataProvider);
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

// Auto-scan when library dir changes
final libraryScanProvider = Provider<void>((ref) {
  ref.listen<String>(libraryDirProvider, (prev, next) {
    if (next.isNotEmpty && next != prev) {
      ref.read(libraryProvider.notifier).scan();
    }
  });
});
