import 'dart:io';

enum ArchiveType { zip, rar, rpa, rpy, py, unknown }

extension ArchiveTypeExt on ArchiveType {
  String get label => switch (this) {
    ArchiveType.zip => 'ZIP',
    ArchiveType.rar => 'RAR',
    ArchiveType.rpa => 'RPA',
    ArchiveType.rpy => 'RPY',
    ArchiveType.py  => 'PY',
    ArchiveType.unknown => '???',
  };

  static ArchiveType fromExtension(String ext) => switch (ext.toLowerCase()) {
    '.zip' => ArchiveType.zip,
    '.rar' => ArchiveType.rar,
    '.rpa' => ArchiveType.rpa,
    '.rpy' => ArchiveType.rpy,
    '.py'  => ArchiveType.py,
    _      => ArchiveType.unknown,
  };
}

class ArchiveItem {
  final File archivePath;
  final String baseKey;
  final String versionStr;
  final String? matchedFolder;
  final String modTime; // ISO 8601 date string YYYY-MM-DD
  final int? sizeBytes;
  final bool isExtracted;

  const ArchiveItem({
    required this.archivePath,
    required this.baseKey,
    required this.versionStr,
    this.matchedFolder,
    this.modTime = '',
    this.sizeBytes,
    this.isExtracted = false,
  });

  ArchiveType get type =>
      ArchiveTypeExt.fromExtension(archivePath.path.split('.').last.toLowerCase() == archivePath.path
          ? '' : '.${archivePath.path.split('.').last}');

  String get name => archivePath.uri.pathSegments.last;

  ArchiveItem copyWith({
    String? matchedFolder,
    bool? isExtracted,
    int? sizeBytes,
  }) => ArchiveItem(
    archivePath: archivePath,
    baseKey: baseKey,
    versionStr: versionStr,
    matchedFolder: matchedFolder ?? this.matchedFolder,
    modTime: modTime,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    isExtracted: isExtracted ?? this.isExtracted,
  );
}
