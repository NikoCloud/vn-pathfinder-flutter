import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/services/app_update_service.dart';

void main() {
  group('compareAppVersions', () {
    test('orders pre-releases below the release they lead to', () {
      final ordered = ['2.0.0-alpha', '2.0.0-alpha.2', '2.0.0-beta.1', '2.0.0-beta.2', '2.0.0-beta.10', '2.0.0-rc.1', '2.0.0', '2.0.1', '2.1.0'];
      for (var i = 0; i < ordered.length - 1; i++) {
        expect(compareAppVersions(ordered[i + 1], ordered[i]), greaterThan(0), reason: '${ordered[i + 1]} > ${ordered[i]}');
        expect(compareAppVersions(ordered[i], ordered[i + 1]), lessThan(0), reason: '${ordered[i]} < ${ordered[i + 1]}');
      }
    });

    test('ignores a leading v and build numbers', () {
      expect(compareAppVersions('v2.0.0-beta.1', '2.0.0-beta.1'), 0);
      expect(compareAppVersions('2.0.0-beta.1+7', '2.0.0-beta.1'), 0);
    });

    test('an old 0.9.0 tag is not newer than 2.0 builds', () {
      expect(compareAppVersions('v0.9.0', '2.0.0-alpha.2'), lessThan(0));
    });
  });

  test('reads the installer and its checksum from a GitHub release', () {
    final r = AppRelease.fromJson({
      'tag_name': 'v2.0.0-beta.2',
      'body': 'notes',
      'html_url': 'https://example.invalid/r',
      'assets': [
        {'name': 'VN-Pathfinder-2.0.0-beta.2-windows-portable.zip', 'browser_download_url': 'zip', 'size': 1},
        {'name': 'VN-Pathfinder-2.0.0-beta.2-windows-setup.exe', 'browser_download_url': 'exe', 'size': 42, 'digest': 'sha256:ABC123'},
      ],
    });
    expect(r.version, '2.0.0-beta.2');
    expect(r.installerUrl, 'exe');
    expect(r.installerSize, 42);
    expect(r.installerSha256, 'abc123');
    expect(r.hasInstaller, isTrue);
  });
}
