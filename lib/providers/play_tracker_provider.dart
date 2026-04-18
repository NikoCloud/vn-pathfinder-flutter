import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_version.dart';
import 'library_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class PlayTrackerState {
  final String? runningBaseKey; // baseKey of the game currently running
  final int elapsedSeconds;

  const PlayTrackerState({this.runningBaseKey, this.elapsedSeconds = 0});

  bool get isRunning => runningBaseKey != null;

  PlayTrackerState copyWith({int? elapsedSeconds}) => PlayTrackerState(
        runningBaseKey: runningBaseKey,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PlayTrackerNotifier extends StateNotifier<PlayTrackerState> {
  final Ref _ref;
  // ignore: unused_field — retained for future kill-game support
  Process? _process;
  Timer? _ticker;

  PlayTrackerNotifier(this._ref) : super(const PlayTrackerState());

  /// Launch a game. Returns an error string on failure, null on success.
  Future<String?> launch(GameVersion version, String baseKey) async {
    if (state.isRunning) {
      return 'Another game is already running (${state.runningBaseKey}).';
    }
    if (version.exePath == null) {
      return 'No executable found for "${version.effectiveTitle}". '
          'Try setting one manually in Game Properties.';
    }
    if (!version.exePath!.existsSync()) {
      return 'Executable not found at:\n${version.exePath!.path}';
    }

    try {
      final args = version.metaLaunchArgs.split(' ').where((s) => s.isNotEmpty).toList();
      final proc = await Process.start(
        version.exePath!.path,
        args,
        workingDirectory: version.folderPath.path,
        runInShell: false,
      );
      _process = proc;
      state = PlayTrackerState(runningBaseKey: baseKey, elapsedSeconds: 0);

      // Tick every second
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
        }
      });

      // Record when the process exits
      proc.exitCode.then((_) => _onExit(baseKey));

      return null; // success
    } catch (e) {
      return 'Failed to launch: $e';
    }
  }

  void _onExit(String baseKey) {
    _ticker?.cancel();
    _ticker = null;
    final seconds = state.elapsedSeconds;
    _process = null;

    if (mounted) state = const PlayTrackerState();

    // Only record meaningful sessions (> 10 seconds to avoid accidental clicks)
    if (seconds > 10) {
      _ref.read(userDataProvider.notifier).recordPlaySession(baseKey, seconds);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final playTrackerProvider =
    StateNotifierProvider<PlayTrackerNotifier, PlayTrackerState>(
  (ref) => PlayTrackerNotifier(ref),
);

// Convenience: is a specific game currently running?
final isGameRunningProvider = Provider.family<bool, String>((ref, baseKey) {
  return ref.watch(playTrackerProvider).runningBaseKey == baseKey;
});
