// UserData — schema v4 (mirrors 1.0 exactly)
// Persisted to %APPDATA%/VN Pathfinder/userdata.json

class UserData {
  // v1
  final Map<String, String> notes;               // base_key → note text
  final Set<String> hidden;                       // base_key → hidden from list
  final Set<String> manualPlayed;                 // folder_name → force-played
  final Set<String> manualUnplayed;               // folder_name → force-unplayed
  final Map<String, String> customDisplayNames;   // base_key → display name

  // v2
  final Map<String, int> playtime;               // folder_name → seconds
  final Map<String, String> lastPlayed;          // folder_name → ISO datetime
  final Map<String, int> playCount;              // folder_name → N
  final Map<String, List<String>> tags;          // base_key → [tag, ...]
  final Map<String, String> customArt;           // base_key → absolute path
  final Map<String, String> patchAssignments;    // archive_name → base_key

  // v3 / v4
  // Key: "{base_key}::{version_str or '_'}" → {patch_filename: is_active}
  final Map<String, Map<String, bool>> appliedPatches;
  final List<String> customPresets;              // user-promoted preset tags

  const UserData({
    this.notes = const {},
    this.hidden = const {},
    this.manualPlayed = const {},
    this.manualUnplayed = const {},
    this.customDisplayNames = const {},
    this.playtime = const {},
    this.lastPlayed = const {},
    this.playCount = const {},
    this.tags = const {},
    this.customArt = const {},
    this.patchAssignments = const {},
    this.appliedPatches = const {},
    this.customPresets = const [],
  });

  factory UserData.empty() => const UserData(
    hidden: {},
    manualPlayed: {},
    manualUnplayed: {},
  );

  factory UserData.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    return UserData(
      notes: Map<String, String>.from(json['notes'] as Map? ?? {}),
      hidden: Set<String>.from(json['hidden'] as List? ?? []),
      manualPlayed: Set<String>.from(json['manual_played'] as List? ?? []),
      manualUnplayed: Set<String>.from(json['manual_unplayed'] as List? ?? []),
      customDisplayNames: Map<String, String>.from(
          json['custom_display_names'] as Map? ?? {}),
      playtime: Map<String, int>.from(json['playtime'] as Map? ?? {}),
      lastPlayed: Map<String, String>.from(json['last_played'] as Map? ?? {}),
      playCount: Map<String, int>.from(json['play_count'] as Map? ?? {}),
      tags: (json['tags'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, List<String>.from(v as List? ?? []))),
      customArt: Map<String, String>.from(json['custom_art'] as Map? ?? {}),
      patchAssignments: Map<String, String>.from(
          json['patch_assignments'] as Map? ?? {}),
      // v3→v4: applied_patches key format changed; reset on migration
      appliedPatches: version >= 4
          ? (json['applied_patches'] as Map? ?? {}).map((k, v) =>
              MapEntry(k as String,
                  Map<String, bool>.from(v as Map? ?? {})))
          : {},
      customPresets: List<String>.from(json['custom_presets'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 4,
    'notes': notes,
    'hidden': hidden.toList()..sort(),
    'manual_played': manualPlayed.toList()..sort(),
    'manual_unplayed': manualUnplayed.toList()..sort(),
    'custom_display_names': customDisplayNames,
    'playtime': playtime,
    'last_played': lastPlayed,
    'play_count': playCount,
    'tags': tags,
    'custom_art': customArt,
    'patch_assignments': patchAssignments,
    'applied_patches': appliedPatches,
    'custom_presets': customPresets,
  };

  UserData copyWith({
    Map<String, String>? notes,
    Set<String>? hidden,
    Set<String>? manualPlayed,
    Set<String>? manualUnplayed,
    Map<String, String>? customDisplayNames,
    Map<String, int>? playtime,
    Map<String, String>? lastPlayed,
    Map<String, int>? playCount,
    Map<String, List<String>>? tags,
    Map<String, String>? customArt,
    Map<String, String>? patchAssignments,
    Map<String, Map<String, bool>>? appliedPatches,
    List<String>? customPresets,
  }) => UserData(
    notes: notes ?? this.notes,
    hidden: hidden ?? this.hidden,
    manualPlayed: manualPlayed ?? this.manualPlayed,
    manualUnplayed: manualUnplayed ?? this.manualUnplayed,
    customDisplayNames: customDisplayNames ?? this.customDisplayNames,
    playtime: playtime ?? this.playtime,
    lastPlayed: lastPlayed ?? this.lastPlayed,
    playCount: playCount ?? this.playCount,
    tags: tags ?? this.tags,
    customArt: customArt ?? this.customArt,
    patchAssignments: patchAssignments ?? this.patchAssignments,
    appliedPatches: appliedPatches ?? this.appliedPatches,
    customPresets: customPresets ?? this.customPresets,
  );
}
