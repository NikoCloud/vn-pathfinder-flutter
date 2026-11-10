import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/settings_provider.dart';

AppSettings _roundTrip(AppSettings s) =>
    AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);

void main() {
  test('cleared archives and the Archive view survive a restart', () {
    final s = _roundTrip(const AppSettings(
      hiddenArchives: [r'D:\Games\URM.rpa', r'E:\VN\Game-0.5-pc.zip'],
      archiveDetails: true,
      archiveCardWidth: 300,
    ));
    expect(s.hiddenArchives, [r'D:\Games\URM.rpa', r'E:\VN\Game-0.5-pc.zip']);
    expect(s.archiveDetails, isTrue);
    expect(s.archiveCardWidth, 300);
  });

  test('settings from before this release show every archive as cards', () {
    final s = AppSettings.fromJson({'library_dir': r'D:\Games'});
    expect(s.hiddenArchives, isEmpty);
    expect(s.archiveDetails, isFalse);
    expect(s.archiveCardWidth, 272);
  });
}
