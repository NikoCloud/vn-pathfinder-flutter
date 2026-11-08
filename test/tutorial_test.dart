// The first-run tour: sample data only while it runs, and the real library
// and Feed back exactly as they were afterwards.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/providers/feed_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/providers/shell_provider.dart';
import 'package:vn_pathfinder/widgets/tutorial_overlay.dart';

class _Settings extends SettingsNotifier {
  _Settings(AppSettings s) {
    state = s;
  }
  int saves = 0;
  @override
  Future<void> save() async => saves++;
}

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
}

final _real = [const GameGroup(baseKey: 'real game', displayName: 'Real Game')];
final _realFeed = [
  RawFeedItem(id: 'f95zone::1', source: 'f95zone', sourceLabel: 'F95Zone', title: 'Real Release', rawBody: '', url: ''),
];

List<Override> _overrides({String libraryDir = ''}) => [
      settingsProvider.overrideWith((ref) => _Settings(AppSettings(libraryDir: libraryDir))),
      libraryProvider.overrideWith((ref) => _Library(ref, _real)),
      feedProvider.overrideWith((ref) => FeedNotifier.seeded(ref, FeedState(items: _realFeed))),
    ];

void main() {
  test('samples stand in while it runs, and the real library and Feed come back after', () {
    final c = ProviderContainer(overrides: _overrides());
    addTearDown(c.dispose);
    final tour = c.read(tutorialProvider.notifier);

    tour.start();
    expect(c.read(libraryProvider).groups, isNotEmpty);
    expect(c.read(libraryProvider).groups.every((g) => g.baseKey.startsWith('tour-sample-')), isTrue);
    expect(c.read(feedProvider).items.every((i) => i.id.contains('tour-sample-')), isTrue);

    tour.finish();
    expect(c.read(libraryProvider).groups, same(_real));
    expect(c.read(feedProvider).items, same(_realFeed));
    expect(c.read(settingsProvider).tutorialDone, isTrue);
    expect(c.read(tutorialProvider), isNull);
  });

  test('a scan asked for during the tour waits, and never replaces the samples', () async {
    final c = ProviderContainer(overrides: _overrides());
    addTearDown(c.dispose);
    final tour = c.read(tutorialProvider.notifier)..start();
    final samples = c.read(libraryProvider).groups;

    await c.read(libraryProvider.notifier).scan();
    expect(c.read(libraryProvider).groups, same(samples));
    tour.finish();
  });

  test('each step opens its tab, and Back and Next move through them', () {
    final c = ProviderContainer(overrides: _overrides());
    addTearDown(c.dispose);
    final tour = c.read(tutorialProvider.notifier)..start();
    for (var i = 0; i < tutorialSteps.length; i++) {
      expect(c.read(tutorialProvider), i);
      expect(c.read(activeTabProvider), tutorialSteps[i].tab);
      if (i < tutorialSteps.length - 1) tour.next();
    }
    tour.back();
    expect(c.read(tutorialProvider), tutorialSteps.length - 2);
    tour.next();
    tour.next();
    expect(c.read(tutorialProvider), isNull, reason: 'Next on the last step ends it');
  });

  Future<ProviderContainer> pumpOverlay(WidgetTester t, {String libraryDir = ''}) async {
    final c = ProviderContainer(overrides: _overrides(libraryDir: libraryDir));
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: TutorialOverlay())),
    ));
    await t.pump();
    return c;
  }

  testWidgets('starts by itself on a first run, and Skip ends it', (t) async {
    final c = await pumpOverlay(t);
    expect(find.text('Welcome to VN Pathfinder'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pump();
    expect(find.text('Library'), findsOneWidget);
    await t.tap(find.text('Skip tour'));
    await t.pump();
    expect(find.text('Library'), findsNothing);
    expect(c.read(settingsProvider).tutorialDone, isTrue);
    expect(c.read(libraryProvider).groups, same(_real));
  });

  testWidgets('stays away for someone who already has a library folder', (t) async {
    await pumpOverlay(t, libraryDir: r'D:\Games');
    expect(find.text('Welcome to VN Pathfinder'), findsNothing);
  });
}
