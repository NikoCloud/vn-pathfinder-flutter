import 'dart:io';

enum ArchiveType { zip, rar, sevenZip, rpa, rpy, py, unknown }

extension ArchiveTypeExt on ArchiveType {
  String get label => switch (this) {
    ArchiveType.zip => 'ZIP',
    ArchiveType.rar => 'RAR',
    ArchiveType.sevenZip => '7Z',
    ArchiveType.rpa => 'RPA',
    ArchiveType.rpy => 'RPY',
    ArchiveType.py  => 'PY',
    ArchiveType.unknown => '???',
  };

  static ArchiveType fromExtension(String ext) => switch (ext.toLowerCase()) {
    '.zip' => ArchiveType.zip,
    '.rar' => ArchiveType.rar,
    '.7z'  => ArchiveType.sevenZip,
    '.rpa' => ArchiveType.rpa,
    '.rpy' => ArchiveType.rpy,
    '.py'  => ArchiveType.py,
    _      => ArchiveType.unknown,
  };

  /// A game download the app can extract.
  bool get canExtract => this == ArchiveType.zip || needs7Zip;

  /// Extracted with 7-Zip, which has to be installed.
  bool get needs7Zip => this == ArchiveType.rar || this == ArchiveType.sevenZip;
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
