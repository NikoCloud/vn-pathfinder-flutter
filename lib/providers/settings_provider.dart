import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../theme.dart';

// ── Settings Model ────────────────────────────────────────────────────────────

class AppSettings {
  final String libraryDir;
  final bool lockdown;
  final bool checkUpdates;
  final bool checkGameUpdates;   // ask F95Zone which version each game's thread is on
  final bool fetchMetadata;
  final bool allowProviderLogin;
  final bool allowDownloadLinks;
  final bool autoBackup;
  final bool minimizeToTray;
  final double slideshowInterval; // seconds
  final int concurrentExtractions;
  final bool deleteAfterExtract;
  final String theme;       // 'dark' | 'light' | 'system'
  final String accentColor; // hex string; AppColors.defaultAccentHex = the theme's own
  final double fontSize;
  final double sidebarWidth; // library sidebar in detail view, dragged by the user

  // Persisted site cookies (separate file, but held here for convenience)
  final Map<String, Map<String, String>> siteCredentials;

  // ── Feed settings ─────────────────────────────────────────────────────────
  final bool feedEnabled;
  final int feedRefreshHours;    // 6 | 12 | 24 | 0 = manual only
  final bool feedSourceF95;      // poll F95Zone forum RSS
  final bool feedSourceLC;       // poll LewdCorner forum RSS
  final bool feedSourceAzc;      // poll Azkosel's Corner forum RSS (both game categories)

  // ── Look ───────────────────────────────────────────────────────────────
  final bool discreet;           // blur all art
  final String? feedSeenAt;      // ISO time of the last "Mark all seen"
  final double cardWidth;        // Library card width
  final bool keepOldVersion;     // keep the old version when an update lands
  final Map<String, Map<String, dynamic>> savedViews; // Library views by name

  const AppSettings({
    this.libraryDir = '',
    this.lockdown = true,
    this.checkUpdates = true,
    this.checkGameUpdates = true,
    this.fetchMetadata = true,
    this.allowProviderLogin = true,
    this.allowDownloadLinks = true,
    this.autoBackup = true,
    this.minimizeToTray = false,
    this.slideshowInterval = 5.0,
    this.concurrentExtractions = 1,
    this.deleteAfterExtract = false,
    this.theme = 'dark',
    this.accentColor = AppColors.defaultAccentHex,
    this.fontSize = 13.0,
    this.sidebarWidth = AppLayout.sidebarWidth,
    this.siteCredentials = const {},
    this.feedEnabled = false,
    this.feedRefreshHours = 6,
    this.feedSourceAzc = false,
    this.feedSourceF95 = true,
    this.feedSourceLC = true,
    this.discreet = false,
    this.feedSeenAt,
    this.cardWidth = 272,
    this.keepOldVersion = true,
    this.savedViews = const {},
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    libraryDir: json['library_dir'] as String? ?? '',
    lockdown: json['lockdown'] as bool? ?? true,
    checkUpdates: json['check_updates'] as bool? ?? true,
    checkGameUpdates: json['check_game_updates'] as bool? ?? true,
    fetchMetadata: json['fetch_metadata'] as bool? ?? true,
    allowProviderLogin: json['allow_provider_login'] as bool? ?? true,
    allowDownloadLinks: json['allow_download_links'] as bool? ?? true,
    autoBackup: json['auto_backup'] as bool? ?? true,
    minimizeToTray: json['minimize_to_tray'] as bool? ?? false,
    slideshowInterval: (json['slideshow_interval'] as num?)?.toDouble() ?? 5.0,
    concurrentExtractions: json['concurrent_extractions'] as int? ?? 1,
    deleteAfterExtract: json['delete_after_extract'] as bool? ?? false,
    theme: json['theme'] as String? ?? 'dark',
    accentColor: json['accent_color'] as String? ?? AppColors.defaultAccentHex,
    fontSize: (json['font_size'] as num?)?.toDouble() ?? 13.0,
    sidebarWidth: (json['sidebar_width'] as num?)?.toDouble() ?? AppLayout.sidebarWidth,
    siteCredentials: (json['site_credentials'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String,
          Map<String, String>.from(v as Map? ?? {}))),
    feedEnabled: json['feed_enabled'] as bool? ?? false,
    feedRefreshHours: json['feed_refresh_hours'] as int? ?? 6,
    feedSourceAzc: json['feed_source_azc'] as bool? ?? false,
    feedSourceF95: json['feed_source_f95'] as bool? ?? true,
    feedSourceLC: json['feed_source_lc'] as bool? ?? true,
    discreet: json['discreet'] as bool? ?? false,
    feedSeenAt: json['feed_seen_at'] as String?,
    cardWidth: (json['card_width'] as num?)?.toDouble() ?? 272,
    keepOldVersion: json['keep_old_version'] as bool? ?? true,
    savedViews: (json['saved_views'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))),
  );

