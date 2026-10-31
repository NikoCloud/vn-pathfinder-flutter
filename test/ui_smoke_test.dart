import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vn_pathfinder/models/archive_item.dart';
import 'package:vn_pathfinder/models/feed_item.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/feed_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/providers/shell_provider.dart';
import 'package:vn_pathfinder/providers/update_provider.dart';
import 'package:vn_pathfinder/services/save_shots.dart';
import 'package:vn_pathfinder/widgets/app_shell.dart';

// Every tab and both kinds of game page, on the app's own fonts, at the largest
// common window and the smallest one the app allows. Layout errors fail the
// test, which is how a page that would come up blank gets caught.

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
  @override
  Future<void> scan() async {}
}

class _UserData extends UserDataNotifier {
  _UserData(super.ref, UserData data) : super(initial: data);
  @override
  Future<void> save() async {}
}

class _Settings extends SettingsNotifier {
  _Settings(AppSettings s) {
    state = s;
  }
  @override
  Future<void> save() async {}
}

Future<void> _loadFont(String family, String prefix) async {
  final loader = FontLoader(family);
  for (final file in Directory('assets/fonts').listSync().whereType<File>()) {
    if (file.path.endsWith('.ttf') && p.basename(file.path).startsWith(prefix)) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await loader.load();
}

GameGroup _game(String title, String version, String developer) {
  final key = title.toLowerCase();
  return GameGroup(
    baseKey: key,
    displayName: title,
    versions: [
      GameVersion(
        folderName: '$title-$version',
        folderPath: Directory(title),
        baseKey: key,
        versionStr: version,
        displayName: title,
        localSaveDir: Directory('saves'),
        hasVnpf: true,
        metadata: {
          'title': title,
          'developer': developer,
          'synopsis': 'A longer description of the game, so the page has something to lay out.',
          'tags_fetched': ['romance', 'comedy'],
          'f95_url': 'https://f95zone.to/threads/${key.replaceAll(' ', '-')}.1001/',
        },
      ),
    ],
  );
}

GameGroup _withArchives(GameGroup g, List<String> names) => g.copyWith(archives: [
      for (final name in names)
        ArchiveItem(archivePath: File(name), baseKey: g.baseKey, versionStr: '1.0', sizeBytes: 2048),
    ]);

RawFeedItem _release(String title, String version, String source, int hours, {String kind = ''}) => RawFeedItem(
      id: '$source::$title',
      source: source,
      sourceLabel: source,
      title: title,
      rawBody: ['Version: $version', 'Developer: A Rather Long Developer Name', 'Tags: romance, comedy', if (kind.isNotEmpty) 'Kind: $kind'].join('\n'),
      url: 'https://f95zone.to/threads/${title.toLowerCase().replaceAll(' ', '-')}.1001/',
      publishedAt: DateTime.now().subtract(Duration(hours: hours)),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont('Inter', 'Inter-');
    await _loadFont('JetBrains Mono', 'JetBrainsMono-');
    await _loadFont('Newsreader', 'Newsreader-Display');
    await _loadFont('Newsreader Text', 'NewsreaderText');
  });

  final groups = [
    _game('Paper Cranes', '0.8.2', 'Lantern Works'),
    _game('A Very Long Game Title That Keeps On Going For Quite Some Time', 'Chapter-3', 'Northwind'),
    _withArchives(_game('Sandglass', '1.0', 'Dune Studio'), ['Sandglass-1.0-pc.zip', 'Sandglass-mod.rpa']),
    const GameGroup(baseKey: 'unknown', displayName: 'Unknown'),
    _withArchives(const GameGroup(baseKey: 'unknown2', displayName: 'Unknown Two'), ['Unknown_Download.zip']),
  ];
  final items = [
    _release('Paper Cranes', '0.9', 'f95zone', 2),
    _release('Neon Parallel', '0.4.1', 'lewdcorner', 3, kind: 'new'),
    _release('Winter Letters', 'Final', 'azc', 30),
    _release('Older Game', '0.2', 'f95zone', 200),
  ];

  for (final (name, size) in [('large', const Size(1440, 900)), ('smallest', const Size(960, 600))]) {
    for (final theme in ['dark', 'light']) {
      testWidgets('every screen lays out: $name, $theme', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);

        final data = UserData(
          playtime: const {'paper cranes': 4000},
          lastPlayed: {'paper cranes': DateTime.now().toIso8601String(), 'sandglass': DateTime(2026).toIso8601String()},
          sessions: [PlaySession('paper cranes', DateTime.now(), 4000)],
        );
        final container = ProviderContainer(overrides: [
          settingsProvider.overrideWith(
              (ref) => _Settings(AppSettings(lockdown: true, feedEnabled: true, feedSourceAzc: true, theme: theme))),
          libraryProvider.overrideWith((ref) => _Library(ref, groups)),
          userDataProvider.overrideWith((ref) => _UserData(ref, data)),
          feedProvider.overrideWith((ref) => FeedNotifier.seeded(ref, FeedState(items: items))),
          updateCheckProvider.overrideWith((ref) => UpdateCheckNotifier.seeded(ref)),
          saveShotProvider.overrideWith((ref, key) async => null),
        ]);
        addTearDown(container.dispose);

        await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: container.read(appThemeDataProvider), home: const AppShell()),
        ));
        await t.pump();

        for (final tab in AppTab.values) {
          container.read(activeTabProvider.notifier).state = tab;
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
        }
        container.read(libraryDetailsProvider.notifier).state = true;
        container.read(activeTabProvider.notifier).state = AppTab.library;
        await t.pump();

        // A game you have with a newer version, then a game you don't have.
        container.read(gamePageProvider.notifier).state =
            GameTarget(baseKey: 'paper cranes', item: items.first, origin: AppTab.feed);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        container.read(gamePageProvider.notifier).state = GameTarget(item: items[1], origin: AppTab.feed);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        container.read(gamePageProvider.notifier).state = null;

        // Assign, in both of its modes, and search that finds nothing.
        container.read(activeTabProvider.notifier).state = AppTab.archive;
        await t.pump();
        await t.tap(find.text('Unknown_Download.zip'));
        await t.pump();
        await t.tap(find.text('Assign…'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Target game'), findsOneWidget);
        expect(find.text('Sandglass'), findsWidgets);
        await t.enterText(find.widgetWithText(TextField, 'Search'), 'no such game');
        await t.pump();
        expect(find.text('Nothing matches.'), findsOneWidget);
        await t.tap(find.text('Game data'));
        await t.pump();
        expect(find.text('Use the data from'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        container.read(finderOpenProvider.notifier).state = true;
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 10));
      });
    }
  }
}
