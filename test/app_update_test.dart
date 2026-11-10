import 'dart:convert';
import 'dart:io';
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

  group('what changed since your version (#23)', () {
    const notes = """Bug fixes from tester reports.

## Bug fixes
- **Adding a library folder could crash the app** while reading a large one.

## Install
On beta 2, use the **Update** button in the title bar. Otherwise:
- **Installer:** `VN-Pathfinder-2.0.0-beta.2.1-windows-setup.exe`.

## Checksums (SHA-256)
```
7c7e...  VN-Pathfinder-2.0.0-beta.2.1-windows-setup.exe
```""";

    test('keeps the changes and drops Install, Checksums and code blocks', () {
      final out = releaseChanges(notes);
      expect(out, contains('Bug fixes from tester reports.'));
      expect(out, contains('Adding a library folder could crash'));
      expect(out, isNot(contains('Install')));
      expect(out, isNot(contains('setup.exe')));
      expect(out, isNot(contains('Checksums')));
    });

    test('lists every newer release, newest first, and none that are older', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode([
            for (final v in ['v0.9.0', 'v99.0.0-beta.1', 'v99.0.0', 'v99.0.0-beta.2', 'v1.0.0-alpha'])
              {'tag_name': v, 'name': v, 'body': 'notes for $v', 'html_url': '', 'assets': []},
            {'tag_name': 'v100.0.0', 'draft': true, 'body': '', 'assets': []},
          ]))
          ..close();
      });
      AppUpdateService.releasesUrlForTesting = 'http://127.0.0.1:${server.port}/releases';
      addTearDown(() => AppUpdateService.releasesUrlForTesting = null);

      final r = (await AppUpdateService.newerRelease())!;
      expect(r.version, '99.0.0');
      expect(r.since.map((x) => x.version), ['99.0.0', '99.0.0-beta.2', '99.0.0-beta.1']);
    });
  });
}
