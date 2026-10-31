import '../services/scanner_service.dart' show compareVersionStrings;

/// A stop on a game's version path.
class PathNode {
  final String version;
  final bool installed;
  final bool latest;

  /// The version you last played: "You are here".
  final bool here;

  const PathNode(this.version, {this.installed = false, this.latest = false, this.here = false});
}

String _plain(String version) => version.trim().toLowerCase().replaceFirst(RegExp(r'^v\.?'), '');

bool sameVersion(String a, String b) => _plain(a) == _plain(b);

/// The route from the oldest version worth showing to the newest known: every
/// installed version and the latest, then recent changelog versions up to
/// [limit] stops, oldest first.
List<PathNode> buildVersionPath({
  required List<String> installed,
  required List<String> changelog,
  required String latest,
  String played = '',
  int limit = 7,
}) {
  final keep = <String, String>{};
  void add(String version) {
    if (version.trim().isNotEmpty) keep.putIfAbsent(_plain(version), () => version);
  }

  installed.forEach(add);
  add(latest);
  for (final version in changelog) {
    if (keep.length >= limit) break;
    add(version);
  }

  final ordered = keep.values.toList()..sort(compareVersionStrings);
  final newest = latest.trim().isNotEmpty ? latest : (ordered.isEmpty ? '' : ordered.last);
  return [
    for (final version in ordered)
      PathNode(
        version,
        installed: installed.any((v) => sameVersion(v, version)),
        latest: sameVersion(version, newest),
        here: played.isNotEmpty && sameVersion(version, played),
      ),
  ];
}
