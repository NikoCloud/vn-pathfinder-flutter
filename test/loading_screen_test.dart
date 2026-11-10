import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/services/scanner_service.dart';
import 'package:vn_pathfinder/widgets/loading_screen.dart';

class _Library extends LibraryNotifier {
  _Library(super.ref, LibraryState s) {
    state = s;
  }
  void set(LibraryState s) => state = s;
  @override
  Future<void> scan() async {}
}

class _Settings extends SettingsNotifier {
  _Settings(AppSettings s) {
    state = s;
  }
  @override
  Future<void> save() async {}
}

late _Library _lib;

Future<void> _pump(WidgetTester t, LibraryState s, {bool discreet = false}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => _Settings(AppSettings(libraryDirs: const [r'D:\Games'], discreet: discreet))),
      libraryProvider.overrideWith((ref) => _lib = _Library(ref, s)),
    ],
    child: const MaterialApp(home: Scaffold(body: Stack(children: [LoadingScreen()]))),
  ));
}

void main() {
  const finding = LibraryState(loading: true, progress: ScanProgress(ScanStage.finding, done: 40, found: 12));

  testWidgets('hidden for the first half second, then shows the real count', (t) async {
    await _pump(t, finding);
    expect(find.textContaining('folders checked'), findsNothing);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Finding games · 40 folders checked · 12 found'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && loadingLines[ScanStage.finding]!.contains(w.data)), findsOneWidget);
  });

  testWidgets('reading saves shows a count out of the total and a filling bar', (t) async {
    await _pump(t, const LibraryState(loading: true, progress: ScanProgress(ScanStage.saves, done: 120, total: 240)));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('Reading saves · 120 of 240'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
  });

  testWidgets('Discreet mode uses plain lines', (t) async {
    await _pump(t, finding, discreet: true);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('Finding your games…'), findsOneWidget);
  });

  testWidgets('a folder that stalls is named', (t) async {
    await _pump(t, const LibraryState(
        loading: true, progress: ScanProgress(ScanStage.finding, folder: r'G:\F95 GAMES\Slow\Folder')));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(seconds: 3));
    expect(find.textContaining('Waiting for'), findsOneWidget);
    expect(find.textContaining(r'Slow\Folder'), findsOneWidget);
  });

  testWidgets('not shown once games are on screen, and steps aside after two minutes', (t) async {
    await _pump(t, finding);
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('folders checked'), findsOneWidget);
    await t.pump(LoadingScreen.giveUpAfter);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('folders checked'), findsNothing);

    _lib.set(const LibraryState(loading: false));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
