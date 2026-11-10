import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/providers/shell_provider.dart';
import 'package:vn_pathfinder/providers/update_provider.dart';
import 'package:vn_pathfinder/widgets/title_bar.dart';

class _Settings extends SettingsNotifier {
  _Settings(AppSettings s) {
    state = s;
  }
  @override
  Future<void> save() async {}
}

Future<ProviderContainer> _pump(WidgetTester t, {required bool lockdown}) async {
  t.view.physicalSize = const Size(1400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  final c = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) => _Settings(AppSettings(lockdown: lockdown, tutorialDone: true))),
    updateCheckProvider.overrideWith((ref) => UpdateCheckNotifier.seeded(ref)),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: AppTitleBar())),
  ));
  return c;
}

void main() {
  testWidgets('in Lockdown the Feed tab cannot be chosen, and says why', (t) async {
    final c = await _pump(t, lockdown: true);
    await t.tap(find.text('Feed'));
    await t.pump();
    expect(c.read(activeTabProvider), isNot(AppTab.feed));
    expect(find.byTooltip('The Feed needs to go online. Turn off Lockdown to use it.'), findsOneWidget);
  });

  testWidgets('online, the Feed tab opens the Feed', (t) async {
    final c = await _pump(t, lockdown: false);
    await t.tap(find.text('Feed'));
    await t.pump();
    expect(c.read(activeTabProvider), AppTab.feed);
  });

  testWidgets('Lockdown coming on while the Feed is open moves to Home', (t) async {
    final c = await _pump(t, lockdown: false);
    c.read(activeTabProvider.notifier).state = AppTab.feed;
    await t.pump();
    c.read(settingsProvider.notifier).setLockdown(true);
    await t.pump();
    await t.pump();
    expect(c.read(activeTabProvider), AppTab.home);
  });
}