  Map<String, dynamic> toJson() => {
    'library_dir': libraryDir,
    'lockdown': lockdown,
    'check_updates': checkUpdates,
    'check_game_updates': checkGameUpdates,
    'fetch_metadata': fetchMetadata,
    'allow_provider_login': allowProviderLogin,
    'allow_download_links': allowDownloadLinks,
    'auto_backup': autoBackup,
    'minimize_to_tray': minimizeToTray,
    'slideshow_interval': slideshowInterval,
    'concurrent_extractions': concurrentExtractions,
    'delete_after_extract': deleteAfterExtract,
    'theme': theme,
    'accent_color': accentColor,
    'font_size': fontSize,
    'sidebar_width': sidebarWidth,
    'site_credentials': siteCredentials,
    'feed_enabled': feedEnabled,
    'feed_refresh_hours': feedRefreshHours,
    'feed_source_azc': feedSourceAzc,
    'feed_source_f95': feedSourceF95,
    'feed_source_lc': feedSourceLC,
    'discreet': discreet,
    'feed_seen_at': feedSeenAt,
    'card_width': cardWidth,
    'keep_old_version': keepOldVersion,
    'saved_views': savedViews,
  };

  AppSettings copyWith({
    String? libraryDir,
    bool? lockdown,
    bool? checkUpdates,
    bool? checkGameUpdates,
    bool? fetchMetadata,
    bool? allowProviderLogin,
    bool? allowDownloadLinks,
    bool? autoBackup,
    bool? minimizeToTray,
    double? slideshowInterval,
    int? concurrentExtractions,
    bool? deleteAfterExtract,
    String? theme,
    String? accentColor,
    double? fontSize,
    double? sidebarWidth,
    Map<String, Map<String, String>>? siteCredentials,
    bool? feedEnabled,
    int? feedRefreshHours,
    bool? feedSourceAzc,
    bool? feedSourceF95,
    bool? feedSourceLC,
    bool? discreet,
    String? feedSeenAt,
    double? cardWidth,
    bool? keepOldVersion,
    Map<String, Map<String, dynamic>>? savedViews,
  }) => AppSettings(
    libraryDir: libraryDir ?? this.libraryDir,
    lockdown: lockdown ?? this.lockdown,
    checkUpdates: checkUpdates ?? this.checkUpdates,
    checkGameUpdates: checkGameUpdates ?? this.checkGameUpdates,
    fetchMetadata: fetchMetadata ?? this.fetchMetadata,
    allowProviderLogin: allowProviderLogin ?? this.allowProviderLogin,
    allowDownloadLinks: allowDownloadLinks ?? this.allowDownloadLinks,
    autoBackup: autoBackup ?? this.autoBackup,
    minimizeToTray: minimizeToTray ?? this.minimizeToTray,
    slideshowInterval: slideshowInterval ?? this.slideshowInterval,
    concurrentExtractions: concurrentExtractions ?? this.concurrentExtractions,
    deleteAfterExtract: deleteAfterExtract ?? this.deleteAfterExtract,
    theme: theme ?? this.theme,
    accentColor: accentColor ?? this.accentColor,
    fontSize: fontSize ?? this.fontSize,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    siteCredentials: siteCredentials ?? this.siteCredentials,
    feedEnabled: feedEnabled ?? this.feedEnabled,
    feedRefreshHours: feedRefreshHours ?? this.feedRefreshHours,
    feedSourceAzc: feedSourceAzc ?? this.feedSourceAzc,
    feedSourceF95: feedSourceF95 ?? this.feedSourceF95,
    feedSourceLC: feedSourceLC ?? this.feedSourceLC,
    discreet: discreet ?? this.discreet,
    feedSeenAt: feedSeenAt ?? this.feedSeenAt,
    cardWidth: cardWidth ?? this.cardWidth,
    keepOldVersion: keepOldVersion ?? this.keepOldVersion,
    savedViews: savedViews ?? this.savedViews,
  );
}

// ── Settings File Path ────────────────────────────────────────────────────────

