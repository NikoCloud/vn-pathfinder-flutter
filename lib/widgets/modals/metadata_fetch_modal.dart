import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme.dart';
import '../../models/game_group.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/metadata_service.dart';
import '../../services/scraping_service.dart';
import '../../services/scanner_service.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

void showMetadataFetchModal(BuildContext context, GameGroup group) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => MetadataFetchModal(group: group),
  );
}

// ── Provider enum ─────────────────────────────────────────────────────────────

enum _Provider { vndb, f95zone, lewdcorner, itchio }

extension _ProviderX on _Provider {
  String get label => switch (this) {
        _Provider.vndb       => 'VNDB',
        _Provider.f95zone    => 'F95Zone',
        _Provider.lewdcorner => 'LewdCorner',
        _Provider.itchio     => 'itch.io',
      };

  // Short label used in mixer pills
  String get shortLabel => switch (this) {
        _Provider.vndb       => 'VNDB',
        _Provider.f95zone    => 'F95',
        _Provider.lewdcorner => 'LC',
        _Provider.itchio     => 'itch',
      };

  // Key in AppSettings.siteCredentials (empty = no auth needed)
  String get credKey => switch (this) {
        _Provider.vndb       => '',
        _Provider.f95zone    => 'f95zone',
        _Provider.lewdcorner => 'lewdcorner',
        _Provider.itchio     => 'itchio',
      };

  // Matches MetadataResult.provider string (used for enrichment check)
  // ignore: unused_element
  String get resultKey => switch (this) {
        _Provider.vndb       => 'vndb',
        _Provider.f95zone    => 'f95zone',
        _Provider.lewdcorner => 'lewdcorner',
        _Provider.itchio     => 'itchio',
      };

  bool get requiresAuth => this != _Provider.vndb;
}

// ── Field keys ────────────────────────────────────────────────────────────────

const _kFields = ['title', 'developer', 'synopsis', 'tags', 'images'];

// ── Root widget ───────────────────────────────────────────────────────────────

class MetadataFetchModal extends ConsumerStatefulWidget {
  final GameGroup group;
  const MetadataFetchModal({super.key, required this.group});

  @override
  ConsumerState<MetadataFetchModal> createState() => _MetadataFetchModalState();
}

class _MetadataFetchModalState extends ConsumerState<MetadataFetchModal> {
  late final TextEditingController _queryCtrl;
  _Provider _activeTab = _Provider.vndb;

  // ── Per-provider parallel search state ────────────────────────────────────
  final Map<_Provider, List<MetadataResult>> _resultsByProvider = {};
  final Map<_Provider, bool> _loadingByProvider = {};
  final Map<_Provider, String?> _errorByProvider = {};

  // ── Per-provider picked result + enrichment state ─────────────────────────
  // One result picked per provider simultaneously — not a single global pick.
  final Map<_Provider, MetadataResult?> _pickedByProvider = {};
  final Map<_Provider, bool> _enrichingByProvider = {};

  // ── Field mixer: which provider supplies each field ───────────────────────
  final Map<String, _Provider?> _fieldSource = {
    for (final f in _kFields) f: null,
  };

  // ── Convenience getters for the active tab ────────────────────────────────
  List<MetadataResult> get _tabResults => _resultsByProvider[_activeTab] ?? [];
  bool get _tabLoading => _loadingByProvider[_activeTab] ?? false;
  String? get _tabError => _errorByProvider[_activeTab];
  bool get _anyLoading => _loadingByProvider.values.any((v) => v);
  bool get _anyPicked => _pickedByProvider.values.any((r) => r != null);

  // ── Apply state ───────────────────────────────────────────────────────────
  bool _applying = false;
  String? _applyError;
  bool _downloadImages = true;
  int _dlDone = 0;
  int _dlTotal = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.group.effectiveTitle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _search() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;

    final settings = ref.read(settingsProvider);
    if (settings.lockdown) {
      setState(() {
        for (final p in _Provider.values) {
          _errorByProvider[p] =
              'Network locked down. Enable it in Settings → Network.';
          _loadingByProvider[p] = false;
        }
      });
      return;
    }

