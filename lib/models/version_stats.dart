/// What one version of a Ren'Py game holds, counted from its own files (#44).
/// Nothing is sent anywhere: the counts come from the folder on this PC.
class VersionStats {
  /// Full-screen, landscape pictures: scenes, not interface art or sprites.
  final int renders;

  /// Video files.
  final int animations;

  /// Words of dialogue and narration. Null when the scripts couldn't be read.
  final int? words;

  /// Audio files, and how many of them sit in a music folder.
  final int audio;
  final int music;

  /// Size of the version's folder on disk, in bytes.
  final int bytes;

  /// Archives in a developer's own format that couldn't be opened, so the
  /// counts leave out whatever is in them.
  final int unreadableArchives;

  /// Identifies the folder as it was when counted; a different one means
  /// it changed and is counted again.
  final String signature;
  final DateTime countedAt;

  /// When the version was built: the newest time on its game folder's
  /// archives and scripts, which unpacking keeps. Puts versions in release
  /// order when their numbers don't ("0.201" before "0.4"). Null if unknown.
  final DateTime? builtAt;

  const VersionStats({
    required this.renders,
    required this.animations,
    required this.words,
    required this.audio,
    required this.music,
    required this.bytes,
    required this.unreadableArchives,
    required this.signature,
    required this.countedAt,
    this.builtAt,
  });

  /// Nothing at all could be counted: the game keeps everything in a format
  /// the app can't open.
  bool get empty => renders == 0 && animations == 0 && audio == 0 && (words ?? 0) == 0;

  factory VersionStats.fromJson(Map json) => VersionStats(
        renders: json['renders'] as int? ?? 0,
        animations: json['animations'] as int? ?? 0,
        words: json['words'] as int?,
        audio: json['audio'] as int? ?? 0,
        music: json['music'] as int? ?? 0,
        bytes: json['bytes'] as int? ?? 0,
        unreadableArchives: json['unreadable_archives'] as int? ?? 0,
        signature: json['signature'] as String? ?? '',
        countedAt: DateTime.tryParse(json['counted_at'] as String? ?? '') ?? DateTime(0),
        builtAt: DateTime.tryParse(json['built_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'renders': renders,
        'animations': animations,
        if (words != null) 'words': words,
        'audio': audio,
        'music': music,
        'bytes': bytes,
        if (unreadableArchives > 0) 'unreadable_archives': unreadableArchives,
        'signature': signature,
        'counted_at': countedAt.toIso8601String(),
        if (builtAt != null) 'built_at': builtAt!.toIso8601String(),
      };
}