File _settingsFile() {
  final appdata = Platform.environment['APPDATA'] ?? '';
  return File(p.join(appdata, 'VN Pathfinder', 'settings.json'));
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  void _load() {
    final f = _settingsFile();
    if (!f.existsSync()) return;
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      state = AppSettings.fromJson(raw);
    } catch (_) {}
  }

  Future<void> save() async {
    final f = _settingsFile();
    f.parent.createSync(recursive: true);
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  void update(AppSettings Function(AppSettings) updater) {
    state = updater(state);
    save();
  }

  void setLibraryDir(String path) => update((s) => s.copyWith(libraryDir: path));
  void setLockdown(bool v) => update((s) => s.copyWith(lockdown: v));
  void setCheckUpdates(bool v) => update((s) => s.copyWith(checkUpdates: v));
  void setCheckGameUpdates(bool v) => update((s) => s.copyWith(checkGameUpdates: v));
  void setFetchMetadata(bool v) => update((s) => s.copyWith(fetchMetadata: v));
  void setAllowProviderLogin(bool v) => update((s) => s.copyWith(allowProviderLogin: v));
  void setAllowDownloadLinks(bool v) => update((s) => s.copyWith(allowDownloadLinks: v));
  void setAutoBackup(bool v) => update((s) => s.copyWith(autoBackup: v));
  void setMinimizeToTray(bool v) => update((s) => s.copyWith(minimizeToTray: v));
  void setSlideshowInterval(double v) => update((s) => s.copyWith(slideshowInterval: v));
  void setConcurrentExtractions(int v) => update((s) => s.copyWith(concurrentExtractions: v));
  void setDeleteAfterExtract(bool v) => update((s) => s.copyWith(deleteAfterExtract: v));
  void setTheme(String v) => update((s) => s.copyWith(theme: v));
  void setAccentColor(String v) => update((s) => s.copyWith(accentColor: v));
  void setFontSize(double v) => update((s) => s.copyWith(fontSize: v));
  void setSidebarWidth(double v) => update((s) => s.copyWith(sidebarWidth: v));

  void setFeedEnabled(bool v) => update((s) => s.copyWith(feedEnabled: v));
  void setFeedRefreshHours(int v) => update((s) => s.copyWith(feedRefreshHours: v));
  void setFeedSourceAzc(bool v) => update((s) => s.copyWith(feedSourceAzc: v));
  void setFeedSourceF95(bool v) => update((s) => s.copyWith(feedSourceF95: v));
  void setFeedSourceLC(bool v) => update((s) => s.copyWith(feedSourceLC: v));
  void setDiscreet(bool v) => update((s) => s.copyWith(discreet: v));
  void markFeedSeen() => update((s) => s.copyWith(feedSeenAt: DateTime.now().toIso8601String()));
  void setCardWidth(double v) => update((s) => s.copyWith(cardWidth: v));
  void setKeepOldVersion(bool v) => update((s) => s.copyWith(keepOldVersion: v));
  void saveView(String name, Map<String, dynamic> view) =>
      update((s) => s.copyWith(savedViews: {...s.savedViews, name: view}));
  void deleteView(String name) =>
      update((s) => s.copyWith(savedViews: {...s.savedViews}..remove(name)));

  /// Merge new key-value pairs into the credentials for [site].
  /// E.g. setSiteCredentials('f95zone', {'xf_user': '...', 'xf_session': '...'})
  void setSiteCredentials(String site, Map<String, String> creds) =>
      update((s) => s.copyWith(siteCredentials: {
            ...s.siteCredentials,
            site: {...(s.siteCredentials[site] ?? {}), ...creds},
          }));

  /// Clear all credentials for [site].
  void clearSiteCredentials(String site) =>
      update((s) => s.copyWith(siteCredentials: {
            ...s.siteCredentials,
            site: const {},
          }));
}

// ── Provider ──────────────────────────────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);

// Convenience: lockdown state
final lockdownProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider).lockdown,
);

// Convenience: library dir
final libraryDirProvider = Provider<String>(
  (ref) => ref.watch(settingsProvider).libraryDir,
);

// Reactive ThemeData derived from persisted settings
final appThemeDataProvider = Provider<ThemeData>((ref) {
  final s = ref.watch(settingsProvider);
  final dark = switch (s.theme) {
    'light' => false,
    'system' => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
    _ => true,
  };
  // The default accent is the theme's own, so it stays readable on both.
  final accent = AppColors.isDefaultAccent(s.accentColor) ? null : _hexToColor(s.accentColor);
  AppColors.apply(dark: dark, accent: accent);
  return AppTheme.build(accent: accent, fontSize: s.fontSize, dark: dark);
});

// Reactive ThemeMode derived from persisted settings
final appThemeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(settingsProvider).theme) {
    'light'  => ThemeMode.light,
    'system' => ThemeMode.system,
    _        => ThemeMode.dark,
  };
});

Color? _hexToColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  return Color(int.parse('FF$clean', radix: 16));
}
