import 'game_version.dart';
import 'archive_item.dart';

class GameGroup {
  final String baseKey;
  final String displayName;
  final List<GameVersion> versions;
  final List<ArchiveItem> archives;

  const GameGroup({
    required this.baseKey,
    required this.displayName,
    this.versions = const [],
    this.archives = const [],
  });

  // Latest version (highest version string, last in sorted list)
  GameVersion? get latestVersion =>
      versions.isEmpty ? null : versions.last;

  // Effective title: metadata title from latest version > parsed display name
  String get effectiveTitle {
    final t = latestVersion?.effectiveTitle;
    return (t != null && t.isNotEmpty) ? t : displayName;
  }

  // Developer from latest version
  String get effectiveDeveloper => latestVersion?.effectiveDeveloper ?? '';

  GameGroup copyWith({
    String? displayName,
    List<GameVersion>? versions,
    List<ArchiveItem>? archives,
  }) => GameGroup(
    baseKey: baseKey,
    displayName: displayName ?? this.displayName,
    versions: versions ?? this.versions,
    archives: archives ?? this.archives,
  );
}
