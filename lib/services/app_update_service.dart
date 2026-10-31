import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game_status.dart';

/// This build's version, shown in Settings → About and compared with releases.
const appVersion = '2.0.0-alpha';

/// Looks for a newer VN Pathfinder on GitHub. No account or login involved.
class AppUpdateService {
  static const _latest = 'https://api.github.com/repos/NikoCloud/vn-pathfinder-flutter/releases/latest';

  /// The newer release's tag, or null when this build is current, when no
  /// release has been published, or when the check can't be made.
  static Future<String?> newerRelease() async {
    try {
      final resp = await http.get(Uri.parse(_latest), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'VN-Pathfinder/$appVersion',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      final tag = json is Map ? '${json['tag_name'] ?? ''}' : '';
      return tag.isNotEmpty && isClearlyNewer(tag, appVersion) ? tag : null;
    } catch (_) {
      return null;
    }
  }
}
