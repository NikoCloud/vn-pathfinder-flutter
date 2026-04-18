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

  /// Key stored in AppSettings.siteCredentials (empty = no auth needed).
  String get credKey => switch (this) {
        _Provider.vndb       => '',
        _Provider.f95zone    => 'f95zone',
        _Provider.lewdcorner => 'lewdcorner',
        _Provider.itchio     => 'itchio',
      };

  /// Matches MetadataResult.provider string returned by MetadataService.
  String get resultKey => switch (this) {
        _Provider.vndb       => 'vndb',
        _Provider.f95zone    => 'f95zone',
        _Provider.lewdcorner => 'lewdcorner',
        _Provider.itchio     => 'itchio',
      };

  bool get requiresAuth => this != _Provider.vndb;
}

// ── Root widget ───────────────────────────────────────────────────────────────

class MetadataFetchModal extends ConsumerStatefulWidget {
  final GameGroup group;
  const MetadataFetchModal({super.key, required this.group});

  @override
  ConsumerState<MetadataFetchModal> createState() => _MetadataFetchModalState();
}

class _MetadataFetchModalState extends ConsumerState<MetadataFetchModal> {
  late final TextEditingController _queryCtrl;
  _Provider _provider = _Provider.vndb;

  // ── Per-provider result cache ─────────────────────────────────────────────
  // All four providers search in parallel. Results/loading/errors are stored
  // per-provider so switching tabs is instant — no extra network round-trip.
  final Map<_Provider, List<MetadataResult>> _resultsByProvider = {};
  final Map<_Provider, bool> _loadingByProvider = {};
  final Map<_Provider, String?> _errorByProvider = {};

  // Convenience getters for the active tab
  List<MetadataResult> get _results => _resultsByProvider[_provider] ?? [];
  bool get _loading => _loadingByProvider[_provider] ?? false;
  String? get _error => _errorByProvider[_provider];

  MetadataResult? _selected;
  bool _enriching = false; // fetching thread details for F95/LC selection
  String? _applyError;    // apply-specific error (shown in footer)
  bool _applying = false;
  bool _downloadImages = true;
  int _dlDone = 0;
  int _dlTotal = 0;

