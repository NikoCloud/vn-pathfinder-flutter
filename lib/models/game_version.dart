import 'dart:io';

/// What a version's Ren'Py save files say — read at scan time.
class SaveInfo {
  /// Newest save or `persistent` file (Ren'Py writes `persistent` the first
  /// time a game runs), local or AppData. Null if there are none.
  final DateTime? lastSaveAt;

  /// This version's own game/saves has saves. Ren'Py writes every save there
  /// as well as to AppData, so a freshly installed version starts without any.
  final bool hasLocalSaves;

  /// Saves the player made: page/slot saves ("1-1-LT1") and quicksaves.
  final int manualSaves;

  /// Ren'Py autosaves ("auto-1-LT1"), written before choices.
  final int autoSaves;

  /// The game's own version (config.version) recorded in the newest save.
  final String? newestSaveVersion;
  final DateTime? newestSaveAt;

  const SaveInfo({
    this.lastSaveAt,
    this.hasLocalSaves = false,
    this.manualSaves = 0,
    this.autoSaves = 0,
    this.newestSaveVersion,
    this.newestSaveAt,
  });
}

class GameVersion {
  final String folderName;
  final Directory folderPath;
  final String baseKey;
  final String versionStr;
  final String displayName;
  final File? exePath;
  final Directory localSaveDir;
  final Directory? appdataSaveDir;
  final Map<String, dynamic> metadata;
  final bool isRenpy;
  final SaveInfo saves;

  /// This folder has a .vnpf folder, where Fetch Metadata saves its results.
  final bool hasVnpf;

  const GameVersion({
    required this.folderName,
    required this.folderPath,
    required this.baseKey,
    required this.versionStr,
    required this.displayName,
    this.exePath,
    required this.localSaveDir,
    this.appdataSaveDir,
    this.metadata = const {},
    this.isRenpy = true,
    this.saves = const SaveInfo(),
    this.hasVnpf = false,
  });

  // Metadata convenience getters (sourced from .vnpf/metadata.json)
  String get metaTitle       => metadata['title'] as String? ?? '';
  String get metaDeveloper   => metadata['developer'] as String? ?? '';
  String get metaSynopsis    => metadata['synopsis'] as String? ?? '';
  List<String> get metaImages => (metadata['images'] as List?)
      ?.map((e) => e.toString()).toList() ?? [];
  String get metaSourceUrl   => metadata['source_url'] as String? ?? '';
  String get metaF95Url      => metadata['f95_url'] as String? ?? '';
  String get metaVndbUrl     => metadata['vndb_url'] as String? ?? '';
  String get metaItchUrl     => metadata['itch_url'] as String? ?? '';
  String get metaLcUrl       => metadata['lc_url'] as String? ?? '';
  String get metaAzcUrl      => metadata['azc_url'] as String? ?? '';
  String get metaEngine      => metadata['engine'] as String? ?? '';
  String get metaLaunchArgs  => metadata['launch_arguments'] as String? ?? '';

  /// Tags fetched from metadata providers (stored in .vnpf/metadata.json).
  /// Reads both 'tags_fetched' (2.0 format) and 'tags' (1.0 legacy format).
  List<String> get metaTags {
    final fromFetched = (metadata['tags_fetched'] as List?)
        ?.map((e) => e.toString()).toList() ?? [];
    final fromTags = (metadata['tags'] as List?)
        ?.map((e) => e.toString()).toList() ?? [];
    // Merge: prefer tags_fetched, append any tags not already present
    final seen = <String>{};
    return [...fromFetched, ...fromTags]
        .where((t) => t.isNotEmpty && seen.add(t))
        .toList();
  }

  // Effective display name: custom metadata title > parsed display name
  String get effectiveTitle => metaTitle.isNotEmpty ? metaTitle : displayName;

  // Effective developer from metadata
  String get effectiveDeveloper => metaDeveloper;

  GameVersion copyWith({
    Map<String, dynamic>? metadata,
    File? exePath,
    Directory? appdataSaveDir,
  }) => GameVersion(
    folderName: folderName,
    folderPath: folderPath,
    baseKey: baseKey,
    versionStr: versionStr,
    displayName: displayName,
    exePath: exePath ?? this.exePath,
    localSaveDir: localSaveDir,
    appdataSaveDir: appdataSaveDir ?? this.appdataSaveDir,
    metadata: metadata ?? this.metadata,
    isRenpy: isRenpy,
    saves: saves,
    hasVnpf: hasVnpf,
  );
}
