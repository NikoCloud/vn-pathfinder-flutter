import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/scanner_service.dart';
import '../theme.dart';

/// Lines shown above the real status while the library loads (#13). Each set
/// matches what the scan is doing. Draft list, pending NikoCloud's approval.
const loadingLines = {
  ScanStage.finding: [
    'Going through your bookshelf…',
    'Counting the spines…',
    'Checking behind the encyclopedias…',
    'Opening the drawer you said was just socks…',
    'Sorting the Ren\'Pys from the Unitys…',
    'Figuring out who\'s who…',
    'Telling the classics from the "classics"…',
    'Peeking into every folder, politely…',
    'Following the trail of breadcrumbs…',
  ],
  ScanStage.saves: [
    'Checking where the sticky pages are…',
    'Finding your bookmarks…',
    'Seeing who you left on a cliffhanger…',
    'Remembering which route you were on…',
    'Dusting off the covers…',
    'Straightening the posters…',
    'Counting your save slots…',
    'Working out who you\'ve been seeing…',
    'Checking what you did last summer…',
  ],
};

/// The Library header's note while new games are looked for in the background.
const backgroundLines = [
  'Anything left under the mattress?',
  'Checking the back of the closet…',
  'Looking in the box marked "taxes"…',
];

const slowDriveLines = [
  'This drive\'s taking its time…',
  'Waking up the external drive. It was napping…',
  'The NAS is thinking about it…',
];

/// Plain lines for Discreet mode, when someone else might see the screen.
const _plainLines = {
  ScanStage.finding: 'Finding your games…',
  ScanStage.saves: 'Reading your library…',
};

/// Covers the window while the library loads with nothing to show yet: the
/// first start, or a start whose quick pass found nothing. Appears only after
/// half a second, so a fast start never flashes it, and steps aside after two
/// minutes so a huge or slow library never locks the app.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  static const showAfter = Duration(milliseconds: 500);
  static const giveUpAfter = Duration(minutes: 2);
  static const lineEvery = Duration(milliseconds: 3500);
  static const slowAfter = Duration(milliseconds: 2500);

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  // Time is counted in 250 ms ticks of its own timer, not the wall clock.
  static const _tickLength = Duration(milliseconds: 250);
  Timer? _tick;
  int _ticks = 0;
  bool _gaveUp = false;
  final _rng = Random();
  final _used = <String>{};
  String? _line;
  int _lineAt = -1000;
  String? _folder;
  int _folderAt = 0;

  Duration _since(int tick) => _tickLength * (_ticks - tick);

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _pick(List<String> pool) {
    final fresh = pool.where((l) => !_used.contains(l)).toList();
    final from = fresh.isEmpty ? pool : fresh;
    final line = from[_rng.nextInt(from.length)];
    _used.add(line);
    return line;
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final hasFolders = ref.watch(libraryDirsProvider).isNotEmpty;
    final discreet = ref.watch(settingsProvider.select((s) => s.discreet));
    final waiting = lib.loading && lib.groups.isEmpty && hasFolders && lib.error == null;

    if (!waiting) {
      _tick?.cancel();
      _tick = null;
      _ticks = 0;
      _gaveUp = false;
      _used.clear();
      _line = null;
      return const SizedBox.shrink();
    }
    _tick ??= Timer.periodic(_tickLength, (_) {
      if (mounted) setState(() => _ticks++);
    });
    final shown = _since(0);
    if (shown >= LoadingScreen.giveUpAfter) _gaveUp = true;
    if (shown < LoadingScreen.showAfter || _gaveUp) return const SizedBox.shrink();

    final prog = lib.progress;
    final stage = prog?.stage ?? ScanStage.finding;
    if (prog?.folder != _folder) {
      _folder = prog?.folder;
      _folderAt = _ticks;
    }
    final stalled = _folder != null && _since(_folderAt) >= LoadingScreen.slowAfter;

    if (_line == null || _since(_lineAt) >= LoadingScreen.lineEvery) {
      _line = discreet
          ? _plainLines[stage]
          : stalled
              ? _pick(slowDriveLines)
              : _pick(loadingLines[stage]!);
      _lineAt = _ticks;
    }

    final status = switch (stage) {
      ScanStage.finding => 'Finding games · ${prog?.done ?? 0} folders checked · ${prog?.found ?? 0} found',
      ScanStage.saves => 'Reading saves · ${prog!.done} of ${prog.total}',
    };

    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        label: '$status. ${_line ?? ''}',
        child: Container(
          color: AppColors.bgPrimary,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.accentDim],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text('VP', style: AppText.ui(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _line ?? '',
                    key: ValueKey(_line),
                    textAlign: TextAlign.center,
                    style: AppText.display(fontSize: 22, height: 1.2, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: prog?.fraction,
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(status, style: AppText.ui(fontSize: 12, color: AppColors.textSecondary)),
                if (stalled) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Waiting for ${_shortPath(_folder!)}',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last two parts of a path, so a deep one stays readable.
String _shortPath(String path) {
  final parts = p.split(path);
  return parts.length <= 2 ? path : p.joinAll(['…', ...parts.sublist(parts.length - 2)]);
}
