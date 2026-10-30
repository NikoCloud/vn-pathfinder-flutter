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

  /// A metadata field from the newest version that has it. Fetch Metadata
  /// saves into the then-latest version's folder, so a newly installed
  /// version starts without .vnpf/metadata.json — fall back to older versions
  /// the way cover art and screenshots already do.
  String newestMeta(String Function(GameVersion v) field) {
    for (final v in versions.reversed) {
      final value = field(v);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  // Effective title: newest metadata title > latest version's parsed name >
  // group display name
  String get effectiveTitle {
    final t = newestMeta((v) => v.metaTitle);
    if (t.isNotEmpty) return t;
    final parsed = latestVersion?.displayName;
    return (parsed != null && parsed.isNotEmpty) ? parsed : displayName;
  }

  // Developer from the newest version that has one
  String get effectiveDeveloper => newestMeta((v) => v.effectiveDeveloper);

  /// Fetched tags from the newest version that has any (see [newestMeta]).
  List<String> get newestMetaTags {
    for (final v in versions.reversed) {
      if (v.metaTags.isNotEmpty) return v.metaTags;
    }
    return const [];
  }

  /// No version has a .vnpf folder, so nothing has been saved for this game.
  /// One version is enough, since metadata and art fall back across versions.
  bool get isUnfetched => !versions.any((v) => v.hasVnpf);

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
