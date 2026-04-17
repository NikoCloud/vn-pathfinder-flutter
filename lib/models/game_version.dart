import 'dart:io';

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
  String get metaEngine      => metadata['engine'] as String? ?? '';

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
  );
}