    setState(() {
      for (final p in _Provider.values) {
        _loadingByProvider[p] = true;
        _errorByProvider[p] = null;
        _resultsByProvider[p] = [];
        _pickedByProvider[p] = null;
        _enrichingByProvider[p] = false;
      }
      for (final f in _kFields) {
        _fieldSource[f] = null;
      }
      _applyError = null;
    });

    final scraping = ref.read(scrapingServiceProvider);
    // All four fire in parallel; ScrapingService queues WebView requests internally.
    await Future.wait(_Provider.values.map((p) => _searchOne(p, query, scraping)));
  }

  Future<void> _searchOne(
      _Provider prov, String query, ScrapingService scraping) async {
    try {
      final results = switch (prov) {
        _Provider.vndb       => await MetadataService.searchVndb(query),
        _Provider.f95zone    => await MetadataService.searchF95Zone(query, scraping),
        _Provider.lewdcorner => await MetadataService.searchLewdCorner(query, scraping),
        _Provider.itchio     => await MetadataService.searchItchio(query, scraping),
      };

      if (!mounted) return;
      setState(() {
        _resultsByProvider[prov] = results;
        _loadingByProvider[prov] = false;
        if (results.isEmpty) _errorByProvider[prov] = 'No results found.';
      });

      // Auto-pick first result for every provider, not just the active tab.
      // This pre-populates the field mixer as results arrive.
      if (results.isNotEmpty && _pickedByProvider[prov] == null) {
        await _pickResult(prov, results.first, autoAssign: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingByProvider[prov] = false;
        _errorByProvider[prov] = 'Search failed: $e';
      });
    }
  }

  // ── Pick & enrich ─────────────────────────────────────────────────────────

  Future<void> _pickResult(_Provider prov, MetadataResult r,
      {bool autoAssign = false}) async {
    if (!mounted) return;
    setState(() {
      _pickedByProvider[prov] = r;
      if (autoAssign) _autoAssignFields(prov, r);
    });

    // Enrich F95/LC results — fetches the thread page for full images/synopsis/tags
    if (r.provider == 'f95zone' || r.provider == 'lewdcorner') {
      if (!mounted) return;
      setState(() => _enrichingByProvider[prov] = true);
      final scraping = ref.read(scrapingServiceProvider);
      try {
        final enriched = await MetadataService.fetchThreadDetails(r, scraping);
        if (!mounted) return;
        if (_pickedByProvider[prov] == r) {
          setState(() {
            _pickedByProvider[prov] = enriched;
            _enrichingByProvider[prov] = false;
            if (autoAssign) _autoAssignFields(prov, enriched);
          });
        }
      } catch (_) {
        if (mounted) setState(() => _enrichingByProvider[prov] = false);
      }
    }
  }

  /// Auto-assigns fields to [prov] where no source is set, or the current
  /// source has no data for that field. User manual picks are never overwritten.
  void _autoAssignFields(_Provider prov, MetadataResult r) {
    final hasData = {
      'title':     r.title.isNotEmpty,
      'developer': r.developer.isNotEmpty,
      'synopsis':  r.synopsis.isNotEmpty,
      'tags':      r.tags.isNotEmpty,
      'images':    r.coverUrl.isNotEmpty || r.screenshotUrls.isNotEmpty,
    };

    for (final field in _kFields) {
      if (!hasData[field]!) continue;
      final current = _fieldSource[field];
      if (current == null || !_providerHasDataFor(field, current)) {
        _fieldSource[field] = prov;
      }
    }
  }

  bool _providerHasDataFor(String field, _Provider prov) {
    final r = _pickedByProvider[prov];
    if (r == null) return false;
    return switch (field) {
      'title'     => r.title.isNotEmpty,
      'developer' => r.developer.isNotEmpty,
      'synopsis'  => r.synopsis.isNotEmpty,
      'tags'      => r.tags.isNotEmpty,
      'images'    => r.coverUrl.isNotEmpty || r.screenshotUrls.isNotEmpty,
      _           => false,
    };
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (!_anyPicked) return;
    final v = widget.group.latestVersion;
    if (v == null) {
      setState(() => _applyError = 'No game version found — cannot save metadata.');
      return;
    }

    setState(() { _applying = true; _applyError = null; });

    try {
      final meta = Map<String, dynamic>.from(loadGameMetadata(v.folderPath));

      // Reads the picked result for [field]'s chosen source, applies [write] if data exists.
      void applyField(String field, void Function(MetadataResult r) write) {
        final src = _fieldSource[field];
        if (src == null) return;
        final r = _pickedByProvider[src];
        if (r != null) write(r);
      }

      applyField('title',     (r) { if (r.title.isNotEmpty)     meta['title']        = r.title; });
      applyField('developer', (r) { if (r.developer.isNotEmpty) meta['developer']    = r.developer; });
      applyField('synopsis',  (r) { if (r.synopsis.isNotEmpty)  meta['synopsis']     = r.synopsis; });
      applyField('tags',      (r) { if (r.tags.isNotEmpty)      meta['tags_fetched'] = r.tags; });

      // Release date — use first picked provider that has one
      for (final r in _pickedByProvider.values) {
        if (r?.releaseDate.isNotEmpty == true) {
          meta['release_date'] = r!.releaseDate;
          break;
        }
      }

      // Store source URLs for every picked provider
      for (final entry in _pickedByProvider.entries) {
        final r = entry.value;
        if (r == null || r.sourceUrl.isEmpty) continue;
        switch (entry.key) {
          case _Provider.vndb:       meta['vndb_url'] = r.sourceUrl;
          case _Provider.f95zone:    meta['f95_url']  = r.sourceUrl;
          case _Provider.lewdcorner: meta['lc_url']   = r.sourceUrl;
          case _Provider.itchio:     meta['itch_url'] = r.sourceUrl;
        }
      }

      // Primary source_url = image source provider, or first available
      final imgSrc = _fieldSource['images'];
      final primaryUrl = (imgSrc != null ? _pickedByProvider[imgSrc]?.sourceUrl : null) ??
          _pickedByProvider.values
              .firstWhere((r) => r != null, orElse: () => null)
              ?.sourceUrl;
      if (primaryUrl != null) meta['source_url'] = primaryUrl;

      await saveGameMetadata(v.folderPath, meta);

      // Download images from chosen images source
      final imgResult = imgSrc != null ? _pickedByProvider[imgSrc] : null;
      if (_downloadImages && imgResult != null &&
          (imgResult.coverUrl.isNotEmpty || imgResult.screenshotUrls.isNotEmpty)) {
        setState(() {
          _dlDone = 0;
          _dlTotal = (imgResult.coverUrl.isNotEmpty ? 1 : 0) +
              imgResult.screenshotUrls.length;
        });
        await MetadataService.downloadImages(
          gameFolder: v.folderPath,
          coverUrl: imgResult.coverUrl,
          screenshotUrls: imgResult.screenshotUrls,
          scrapingService: ref.read(scrapingServiceProvider),
          onProgress: (done, total) {
            if (mounted) setState(() { _dlDone = done; _dlTotal = total; });
          },
        );
      }

      await ref.read(libraryProvider.notifier).scan();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() { _applying = false; _applyError = 'Save failed: $e'; });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final locked = settings.lockdown;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1020, maxHeight: 700),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: AppRadius.borderLg,
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadius.borderLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: widget.group.effectiveTitle,
                  onClose: () => Navigator.of(context).pop(),
                ),
                if (locked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.danger.withValues(alpha: 0.12),
                    child: Row(children: [
                      const Icon(Icons.lock_outline, size: 14, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Text(
                        'Network lockdown is active — metadata search is disabled.',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger),
                      ),
                    ]),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left: search + provider tabs + results ──────────
                      SizedBox(
                        width: 270,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Expanded(
                                  child: _SearchField(
                                    controller: _queryCtrl,
                                    onSubmit: locked ? null : _search,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _SearchButton(
                                  onTap: locked ? null : _search,
                                  loading: _anyLoading,
                                ),
                              ]),
                            ),
                            _ProviderTabs(
                              selected: _activeTab,
                              settings: settings,
                              loadingByProvider: _loadingByProvider,
                              pickedByProvider: _pickedByProvider,
                              onSelect: (p) => setState(() => _activeTab = p),
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            Expanded(
                              child: _ResultsList(
                                loading: _tabLoading,
                                results: _tabResults,
                                picked: _pickedByProvider[_activeTab],
                                error: _tabError,
                                onSelect: (r) => _pickResult(_activeTab, r),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                      // ── Right: field mixer ──────────────────────────────
                      Expanded(
                        child: _FieldMixer(
                          pickedByProvider: _pickedByProvider,
                          enrichingByProvider: _enrichingByProvider,
                          fieldSource: _fieldSource,
                          downloadImages: _downloadImages,
                          onSourceChange: (field, prov) =>
                              setState(() => _fieldSource[field] = prov),
                          onToggleDownload: (v) =>
                              setState(() => _downloadImages = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                _Footer(
                  anyPicked: _anyPicked,
                  applying: _applying,
                  dlDone: _dlDone,
                  dlTotal: _dlTotal,
                  applyError: _applyError,
                  onCancel: () => Navigator.of(context).pop(),
                  onApply: (_anyPicked && !_applying && !locked) ? _apply : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _Header({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        const Icon(Icons.tune_outlined, size: 16, color: AppColors.accent),
        const SizedBox(width: 10),
        Text('Fetch Metadata',
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(width: 6),
        Text('— $title',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: AppColors.textSecondary,
          onPressed: onClose,
          splashRadius: 16,
          tooltip: 'Close',
        ),
      ]),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  const _SearchField({required this.controller, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.borderSm,
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        decoration: const InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
        onSubmitted: (_) => onSubmit?.call(),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  const _SearchButton({this.onTap, required this.loading});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.accent : AppColors.bgCard,
          borderRadius: AppRadius.borderSm,
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              )
            : const Icon(Icons.search, size: 16, color: Colors.white),
      ),
    );
  }
}

// ── Provider tabs ─────────────────────────────────────────────────────────────

class _ProviderTabs extends StatelessWidget {
  final _Provider selected;
  final AppSettings settings;
  final Map<_Provider, bool> loadingByProvider;
  final Map<_Provider, MetadataResult?> pickedByProvider;
  final ValueChanged<_Provider> onSelect;

  const _ProviderTabs({
    required this.selected,
    required this.settings,
    required this.loadingByProvider,
    required this.pickedByProvider,
    required this.onSelect,
  });

  bool _connected(_Provider prov) {
    if (!prov.requiresAuth) return true;
    final creds = settings.siteCredentials[prov.credKey] ?? {};
    if (prov == _Provider.itchio) return creds.isNotEmpty;
    return creds['connected'] == 'true' ||
        (creds['xf_session'] ?? '').isNotEmpty ||
        (creds['xf_user'] ?? '').isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: AppColors.bgCard,
      child: Row(
        children: _Provider.values.map((prov) {
          final active = prov == selected;
          final ok = _connected(prov);
          final loading = loadingByProvider[prov] ?? false;
          final picked = pickedByProvider[prov] != null;

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(prov),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? AppColors.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        prov.label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          color: active ? AppColors.accent : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    // Loading spinner or picked dot or lock
                    if (loading)
                      const SizedBox(
                        width: 8, height: 8,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppColors.accent),
                      )
                    else if (picked)
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      )
                    else if (!ok)
                      Icon(Icons.lock_outline,
                          size: 9,
                          color: AppColors.textMuted.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Results list ──────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  final bool loading;
  final List<MetadataResult> results;
  final MetadataResult? picked;
  final String? error;
  final ValueChanged<MetadataResult> onSelect;

  const _ResultsList({
    required this.loading,
    required this.results,
    required this.picked,
    required this.error,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    if (error != null && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error!,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Text('Search to find metadata',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemExtent: 58,
      itemBuilder: (context, index) {
        final r = results[index];
        return _ResultItem(
          result: r,
          selected: r == picked,
          onTap: () => onSelect(r),
        );
      },
    );
  }
}

class _ResultItem extends StatefulWidget {
  final MetadataResult result;
  final bool selected;
  final VoidCallback onTap;
  const _ResultItem({required this.result, required this.selected, required this.onTap});

  @override
  State<_ResultItem> createState() => _ResultItemState();
}

class _ResultItemState extends State<_ResultItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final sel = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: sel
                ? AppColors.bgActive
                : _hovered
                    ? AppColors.bgCard
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: sel ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                r.title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                if (r.developer.isNotEmpty) ...[
                  Text(r.developer,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(width: 6),
                ],
                if (r.releaseDate.isNotEmpty)
                  Text(r.releaseDate,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textMuted)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Field Mixer ───────────────────────────────────────────────────────────────

class _FieldMixer extends StatelessWidget {
  final Map<_Provider, MetadataResult?> pickedByProvider;
  final Map<_Provider, bool> enrichingByProvider;
  final Map<String, _Provider?> fieldSource;
  final bool downloadImages;
  final void Function(String field, _Provider prov) onSourceChange;
  final ValueChanged<bool> onToggleDownload;

  const _FieldMixer({
    required this.pickedByProvider,
    required this.enrichingByProvider,
    required this.fieldSource,
    required this.downloadImages,
    required this.onSourceChange,
    required this.onToggleDownload,
  });

  bool _hasData(String field, MetadataResult r) => switch (field) {
        'title'     => r.title.isNotEmpty,
        'developer' => r.developer.isNotEmpty,
        'synopsis'  => r.synopsis.isNotEmpty,
        'tags'      => r.tags.isNotEmpty,
        'images'    => r.coverUrl.isNotEmpty || r.screenshotUrls.isNotEmpty,
        _           => false,
      };

  @override
  Widget build(BuildContext context) {
    final anyPicked = pickedByProvider.values.any((r) => r != null);

    if (!anyPicked) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_outlined, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('Searching all providers…',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('Field mixer will populate as results arrive',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    final imgSrc = fieldSource['images'];
    final imgResult = imgSrc != null ? pickedByProvider[imgSrc] : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mixer explanation ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.borderSm,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Click a provider pill to change the source for that field.',
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
              ),
            ]),
          ),

          // ── Text field rows ────────────────────────────────────────────────
          _MixerRow(
            field: 'title',
            label: 'TITLE',
            pickedByProvider: pickedByProvider,
            enrichingByProvider: enrichingByProvider,
            fieldSource: fieldSource,
            hasData: _hasData,
            onSourceChange: onSourceChange,
            valueWidget: (r) => Text(
              r.title,
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const _MixerDivider(),

          _MixerRow(
            field: 'developer',
            label: 'DEVELOPER',
            pickedByProvider: pickedByProvider,
            enrichingByProvider: enrichingByProvider,
            fieldSource: fieldSource,
            hasData: _hasData,
            onSourceChange: onSourceChange,
            valueWidget: (r) => Text(
              r.developer,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.accentSilver),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const _MixerDivider(),

          _MixerRow(
            field: 'synopsis',
            label: 'SYNOPSIS',
            pickedByProvider: pickedByProvider,
            enrichingByProvider: enrichingByProvider,
            fieldSource: fieldSource,
            hasData: _hasData,
            onSourceChange: onSourceChange,
            valueWidget: (r) => Text(
              r.synopsis,
              style: GoogleFonts.inter(
                  fontSize: 12, height: 1.5, color: AppColors.textSecondary),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const _MixerDivider(),

          _MixerRow(
            field: 'tags',
            label: 'TAGS',
            pickedByProvider: pickedByProvider,
            enrichingByProvider: enrichingByProvider,
            fieldSource: fieldSource,
            hasData: _hasData,
            onSourceChange: onSourceChange,
            valueWidget: (r) => Wrap(
              spacing: 4,
              runSpacing: 4,
              children: r.tags
                  .take(20)
                  .map((t) => _TagChip(label: t))
                  .toList(),
            ),
          ),

          const _MixerDivider(),

          // ── Images row ─────────────────────────────────────────────────────
          _ImagesRow(
            pickedByProvider: pickedByProvider,
            enrichingByProvider: enrichingByProvider,
            fieldSource: fieldSource,
            imgResult: imgResult,
            imgSrc: imgSrc,
            hasData: _hasData,
            downloadImages: downloadImages,
            onSourceChange: onSourceChange,
            onToggleDownload: onToggleDownload,
          ),

          // ── Source links ───────────────────────────────────────────────────
          const _MixerDivider(),
          _SourceLinks(pickedByProvider: pickedByProvider),
        ],
      ),
    );
  }
}

// ── Mixer Row ─────────────────────────────────────────────────────────────────

class _MixerRow extends StatelessWidget {
  final String field;
  final String label;
  final Map<_Provider, MetadataResult?> pickedByProvider;
  final Map<_Provider, bool> enrichingByProvider;
  final Map<String, _Provider?> fieldSource;
  final bool Function(String field, MetadataResult r) hasData;
  final void Function(String field, _Provider prov) onSourceChange;
  final Widget Function(MetadataResult r) valueWidget;

  const _MixerRow({
    required this.field,
    required this.label,
    required this.pickedByProvider,
    required this.enrichingByProvider,
    required this.fieldSource,
    required this.hasData,
    required this.onSourceChange,
    required this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    final currentSrc = fieldSource[field];
    final currentResult = currentSrc != null ? pickedByProvider[currentSrc] : null;
    final isEnrichingCurrent =
        currentSrc != null && (enrichingByProvider[currentSrc] ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + pills row
          Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ..._Provider.values.map((prov) => _ProviderPill(
                    field: field,
                    prov: prov,
                    pickedByProvider: pickedByProvider,
                    enrichingByProvider: enrichingByProvider,
                    fieldSource: fieldSource,
                    hasData: hasData,
                    onTap: onSourceChange,
                  )),
              if (isEnrichingCurrent) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.accent),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          // Value
          if (currentResult != null && hasData(field, currentResult))
            valueWidget(currentResult)
          else
            Text('—',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ── Images Row ────────────────────────────────────────────────────────────────

class _ImagesRow extends StatelessWidget {
  final Map<_Provider, MetadataResult?> pickedByProvider;
  final Map<_Provider, bool> enrichingByProvider;
  final Map<String, _Provider?> fieldSource;
  final MetadataResult? imgResult;
  final _Provider? imgSrc;
  final bool Function(String field, MetadataResult r) hasData;
  final bool downloadImages;
  final void Function(String field, _Provider prov) onSourceChange;
  final ValueChanged<bool> onToggleDownload;

  const _ImagesRow({
    required this.pickedByProvider,
    required this.enrichingByProvider,
    required this.fieldSource,
    required this.imgResult,
    required this.imgSrc,
    required this.hasData,
    required this.downloadImages,
    required this.onSourceChange,
    required this.onToggleDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isEnriching = imgSrc != null && (enrichingByProvider[imgSrc] ?? false);
    final allUrls = [
      if (imgResult?.coverUrl.isNotEmpty == true) imgResult!.coverUrl,
      ...?imgResult?.screenshotUrls,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 76,
              child: Text(
                'IMAGES',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ..._Provider.values.map((prov) => _ProviderPill(
                  field: 'images',
                  prov: prov,
                  pickedByProvider: pickedByProvider,
                  enrichingByProvider: enrichingByProvider,
                  fieldSource: fieldSource,
                  hasData: hasData,
                  onTap: onSourceChange,
                )),
            if (isEnriching) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.accent),
              ),
            ],
            const Spacer(),
            // Download toggle (inline with images row header)
            GestureDetector(
              onTap: () => onToggleDownload(!downloadImages),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 14, height: 14,
                  child: Checkbox(
                    value: downloadImages,
                    onChanged: (v) => onToggleDownload(v ?? true),
                    activeColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.border, width: 1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 5),
                Text('Download',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          if (allUrls.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allUrls.length,
                separatorBuilder: (ctx, i) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final isCover = i == 0 && imgResult?.coverUrl.isNotEmpty == true;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: AppRadius.borderSm,
                        child: Image.network(
                          allUrls[i],
                          width: isCover ? 56 : 120,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx2, e, st) => Container(
                            width: isCover ? 56 : 120,
                            height: 80,
                            color: AppColors.bgCard,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 14, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      if (isCover)
                        Positioned(
                          bottom: 3, left: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: AppRadius.borderSm,
                            ),
                            child: Text('CVR',
                                style: GoogleFonts.inter(
                                    fontSize: 7,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            )
          else if (isEnriching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppColors.accent)),
                const SizedBox(width: 8),
                Text('Fetching images…',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted)),
              ]),
            )
          else
            Text('—', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ── Provider pill ─────────────────────────────────────────────────────────────

class _ProviderPill extends StatelessWidget {
  final String field;
  final _Provider prov;
  final Map<_Provider, MetadataResult?> pickedByProvider;
  final Map<_Provider, bool> enrichingByProvider;
  final Map<String, _Provider?> fieldSource;
  final bool Function(String field, MetadataResult r) hasData;
  final void Function(String field, _Provider prov) onTap;

  const _ProviderPill({
    required this.field,
    required this.prov,
    required this.pickedByProvider,
    required this.enrichingByProvider,
    required this.fieldSource,
    required this.hasData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final result = pickedByProvider[prov];
    // Don't render pill if provider has no picked result yet
    if (result == null) return const SizedBox.shrink();

    final hasFieldData = hasData(field, result);
    final isSelected = fieldSource[field] == prov;
    final isEnriching = enrichingByProvider[prov] ?? false;
    final tappable = hasFieldData && !isEnriching;

    return GestureDetector(
      onTap: tappable ? () => onTap(field, prov) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent
              : hasFieldData
                  ? AppColors.bgCard
                  : Colors.transparent,
          borderRadius: AppRadius.borderSm,
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : hasFieldData
                    ? AppColors.border
                    : AppColors.border.withValues(alpha: 0.25),
          ),
        ),
        child: isEnriching && isSelected
            ? const SizedBox(
                width: 20, height: 10,
                child: Center(
                  child: SizedBox(
                    width: 8, height: 8,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.2, color: Colors.white),
                  ),
                ),
              )
            : Text(
                prov.shortLabel,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : hasFieldData
                          ? AppColors.textSecondary
                          : AppColors.textMuted.withValues(alpha: 0.35),
                ),
              ),
      ),
    );
  }
}

// ── Source links ──────────────────────────────────────────────────────────────

class _SourceLinks extends StatelessWidget {
  final Map<_Provider, MetadataResult?> pickedByProvider;
  const _SourceLinks({required this.pickedByProvider});

  @override
  Widget build(BuildContext context) {
    final links = <({String label, String url})>[];
    for (final prov in _Provider.values) {
      final r = pickedByProvider[prov];
      if (r != null && r.sourceUrl.isNotEmpty) {
        links.add((label: prov.label, url: r.sourceUrl));
      }
    }
    if (links.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SOURCES',
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: links.map((l) => GestureDetector(
              onTap: () {
                final uri = Uri.tryParse(l.url);
                if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Text(
                l.label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Mixer divider ─────────────────────────────────────────────────────────────

class _MixerDivider extends StatelessWidget {
  const _MixerDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.border);
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: AppRadius.borderSm,
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final bool anyPicked;
  final bool applying;
  final int dlDone;
  final int dlTotal;
  final String? applyError;
  final VoidCallback onCancel;
  final VoidCallback? onApply;

  const _Footer({
    required this.anyPicked,
    required this.applying,
    required this.dlDone,
    required this.dlTotal,
    this.applyError,
    required this.onCancel,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (applyError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                borderRadius: AppRadius.borderSm,
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(applyError!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.danger)),
                ),
              ]),
            ),
          ],
          Row(children: [
            // Image download progress
            if (applying && dlTotal > 0) ...[
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  value: dlDone / dlTotal,
                  color: AppColors.accent,
                  backgroundColor: AppColors.border,
                ),
              ),
              const SizedBox(width: 8),
              Text('$dlDone / $dlTotal images',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
            const Spacer(),
            _FooterBtn(label: 'Cancel', onTap: onCancel),
            const SizedBox(width: 8),
            _FooterBtn(
              label: applying ? 'Applying…' : 'Apply Mix',
              primary: true,
              onTap: onApply,
            ),
          ]),
        ],
      ),
    );
  }
}

class _FooterBtn extends StatefulWidget {
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const _FooterBtn({required this.label, this.primary = false, this.onTap});

  @override
  State<_FooterBtn> createState() => _FooterBtnState();
}

class _FooterBtnState extends State<_FooterBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: widget.primary
                ? (enabled
                    ? (_hovered ? AppColors.accentLight : AppColors.accent)
                    : AppColors.bgCard)
                : (_hovered ? AppColors.bgActive : AppColors.bgSecondary),
            border: Border.all(
              color: widget.primary && enabled
                  ? AppColors.accent
                  : AppColors.border,
            ),
            borderRadius: AppRadius.borderMd,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: widget.primary && enabled
                  ? Colors.white
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
