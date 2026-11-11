import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';
import 'package:vn_pathfinder/widgets/common/kit.dart';

class _Settings extends SettingsNotifier {
  _Settings(AppSettings s) {
    state = s;
  }
  int saves = 0;
  @override
  Future<void> save() async => saves++;
}

void main() {
  // #36: every step of a size-slider drag remade the theme, which rebuilds
  // every widget in the app.
  test('changing the card size does not remake the theme; changing the accent does', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final settings = _Settings(const AppSettings());
    final container = ProviderContainer(overrides: [settingsProvider.overrideWith((ref) => settings)]);
    addTearDown(container.dispose);
    var themes = 0;
    container.listen(appThemeDataProvider, (_, _) => themes++);

    settings.setCardWidth(300);
    settings.setArchiveCardWidth(240);
    settings.setDiscreet(true);
    container.read(appThemeDataProvider); // providers recompute when read
    expect(themes, 0);

    settings.update((s) => s.copyWith(accentColor: '#ff0000'));
    container.read(appThemeDataProvider);
    expect(themes, 1);
  });

  test('a card size step changes the setting without writing the file', () {
    final settings = _Settings(const AppSettings());
    settings.setCardWidth(300);
    settings.setArchiveCardWidth(240);
    expect(settings.state.cardWidth, 300);
    expect(settings.state.archiveCardWidth, 240);
    expect(settings.saves, 0);
  });

  testWidgets('the size slider reports every step of a drag and asks to save once, on release', (t) async {
    final widths = <double>[];
    var ends = 0;
    var width = 272.0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => VpSizeSlider(
              details: false,
              width: width,
              onDetails: (_) {},
              onWidth: (w) => setState(() {
                width = w;
                widths.add(w);
              }),
              onEnd: () => ends++,
            ),
          ),
        ),
      ),
    ));

    final slider = t.getCenter(find.byType(VpSlider));
    final drag = await t.startGesture(slider);
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(6, 0));
      await t.pump();
    }
    expect(widths.length, greaterThan(2));
    expect(ends, 0, reason: 'nothing is saved while dragging');
    await drag.up();
    await t.pump();
    expect(ends, 1);
  });
}
