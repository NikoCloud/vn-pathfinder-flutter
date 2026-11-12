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

/// The numbers in a version, in order: "Chapter 3.6.5 Patched" → 3, 6, 5.
List<String> _numbers(String version) => RegExp(r'\d+').allMatches(version).map((m) => m[0]!).toList();

/// The same version spelled two ways ("Chapter 3.6.5 Patched" and "3.6.5"):
/// the same numbers in the same order.
bool _sameNumbers(String a, String b) {
  final x = _numbers(a), y = _numbers(b);
  if (x.isEmpty || x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (int.parse(x[i]) != int.parse(y[i])) return false;
  }
  return true;
}

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
  // A version already on the path in another spelling (the forum's
  // "Chapter 3.6.5 Patched" for an installed "3.6.5") isn't a second stop.
  String? onPath(String version) => keep.values
      .where((v) => sameVersion(v, version) || _sameNumbers(v, version))
      .firstOrNull;
  void add(String version, {bool always = false}) {
    if (version.trim().isEmpty) return;
    if (!always && onPath(version) != null) return;
    keep.putIfAbsent(_plain(version), () => version);
  }

  for (final v in installed) {
    add(v, always: true);
  }
  add(latest);
  for (final version in changelog) {
    if (keep.length >= limit) break;
    add(version);
  }

  final ordered = keep.values.toList()..sort(compareVersionStrings);
  final newest = latest.trim().isNotEmpty ? (onPath(latest) ?? latest) : (ordered.isEmpty ? '' : ordered.last);
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