  // Per-field apply toggles (shown as checkboxes in the preview panel)
  bool _applyTitle = true;
  bool _applyDeveloper = true;
  bool _applySynopsis = true;
  bool _applyTags = true;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.group.effectiveTitle);
    // Auto-search all providers on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// Fires all four providers simultaneously. Each updates its own slice of
  /// state as it completes, so the UI reflects results as they arrive.
  Future<void> _search() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;

    final settings = ref.read(settingsProvider);
    if (settings.lockdown) {
      setState(() {
        for (final p in _Provider.values) {
          _errorByProvider[p] =
              'Network is locked down. Enable it in Settings → Network.';
          _loadingByProvider[p] = false;
        }
      });
      return;
    }

    // Mark all providers as loading and clear previous results.
    setState(() {
      for (final p in _Provider.values) {
        _loadingByProvider[p] = true;
        _errorByProvider[p] = null;
        _resultsByProvider[p] = [];
      }
      _selected = null;
      _enriching = false;
      _applyError = null;
    });

    final scrapingService = ref.read(scrapingServiceProvider);

    // Launch all four searches in parallel. ScrapingService queues WebView
    // requests internally, so F95/LC/itch will process sequentially through
    // the hidden browser while VNDB (plain HTTP) resolves immediately.
    await Future.wait(_Provider.values.map((prov) => _searchOne(prov, query, scrapingService)));
  }

  Future<void> _searchOne(
      _Provider prov, String query, ScrapingService scrapingService) async {
    try {
      final results = switch (prov) {
        _Provider.vndb       => await MetadataService.searchVndb(query),
        _Provider.f95zone    => await MetadataService.searchF95Zone(query, scrapingService),
        _Provider.lewdcorner => await MetadataService.searchLewdCorner(query, scrapingService),
        _Provider.itchio     => await MetadataService.searchItchio(query, scrapingService),
      };

      if (!mounted) return;
      setState(() {
        _resultsByProvider[prov] = results;
        _loadingByProvider[prov] = false;
        if (results.isEmpty) _errorByProvider[prov] = 'No results found.';
      });

      // Auto-select the first result of the active tab when it arrives.
      if (mounted && prov == _provider && results.isNotEmpty && _selected == null) {
        _selectResult(results.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingByProvider[prov] = false;
        _errorByProvider[prov] = 'Search failed: $e';
      });
    }
  }

  Future<void> _selectResult(MetadataResult r) async {
    setState(() { _selected = r; _enriching = false; _applyError = null; });

    // For F95Zone / LewdCorner results the initial search only gives title+URL.
    // Fetch the thread page to pull cover image and screenshots via background browser.
    if (r.provider == 'f95zone' || r.provider == 'lewdcorner') {
      setState(() => _enriching = true);
      final scrapingService = ref.read(scrapingServiceProvider);
      try {
        final enriched = await MetadataService.fetchThreadDetails(r, scrapingService);
        if (mounted && _selected == r) {
          setState(() { _selected = enriched; _enriching = false; });
        }
      } catch (_) {
        if (mounted) setState(() => _enriching = false);
      }
    }
  }

  Future<void> _apply() async {
    if (_selected == null) return;
    final v = widget.group.latestVersion;
    if (v == null) {
      setState(() => _applyError = 'No game version found — cannot save metadata.');
      return;
    }

    setState(() { _applying = true; _applyError = null; });

    try {
      // Load existing metadata, then selectively apply chosen fields.
      final existing = loadGameMetadata(v.folderPath);
      final meta = Map<String, dynamic>.from(existing);

      if (_applyTitle && _selected!.title.isNotEmpty) {
        meta['title'] = _selected!.title;
      }
      if (_applyDeveloper && _selected!.developer.isNotEmpty) {
        meta['developer'] = _selected!.developer;
      }
      if (_applySynopsis && _selected!.synopsis.isNotEmpty) {
        meta['synopsis'] = _selected!.synopsis;
      }
      if (_applyTags && _selected!.tags.isNotEmpty) {
        meta['tags_fetched'] = _selected!.tags;
      }
      if (_selected!.releaseDate.isNotEmpty) {
        meta['release_date'] = _selected!.releaseDate;
      }

      // Always update the provider URL so source links work.
      meta['source_url'] = _selected!.sourceUrl;
      switch (_selected!.provider) {
        case 'vndb':       meta['vndb_url']  = _selected!.sourceUrl;
        case 'f95zone':    meta['f95_url']   = _selected!.sourceUrl;
        case 'lewdcorner': meta['lc_url']    = _selected!.sourceUrl;
        case 'itchio':     meta['itch_url']  = _selected!.sourceUrl;
      }

      await saveGameMetadata(v.folderPath, meta);

      // Download images if requested and available.
      if (_downloadImages &&
          (_selected!.coverUrl.isNotEmpty || _selected!.screenshotUrls.isNotEmpty)) {
        setState(() {
          _dlDone = 0;
          _dlTotal = (_selected!.coverUrl.isNotEmpty ? 1 : 0) +
              _selected!.screenshotUrls.length;
        });
        final scrapingService = ref.read(scrapingServiceProvider);
        await MetadataService.downloadImages(
          gameFolder: v.folderPath,
          coverUrl: _selected!.coverUrl,
          screenshotUrls: _selected!.screenshotUrls,
          scrapingService: scrapingService,
          onProgress: (done, total) {
            if (mounted) setState(() { _dlDone = done; _dlTotal = total; });
          },
        );
      }

      // Re-scan library to pick up the saved metadata.
      await ref.read(libraryProvider.notifier).scan();

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _applyError = 'Save failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final locked = settings.lockdown;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
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
                // Lockdown banner
                if (locked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: AppColors.danger.withValues(alpha: 0.12),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 14, color: AppColors.danger),
                        const SizedBox(width: 8),
                        Text(
                          'Network lockdown is active — metadata search is disabled.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left: search + results ──────────────────────────
                      SizedBox(
                        width: 300,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Search bar
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _SearchField(
                                      controller: _queryCtrl,
                                      onSubmit: locked ? null : _search,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _SearchButton(
                                    onTap: locked ? null : _search,
                                    // Spinner while any provider is still searching
                                    loading: _loadingByProvider.values.any((v) => v),
                                  ),
                                ],
                              ),
                            ),
                            // Provider tabs
                            _ProviderTabs(
                              selected: _provider,
                              settings: settings,
                              onSelect: (p) {
                                if (_provider == p) return;
                                setState(() {
                                  _provider = p;
                                  // Clear selected if it belongs to a different provider
                                  if (_selected != null &&
                                      _selected!.provider != p.resultKey) {
                                    _selected = null;
                                    _enriching = false;
                                  }
                                });
                                // Auto-select first cached result for this tab
                                final cached = _resultsByProvider[p] ?? [];
                                if (cached.isNotEmpty && _selected == null) {
                                  _selectResult(cached.first);
                                }
                              },
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            // Results list
                            Expanded(
                              child: _ResultsList(
                                loading: _loading,
                                results: _results,
                                selected: _selected,
                                error: _error,
                                onSelect: _selectResult,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.border),
                      // ── Right: preview ──────────────────────────────────
                      Expanded(
                        child: _ResultPreview(
                          result: _selected,
                          enriching: _enriching,
                          applyTitle: _applyTitle,
                          applyDeveloper: _applyDeveloper,
                          applySynopsis: _applySynopsis,
                          applyTags: _applyTags,
                          onToggleTitle: (v) => setState(() => _applyTitle = v),
                          onToggleDeveloper: (v) => setState(() => _applyDeveloper = v),
                          onToggleSynopsis: (v) => setState(() => _applySynopsis = v),
                          onToggleTags: (v) => setState(() => _applyTags = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                // Footer
                _Footer(
                  selected: _selected,
                  applying: _applying,
                  dlDone: _dlDone,
                  dlTotal: _dlTotal,
                  downloadImages: _downloadImages,
                  applyError: _applyError,
                  onToggleDownload: (v) =>
                      setState(() => _downloadImages = v),
                  onCancel: () => Navigator.of(context).pop(),
                  onApply: (_selected != null && !_applying && !locked)
                      ? _apply
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

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
      child: Row(
        children: [
          const Icon(Icons.download_outlined,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 10),
          Text(
            'Fetch Metadata',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '— $title',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textSecondary,
            onPressed: onClose,
            splashRadius: 16,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

// ── Search field ───────────────────────────────────────────────────────────────

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

// ── Provider tabs ──────────────────────────────────────────────────────────────

class _ProviderTabs extends StatelessWidget {
  final _Provider selected;
  final AppSettings settings;
  final ValueChanged<_Provider> onSelect;

  const _ProviderTabs({
    required this.selected,
    required this.settings,
    required this.onSelect,
  });

  bool _connected(_Provider prov) {
    if (!prov.requiresAuth) return true;
    final creds = settings.siteCredentials[prov.credKey] ?? {};
    if (prov == _Provider.itchio) return creds.isNotEmpty;
    // Accept the 'connected' marker stored by WebView login, or legacy cookie keys
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
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: active
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                     ),
                    ),
                    if (!ok) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.lock_outline,
                          size: 9,
                          color: AppColors.textMuted.withValues(alpha: 0.7)),
                    ],
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

// ── Results list ───────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  final bool loading;
  final List<MetadataResult> results;
  final MetadataResult? selected;
  final String? error;
  final ValueChanged<MetadataResult> onSelect;

  const _ResultsList({
    required this.loading,
    required this.results,
    required this.selected,
    required this.error,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      );
    }

    if (error != null && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          error!,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Text(
          'Search to find metadata',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemExtent: 58,
      itemBuilder: (context, index) {
        final r = results[index];
        final isSelected = r == selected;
        return _ResultItem(
          result: r,
          selected: isSelected,
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
  const _ResultItem(
      {required this.result, required this.selected, required this.onTap});

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
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (r.developer.isNotEmpty) ...[
                    Text(
                      r.developer,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (r.releaseDate.isNotEmpty)
                    Text(
                      r.releaseDate,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Result preview ─────────────────────────────────────────────────────────────

class _ResultPreview extends StatelessWidget {
  final MetadataResult? result;
  final bool enriching;
  final bool applyTitle;
  final bool applyDeveloper;
  final bool applySynopsis;
  final bool applyTags;
  final ValueChanged<bool> onToggleTitle;
  final ValueChanged<bool> onToggleDeveloper;
  final ValueChanged<bool> onToggleSynopsis;
  final ValueChanged<bool> onToggleTags;

  const _ResultPreview({
    this.result,
    this.enriching = false,
    required this.applyTitle,
    required this.applyDeveloper,
    required this.applySynopsis,
    required this.applyTags,
    required this.onToggleTitle,
    required this.onToggleDeveloper,
    required this.onToggleSynopsis,
    required this.onToggleTags,
  });

  Widget _fieldHeader(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? true),
            activeColor: AppColors.accent,
            side: const BorderSide(color: AppColors.border, width: 1),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Select a result to preview',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover / enriching indicator
          if (enriching && r.coverUrl.isEmpty)
            Container(
              height: 80,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  ),
                  const SizedBox(width: 10),
                  Text('Fetching details…',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            )
          else if (r.coverUrl.isNotEmpty)
            ClipRRect(
              borderRadius: AppRadius.borderMd,
              child: Image.network(
                r.coverUrl,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 14),

          // ── TITLE ──────────────────────────────────────────────────────────
          _fieldHeader('TITLE', applyTitle, onToggleTitle),
          const SizedBox(height: 4),
          Opacity(
            opacity: applyTitle ? 1.0 : 0.35,
            child: Text(
              r.title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // ── DEVELOPER ──────────────────────────────────────────────────────
          if (r.developer.isNotEmpty) ...[
            const SizedBox(height: 12),
            _fieldHeader('DEVELOPER', applyDeveloper, onToggleDeveloper),
            const SizedBox(height: 4),
            Opacity(
              opacity: applyDeveloper ? 1.0 : 0.35,
              child: Text(
                r.developer,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.accentSilver),
              ),
            ),
          ],

          // Release date (always applied if present, no toggle needed)
          if (r.releaseDate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Released: ${r.releaseDate}',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
            ),
          ],

          // Source link (always shown)
          const SizedBox(height: 8),
          _SourceLink(url: r.sourceUrl),

          // ── SYNOPSIS ───────────────────────────────────────────────────────
          if (r.synopsis.isNotEmpty) ...[
            const SizedBox(height: 16),
            _fieldHeader('SYNOPSIS', applySynopsis, onToggleSynopsis),
            const SizedBox(height: 6),
            Opacity(
              opacity: applySynopsis ? 1.0 : 0.35,
              child: Text(
                r.synopsis,
                style: GoogleFonts.inter(fontSize: 12, height: 1.6, color: AppColors.textSecondary),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // ── TAGS ───────────────────────────────────────────────────────────
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _fieldHeader('TAGS (${r.tags.length})', applyTags, onToggleTags),
            const SizedBox(height: 6),
            Opacity(
              opacity: applyTags ? 1.0 : 0.35,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: r.tags.take(20).map((t) => _TagChip(label: t)).toList(),
              ),
            ),
          ],

          // ── SCREENSHOTS (images toggle is in footer) ────────────────────
          if (r.screenshotUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionLabel('SCREENSHOTS (${r.screenshotUrls.length}) — toggle in footer'),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: r.screenshotUrls.length,
                separatorBuilder: (sCtx, si) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: AppRadius.borderSm,
                  child: Image.network(
                    r.screenshotUrls[i],
                    width: 128,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx2, err, st) => Container(
                      width: 128, height: 72, color: AppColors.bgCard),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceLink extends StatelessWidget {
  final String url;
  const _SourceLink({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final uri = Uri.tryParse(url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Text(
        url,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: AppColors.accent,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.accent,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: AppRadius.borderSm,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final MetadataResult? selected;
  final bool applying;
  final int dlDone;
  final int dlTotal;
  final bool downloadImages;
  final String? applyError;
  final ValueChanged<bool> onToggleDownload;
  final VoidCallback onCancel;
  final VoidCallback? onApply;

  const _Footer({
    required this.selected,
    required this.applying,
    required this.dlDone,
    required this.dlTotal,
    required this.downloadImages,
    this.applyError,
    required this.onToggleDownload,
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
          // Apply error banner — shown prominently when save fails
          if (applyError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                borderRadius: AppRadius.borderSm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 13, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      applyError!,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
        children: [
          // Download images toggle
          if (selected != null &&
              (selected!.coverUrl.isNotEmpty ||
                  selected!.screenshotUrls.isNotEmpty)) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: downloadImages,
                onChanged: (v) => onToggleDownload(v ?? true),
                activeColor: AppColors.accent,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Download images',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],

          // Download progress
          if (applying && dlTotal > 0) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: dlDone / dlTotal,
                color: AppColors.accent,
                backgroundColor: AppColors.border,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$dlDone / $dlTotal',
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textMuted),
            ),
          ],

          const Spacer(),
          // Cancel
          _FooterBtn(label: 'Cancel', onTap: onCancel),
          const SizedBox(width: 8),
          // Apply
          _FooterBtn(
            label: applying ? 'Applying…' : 'Apply',
            primary: true,
            onTap: onApply,
          ),
        ],
          ),
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
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
