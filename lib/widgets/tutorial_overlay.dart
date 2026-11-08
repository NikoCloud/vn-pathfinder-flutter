import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_provider.dart';
import '../services/tutorial_samples.dart';
import '../theme.dart';
import 'common/kit.dart';
import 'modals/settings_modal.dart';

typedef TutorialStep = ({AppTab tab, String title, String body});

const tutorialSteps = <TutorialStep>[
  (
    tab: AppTab.home,
    title: 'Welcome to VN Pathfinder',
    body: "Here's a quick tour with made-up games. They're only here for the tour, nothing you see is saved, "
        'and they disappear when it ends.',
  ),
  (
    tab: AppTab.library,
    title: 'Library',
    body: 'Every game in your library folder, with all its versions kept together. Right-click a game for Fetch '
        'Metadata, its saves folder and more. The slider in the top bar sets the card size, and dragging it to the '
        'left end switches to the Details list.',
  ),
  (
    tab: AppTab.library,
    title: 'Game status',
    body: 'Each game gets a status from its saves and play history, such as Unplayed, Playing or Updated. You can '
        "set it yourself from a game's right-click menu, and the views along the top filter by it.",
  ),
  (
    tab: AppTab.feed,
    title: 'Feed',
    body: "New releases and updates from the sites you choose, in time order. It's off until you turn it on in "
        'Settings, and nothing goes online while Lockdown Mode is on.',
  ),
  (
    tab: AppTab.archive,
    title: 'Archive',
    body: 'The archives in your library folder, and the downloads you start from the Feed. Extract them here, and '
        'follow your downloads at the top.',
  ),
  (
    tab: AppTab.home,
    title: "You're ready",
    body: 'Choose the folder that holds your games to get started. You can take this tour again from Help (F1).',
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

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(tutorialProvider);
    if (step == null) return const SizedBox.shrink();
    final tour = ref.read(tutorialProvider.notifier);
    final s = tutorialSteps[step];
    final last = step == tutorialSteps.length - 1;

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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!last) VpButton(label: 'Skip tour', tone: VpTone.quiet, small: true, onTap: tour.finish),
                      const Spacer(),
                      if (step > 0) ...[
                        VpButton(label: 'Back', tone: VpTone.quiet, small: true, onTap: tour.back),
                        const SizedBox(width: 6),
                      ],
                      if (last) ...[
                        VpButton(label: 'Done', tone: VpTone.quiet, small: true, onTap: tour.finish),
                        const SizedBox(width: 6),
                        VpButton(
                          label: 'Choose library folder',
                          tone: VpTone.primary,
                          small: true,
                          onTap: () {
                            tour.finish();
                            showSettingsModal(context);
                          },
                        ),
                      ] else
                        VpButton(label: 'Next', tone: VpTone.primary, small: true, onTap: tour.next),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
