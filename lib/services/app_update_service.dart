import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// This build's version, shown in Settings → About and compared with releases.
/// `tool/package_windows.ps1` reads it too, so it names the installer.
const appVersion = '2.0.0-beta.2';

/// One published VN Pathfinder release and its Windows installer.
class AppRelease {
  final String tag;
  final String name;
  final String notes;
  final String pageUrl;
  final String? installerUrl;
  final String? installerName;
  final int installerSize;

  /// Lowercase hex SHA-256 of the installer, as GitHub reports it.
  final String? installerSha256;

  const AppRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.pageUrl,
    this.installerUrl,
    this.installerName,
    this.installerSize = 0,
    this.installerSha256,
  });

  /// "v2.0.0-beta.2" → "2.0.0-beta.2".
  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');

  bool get hasInstaller => installerUrl != null && installerSha256 != null;

  factory AppRelease.fromJson(Map json) {
    Map? installer;
    for (final a in (json['assets'] as List? ?? const [])) {
      if (a is Map && '${a['name']}'.toLowerCase().endsWith('-windows-setup.exe')) {
        installer = a;
        break;
      }
    }
    final digest = '${installer?['digest'] ?? ''}';
    return AppRelease(
      tag: '${json['tag_name'] ?? ''}',
      name: '${json['name'] ?? json['tag_name'] ?? ''}',
      notes: '${json['body'] ?? ''}'.trim(),
      pageUrl: '${json['html_url'] ?? AppUpdateService.releasesPage}',
      installerUrl: installer?['browser_download_url'] as String?,
      installerName: installer?['name'] as String?,
      installerSize: (installer?['size'] as num?)?.toInt() ?? 0,
      installerSha256: digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
    );
  }
}

/// Finds, downloads and installs newer VN Pathfinder releases from GitHub.
/// No account or login involved.
class AppUpdateService {
  static const releasesPage = 'https://github.com/NikoCloud/vn-pathfinder-flutter/releases';

  /// The releases list rather than `releases/latest`, which skips pre-releases.
  /// Every release counts until there is a stable one. Setting
  /// VNPF_RELEASES_URL points this at another list, for testing.
  static String get _releasesApi =>
      Platform.environment['VNPF_RELEASES_URL'] ??
      'https://api.github.com/repos/NikoCloud/vn-pathfinder-flutter/releases?per_page=20';

  static Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'VN-Pathfinder/$appVersion',
      };

  /// The newest release if it's newer than this build, otherwise null.
  /// Throws when GitHub can't be reached or answers with an error.
  static Future<AppRelease?> newerRelease() async {
    final resp = await http.get(Uri.parse(_releasesApi), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw HttpException('GitHub answered ${resp.statusCode}');
    final list = jsonDecode(resp.body);
    if (list is! List) throw const FormatException('Unexpected answer from GitHub');
    AppRelease? newest;
    for (final r in list) {
      if (r is! Map || r['draft'] == true) continue;
      final release = AppRelease.fromJson(r);
      if (release.tag.isEmpty) continue;
      if (newest == null || compareAppVersions(release.version, newest.version) > 0) newest = release;
    }
    if (newest == null || compareAppVersions(newest.version, appVersion) <= 0) return null;
    return newest;
  }

  /// True when this copy was put here by the installer, which can update it.
  /// A portable copy has no uninstaller next to it.
  static bool get isInstalled {
    final dir = p.dirname(Platform.resolvedExecutable);
    return File(p.join(dir, 'unins000.exe')).existsSync();
  }

  /// Downloads the release's installer to a temp folder and checks it against
  /// the size and SHA-256 GitHub reports. Returns the file once it checks out.
  static Future<File> download(AppRelease release, {void Function(double progress)? onProgress}) async {
    if (!release.hasInstaller) throw StateError('This release has no installer to download');
    final dir = Directory(p.join(Directory.systemTemp.path, 'VN Pathfinder', 'updates'));
    if (dir.existsSync()) {
      for (final old in dir.listSync()) {
        try {
          old.deleteSync(recursive: true);
        } catch (_) {}
      }
    } else {
      dir.createSync(recursive: true);
    }
    final file = File(p.join(dir.path, p.basename(release.installerName!)));

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(release.installerUrl!))..headers.addAll(_headers);
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw HttpException('Download failed: GitHub answered ${resp.statusCode}');
      final total = resp.contentLength ?? release.installerSize;

      final digestOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestOut);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      hasher.close();

      if (release.installerSize > 0 && received != release.installerSize) {
        file.deleteSync();
        throw StateError('The download was incomplete');
      }
      if (digestOut.value.toString() != release.installerSha256) {
        file.deleteSync();
        throw StateError("The download doesn't match the checksum GitHub published");
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Starts the installer silently and closes the app. The installer reuses
  /// the existing install folder, leaves app data alone and reopens the app.
  static Future<Never> installAndExit(File installer) async {
    await Process.start(
      installer.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Compares app versions the semver way: "2.0.0" > "2.0.0-beta.2" >
/// "2.0.0-beta.1" > "2.0.0-alpha.2". A leading "v" and "+build" are ignored.
int compareAppVersions(String a, String b) {
  (List<int>, List<String>) parse(String v) {
    final s = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final dash = s.indexOf('-');
    final core = (dash < 0 ? s : s.substring(0, dash)).split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pre = dash < 0 ? <String>[] : s.substring(dash + 1).split('.');
    return (core, pre);
  }

  final (ac, ap) = parse(a);
  final (bc, bp) = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < ac.length ? ac[i] : 0, y = i < bc.length ? bc[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (ap.isEmpty || bp.isEmpty) return ap.isEmpty == bp.isEmpty ? 0 : (ap.isEmpty ? 1 : -1);
  for (var i = 0; i < ap.length && i < bp.length; i++) {
    final x = int.tryParse(ap[i]), y = int.tryParse(bp[i]);
    final c = (x != null && y != null)
        ? x.compareTo(y)
        : (x != null) != (y != null)
            ? (x != null ? -1 : 1)
            : ap[i].compareTo(bp[i]);
    if (c != 0) return c;
  }
  return ap.length.compareTo(bp.length);
}
