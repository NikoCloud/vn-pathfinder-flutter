import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../services/tutorial_samples.dart';
import '../theme.dart';
import 'common/kit.dart';
import '../services/folder_picker.dart';
import '../services/scanner_service.dart' show ScanStage;

typedef TutorialStep = ({AppTab tab, String title, String body});

const tutorialSteps = <TutorialStep>[
  (
    tab: AppTab.home,
    title: 'Welcome to VN Pathfinder',
    body: 'Choose the folder that holds your games, and the app reads it while you take this tour. The games you '
        'see now are made up, only here for the tour, and they disappear when it ends.\n\n'
        "For now, VN Pathfinder officially supports Ren'Py games only. Support for other engines, like Unity and "
        "RPG Maker, is planned and on its way. Until then, those games are often found and can be played, and some "
        'features may work for them, but use them at your own risk.',
  ),
  (
    tab: AppTab.home,
    title: 'Home',
    body: 'What to play next: the game you were last in, new versions of games you play, and games ready to start. '
        "It's worked out from your saves, so it's right the moment the app opens.",
  ),
  (
    tab: AppTab.library,
    title: 'Library',
    body: r'Every game in your library folders, with all its versions kept together. Games inside folders, like '
        r'Played\Developer\Game, are found too. The slider in the top bar sets the card size; drag it to the left end '
        'for a list.',
  ),
  (
    tab: AppTab.library,
    title: 'Game status',
    body: 'Each game gets a status from its saves and play history, such as Unplayed, Playing or Updated. You can '
        "set it yourself from a game's right-click menu, and the views along the top filter by it.",
  ),
  (
    tab: AppTab.library,
    title: 'Fetch Metadata and Merge',
    body: 'Right-click a game for Fetch Metadata, which finds its cover, description and tags. Nothing goes online '
        'while Lockdown is on. If one game shows as two, right-click either one and choose Merge into Another Game '
        'to join their versions.',
  ),
  (
    tab: AppTab.archive,
    title: 'Archive',
    body: 'The archives in your library folders and your downloads. Extract a game, or Assign a mod or patch to one; '
        'Keep the original copies it instead of moving it, so one file can go to several games.',
  ),
  (
    tab: AppTab.archive,
    title: 'Clear, Delete and Clean Up',
    body: 'Clear takes an archive off this screen and leaves the file; Hidden brings it back. Clear & Delete deletes '
        'only the archive file. Archive never deletes a game folder. Clean Up lists archives of games you already '
        'have, to free space.',
  ),
  (
    tab: AppTab.feed,
    title: 'Feed',
    body: 'New releases and updates from the sites you choose, in time order. It needs to go online, so it stays '
        'unavailable while Lockdown is on, and it starts off until you turn it on in Settings.',
  ),
  (
    tab: AppTab.stats,
    title: 'Stats',
    body: 'Your library in numbers: games by status and engine, what you play most, and play time by week.',
  ),
  (
    tab: AppTab.home,
    title: 'In the title bar',
    body: 'The eye hides every cover at once (Ctrl+Shift+D), for when someone might see your screen. Lockdown shows '
        "whether the app may go online; click it to switch. Rescan the library from the Library's top bar after "
        'changing folders outside the app.',
  ),
  (
    tab: AppTab.home,
    title: "You're ready",
    body: 'Take this tour again any time from Help (F1).',
  ),
];

/// The tour's step, or null when it isn't running.
class TutorialNotifier extends StateNotifier<int?> {
  TutorialNotifier(this._ref) : super(null);
  final Ref _ref;

  void start() {
    if (state != null) return;
    _ref.read(gamePageProvider.notifier).state = null;
    _ref.read(libraryProvider.notifier).showSample(sampleGames());
    _ref.read(feedProvider.notifier).showSample(sampleReleases());
    _go(0);
  }

  void next() => state == null || state! >= tutorialSteps.length - 1 ? finish() : _go(state! + 1);

  void back() {
    if (state != null && state! > 0) _go(state! - 1);
  }

  /// Ends the tour, whether it was finished or skipped, and puts the real
  /// library and Feed back.
  void finish() {
    if (state == null) return;
    _ref.read(libraryProvider.notifier).endSample();
    _ref.read(feedProvider.notifier).endSample();
    _ref.read(settingsProvider.notifier).setTutorialDone();
    _ref.read(activeTabProvider.notifier).state = AppTab.home;
    state = null;
  }

