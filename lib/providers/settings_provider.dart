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
  final bool fetchMetadata;
  final bool allowProviderLogin;
  final bool allowDownloadLinks;
  final bool autoBackup;
  final double slideshowInterval; // seconds
  final int concurrentExtractions;
  final bool deleteAfterExtract;
  final String theme;       // 'dark' | 'light' | 'system'
  final String accentColor; // hex string e.g. '#4a9e6e'
  final double fontSize;

  // Persisted site cookies (separate file, but held here for convenience)
  final Map<String, Map<String, String>> siteCredentials;

  // ── Feed settings ─────────────────────────────────────────────────────────
  final bool feedEnabled;
  final int feedRefreshHours;    // 6 | 12 | 0 = manual only
  final bool feedSourceF95;      // poll F95Zone forum RSS
  final bool feedSourceLC;       // poll LewdCorner forum RSS
  final bool feedSourceAzc;      // poll Azkosel's Corner forum RSS (both game categories)
  final String discordBotToken;  // Bot token for Discord REST API
  /// List of Discord channel entries.
  /// Format per entry: "channelId:ServerName:#channelName"
  /// e.g. "123456789:Patreon Devs:#announcements"
  final List<String> discordChannelIds;

  const AppSettings({
    this.libraryDir = '',
    this.lockdown = true,
    this.checkUpdates = false,
    this.fetchMetadata = false,
    this.allowProviderLogin = false,
    this.allowDownloadLinks = false,
    this.autoBackup = true,
    this.slideshowInterval = 5.0,
    this.concurrentExtractions = 1,
    this.deleteAfterExtract = false,
    this.theme = 'dark',
    this.accentColor = '#4a9e6e',
    this.fontSize = 13.0,
    this.siteCredentials = const {},
    this.feedEnabled = false,
    this.feedRefreshHours = 12,
    this.feedSourceAzc = false,
    this.feedSourceF95 = true,
    this.feedSourceLC = true,
    this.discordBotToken = '',
    this.discordChannelIds = const [],
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    libraryDir: json['library_dir'] as String? ?? '',
    lockdown: json['lockdown'] as bool? ?? true,
    checkUpdates: json['check_updates'] as bool? ?? true,
    fetchMetadata: json['fetch_metadata'] as bool? ?? true,
    allowProviderLogin: json['allow_provider_login'] as bool? ?? true,
    allowDownloadLinks: json['allow_download_links'] as bool? ?? true,
    autoBackup: json['auto_backup'] as bool? ?? true,
    slideshowInterval: (json['slideshow_interval'] as num?)?.toDouble() ?? 5.0,
    concurrentExtractions: json['concurrent_extractions'] as int? ?? 1,
    deleteAfterExtract: json['delete_after_extract'] as bool? ?? false,
    theme: json['theme'] as String? ?? 'dark',
    accentColor: json['accent_color'] as String? ?? '#4a9e6e',
    fontSize: (json['font_size'] as num?)?.toDouble() ?? 13.0,
    siteCredentials: (json['site_credentials'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String,
          Map<String, String>.from(v as Map? ?? {}))),
    feedEnabled: json['feed_enabled'] as bool? ?? false,
    feedRefreshHours: json['feed_refresh_hours'] as int? ?? 12,
    feedSourceAzc: json['feed_source_azc'] as bool? ?? false,
    feedSourceF95: json['feed_source_f95'] as bool? ?? true,
    feedSourceLC: json['feed_source_lc'] as bool? ?? true,
    discordBotToken: json['discord_bot_token'] as String? ?? '',
    discordChannelIds: (json['discord_channel_ids'] as List?)
        ?.map((e) => e.toString()).toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'library_dir': libraryDir,
    'lockdown': lockdown,
    'check_updates': checkUpdates,
    'fetch_metadata': fetchMetadata,
    'allow_provider_login': allowProviderLogin,
    'allow_download_links': allowDownloadLinks,
    'auto_backup': autoBackup,
    'slideshow_interval': slideshowInterval,
    'concurrent_extractions': concurrentExtractions,
    'delete_after_extract': deleteAfterExtract,
    'theme': theme,
    'accent_color': accentColor,
    'font_size': fontSize,
    'site_credentials': siteCredentials,
    'feed_enabled': feedEnabled,
    'feed_refresh_hours': feedRefreshHours,
    'feed_source_azc': feedSourceAzc,
    'feed_source_f95': feedSourceF95,
    'feed_source_lc': feedSourceLC,
    'discord_bot_token': discordBotToken,
    'discord_channel_ids': discordChannelIds,
  };

  AppSettings copyWith({
    String? libraryDir,
    bool? lockdown,
    bool? checkUpdates,
    bool? fetchMetadata,
    bool? allowProviderLogin,
    bool? allowDownloadLinks,
    bool? autoBackup,
    double? slideshowInterval,
    int? concurrentExtractions,
    bool? deleteAfterExtract,
    String? theme,
    String? accentColor,
    double? fontSize,
    Map<String, Map<String, String>>? siteCredentials,
    bool? feedEnabled,
    int? feedRefreshHours,
    bool? feedSourceAzc,
    bool? feedSourceF95,
    bool? feedSourceLC,
    String? discordBotToken,
    List<String>? discordChannelIds,
  }) => AppSettings(
    libraryDir: libraryDir ?? this.libraryDir,
    lockdown: lockdown ?? this.lockdown,
    checkUpdates: checkUpdates ?? this.checkUpdates,
    fetchMetadata: fetchMetadata ?? this.fetchMetadata,
    allowProviderLogin: allowProviderLogin ?? this.allowProviderLogin,
    allowDownloadLinks: allowDownloadLinks ?? this.allowDownloadLinks,
    autoBackup: autoBackup ?? this.autoBackup,
    slideshowInterval: slideshowInterval ?? this.slideshowInterval,
    concurrentExtractions: concurrentExtractions ?? this.concurrentExtractions,
    deleteAfterExtract: deleteAfterExtract ?? this.deleteAfterExtract,
    theme: theme ?? this.theme,
    accentColor: accentColor ?? this.accentColor,
    fontSize: fontSize ?? this.fontSize,
    siteCredentials: siteCredentials ?? this.siteCredentials,
    feedEnabled: feedEnabled ?? this.feedEnabled,
    feedRefreshHours: feedRefreshHours ?? this.feedRefreshHours,
    feedSourceAzc: feedSourceAzc ?? this.feedSourceAzc,
    feedSourceF95: feedSourceF95 ?? this.feedSourceF95,
    feedSourceLC: feedSourceLC ?? this.feedSourceLC,
    discordBotToken: discordBotToken ?? this.discordBotToken,
    discordChannelIds: discordChannelIds ?? this.discordChannelIds,
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
  void setFetchMetadata(bool v) => update((s) => s.copyWith(fetchMetadata: v));
  void setAllowProviderLogin(bool v) => update((s) => s.copyWith(allowProviderLogin: v));
  void setAllowDownloadLinks(bool v) => update((s) => s.copyWith(allowDownloadLinks: v));
  void setAutoBackup(bool v) => update((s) => s.copyWith(autoBackup: v));
  void setSlideshowInterval(double v) => update((s) => s.copyWith(slideshowInterval: v));
  void setConcurrentExtractions(int v) => update((s) => s.copyWith(concurrentExtractions: v));
  void setDeleteAfterExtract(bool v) => update((s) => s.copyWith(deleteAfterExtract: v));
  void setTheme(String v) => update((s) => s.copyWith(theme: v));
  void setAccentColor(String v) => update((s) => s.copyWith(accentColor: v));
  void setFontSize(double v) => update((s) => s.copyWith(fontSize: v));

  void setFeedEnabled(bool v) => update((s) => s.copyWith(feedEnabled: v));
  void setFeedRefreshHours(int v) => update((s) => s.copyWith(feedRefreshHours: v));
  void setFeedSourceAzc(bool v) => update((s) => s.copyWith(feedSourceAzc: v));
  void setFeedSourceF95(bool v) => update((s) => s.copyWith(feedSourceF95: v));
  void setFeedSourceLC(bool v) => update((s) => s.copyWith(feedSourceLC: v));
  void setDiscordBotToken(String v) => update((s) => s.copyWith(discordBotToken: v));
  void setDiscordChannelIds(List<String> v) => update((s) => s.copyWith(discordChannelIds: v));

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
  return AppTheme.build(
    accent: _hexToColor(s.accentColor),
    fontSize: s.fontSize,
    dark: s.theme != 'light',
  );
});

// Reactive ThemeMode derived from persisted settings
final appThemeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(settingsProvider).theme) {
    'light'  => ThemeMode.light,
    'system' => ThemeMode.system,
    _        => ThemeMode.dark,
  };
});

Color _hexToColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return AppColors.accent;
  return Color(int.parse('FF$clean', radix: 16));
}
