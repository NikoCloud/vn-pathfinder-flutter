import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_update_service.dart';
import 'settings_provider.dart';

enum AppUpdatePhase { idle, checking, upToDate, available, downloading, installing, failed }

class AppUpdateState {
  final AppUpdatePhase phase;
  final AppRelease? release;
  final double progress;
  final String? error;

  const AppUpdateState({this.phase = AppUpdatePhase.idle, this.release, this.progress = 0, this.error});

  /// A newer release is known, whatever is happening with it now.
  bool get hasUpdate => release != null;

  AppUpdateState copyWith({AppUpdatePhase? phase, AppRelease? release, double? progress, String? error}) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        release: release ?? this.release,
        progress: progress ?? this.progress,
        error: error,
      );
}

/// Checking for, downloading and installing new versions of the app.
class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  final Ref ref;
  AppUpdateNotifier(this.ref) : super(const AppUpdateState());

  bool get _busy => const {
        AppUpdatePhase.checking,
        AppUpdatePhase.downloading,
        AppUpdatePhase.installing,
      }.contains(state.phase);

  /// The check made once at startup: skipped under Lockdown or with
  /// Settings → Update Checks off, and silent if GitHub can't be reached.
  Future<void> checkOnStartup() async {
    final s = ref.read(settingsProvider);
    if (s.lockdown || !s.checkUpdates) return;
    await check(quiet: true);
  }

  /// Settings → About's "Check for updates". Works with Update Checks off,
  /// but never under Lockdown.
  Future<void> check({bool quiet = false}) async {
    if (_busy) return;
    if (ref.read(settingsProvider).lockdown) {
      state = state.copyWith(phase: AppUpdatePhase.failed, error: 'Lockdown is on, so nothing can be checked.');
      return;
    }
    state = state.copyWith(phase: AppUpdatePhase.checking);
    try {
      final release = await AppUpdateService.newerRelease();
      state = release == null
          ? const AppUpdateState(phase: AppUpdatePhase.upToDate)
          : AppUpdateState(phase: AppUpdatePhase.available, release: release);
    } catch (e) {
      state = quiet
          ? state.copyWith(phase: AppUpdatePhase.idle)
          : state.copyWith(phase: AppUpdatePhase.failed, error: "Couldn't reach GitHub. Try again later.");
    }
  }

  /// Downloads and checks the installer, then hands over to it. The app
  /// closes here when everything goes right.
  Future<void> install() async {
    final release = state.release;
    if (release == null || _busy) return;
    state = state.copyWith(phase: AppUpdatePhase.downloading, progress: 0);
    try {
      final file = await AppUpdateService.download(release, onProgress: (p) {
        if (mounted) state = state.copyWith(phase: AppUpdatePhase.downloading, progress: p);
      });
      state = state.copyWith(phase: AppUpdatePhase.installing, progress: 1);
      await AppUpdateService.installAndExit(file);
    } catch (e) {
      state = state.copyWith(phase: AppUpdatePhase.failed, error: _describe(e));
    }
  }

  String _describe(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(\w+(Exception|Error)|Bad state): ?'), '');
    return s.isEmpty ? 'The update failed.' : s;
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateNotifier, AppUpdateState>((ref) => AppUpdateNotifier(ref));