  void _go(int step) {
    _ref.read(activeTabProvider.notifier).state = tutorialSteps[step].tab;
    state = step;
  }
}

final tutorialProvider = StateNotifierProvider<TutorialNotifier, int?>((ref) => TutorialNotifier(ref));

/// The tour card, over everything, with the app dimmed and not clickable behind
/// it. Starts by itself on a first run: no library folder and no tour yet.
class TutorialOverlay extends ConsumerStatefulWidget {
  const TutorialOverlay({super.key});

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends ConsumerState<TutorialOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (!settings.tutorialDone && settings.libraryDir.isEmpty) ref.read(tutorialProvider.notifier).start();
    });
  }

  /// Picks the library folder and moves on: the app reads it while the tour
  /// runs, and the real library appears when the tour ends.
  Future<void> _chooseFolder(BuildContext context) async {
    final path = await pickFolder('Choose the folder that holds your games');
    if (path == null || !mounted) return;
    final problem = ref.read(settingsProvider.notifier).addLibraryDir(path);
    if (problem != null) {
      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    if (ref.read(tutorialProvider) == 0) ref.read(tutorialProvider.notifier).next();
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(tutorialProvider);
    if (step == null) return const SizedBox.shrink();
    final tour = ref.read(tutorialProvider.notifier);
    final s = tutorialSteps[step];
    final last = step == tutorialSteps.length - 1;
    final hasFolder = ref.watch(libraryDirsProvider).isNotEmpty;

    return Stack(
      children: [
        ModalBarrier(color: Colors.black.withValues(alpha: 0.28), dismissible: false),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
            child: Container(
              width: 480,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                border: Border.all(color: AppColors.border),
                borderRadius: AppRadius.borderLg,
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 16))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tour, ${step + 1} of ${tutorialSteps.length}', style: AppText.meta(color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  Text(s.title, style: AppText.heading()),
                  const SizedBox(height: 8),
                  Text(s.body, style: AppText.body(color: AppColors.textSecondary)),
                  const _ScanNote(),
                  const SizedBox(height: 16),
                  // Navigation on one line, Skip on its own below, so the
                  // first card's three buttons fit at any text size.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (step > 0) VpButton(label: 'Back', tone: VpTone.quiet, small: true, onTap: tour.back),
                        if (!hasFolder && (step == 0 || last))
                          VpButton(
                            label: 'Choose library folder',
                            tone: VpTone.primary,
                            small: true,
                            onTap: () => _chooseFolder(context),
                          ),
                        if (last)
                          VpButton(
                              label: 'Done',
                              tone: hasFolder ? VpTone.primary : VpTone.quiet,
                              small: true,
                              onTap: tour.finish)
                        else
                          VpButton(
                            label: step == 0 && !hasFolder ? 'Tour first' : 'Next',
                            tone: step == 0 && !hasFolder ? VpTone.quiet : VpTone.primary,
                            small: true,
                            onTap: tour.next,
                          ),
                      ],
                    ),
                  ),
                  if (!last) ...[
                    const SizedBox(height: 4),
                    VpButton(label: 'Skip tour', tone: VpTone.quiet, small: true, onTap: tour.finish),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The real library's progress, read while the tour shows sample games.
class _ScanNote extends ConsumerWidget {
  const _ScanNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(libraryDirsProvider).isEmpty) return const SizedBox.shrink();
    final prog = ref.watch(scanProgressProvider);
    final count = ref.watch(realGameCountProvider);
    final String text;
    if (prog != null) {
      text = prog.stage == ScanStage.saves
          ? 'Reading your library in the background · ${prog.done} of ${prog.total}'
          : 'Finding your games in the background · ${prog.found} found';
    } else if (count != null) {
      text = 'Your library is ready: $count game${count == 1 ? '' : 's'}.';
    } else {
      text = 'Reading your library in the background…';
    }
    final working = prog != null || count == null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          if (working)
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.accent))
          else
            Icon(Icons.check_circle_outline, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.ui(fontSize: 12, color: AppColors.textMuted))),
        ],
      ),
    );
  }
}
