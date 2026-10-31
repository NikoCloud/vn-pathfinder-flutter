import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';
import '../services/archive_cards.dart';
import '../services/metadata_service.dart';
import '../services/scraping_service.dart';
import '../services/site_browser.dart';
import 'feed_images_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

enum JobStage { downloading, waiting, extracting, ready, saved, failed }

/// A game on its way into the library.
class DownloadJob {
  final int id;
  final String title;
  final String cover;
  final String version;
  final String? baseKey;

  /// Folder to delete once this version is in, when the user asked for that.
  final String? replaceFolder;
  final JobStage stage;
  final int received;
  final int total;
  final String path;
  final double extractProgress;
  final String message;

  /// How many times the browser has tried. It retries a dropped download by
  /// itself, from where it stopped if the host allows that, or else from zero.
  final int tries;

  const DownloadJob({
    required this.id,
    required this.title,
    this.cover = '',
    this.version = '',
    this.baseKey,
    this.replaceFolder,
    this.stage = JobStage.downloading,
    this.received = 0,
    this.total = -1,
    this.path = '',
    this.extractProgress = 0,
    this.message = '',
    this.tries = 1,
  });

  /// 0 to 1, or null while the size isn't known.
  double? get progress => stage == JobStage.extracting
      ? extractProgress
      : total > 0
          ? (received / total).clamp(0.0, 1.0)
          : null;

  bool get active => stage == JobStage.downloading || stage == JobStage.waiting || stage == JobStage.extracting;

  DownloadJob copyWith({
    JobStage? stage,
    int? received,
    int? total,
    String? path,
    double? extractProgress,
    String? message,
    String? baseKey,
    int? tries,
  }) =>
      DownloadJob(
        id: id,
        title: title,
        cover: cover,
        version: version,
        baseKey: baseKey ?? this.baseKey,
        replaceFolder: replaceFolder,
        stage: stage ?? this.stage,
        received: received ?? this.received,
        total: total ?? this.total,
        path: path ?? this.path,
        extractProgress: extractProgress ?? this.extractProgress,
        message: message ?? this.message,
        tries: tries ?? this.tries,
      );
}

/// Where an extraction stands, by archive path. Written by the Archive tab,
/// which owns the extraction queue.
/// Why a download stopped, from WebView2's COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON.
/// The number stays on the end, so a report says exactly what happened.
String downloadStopMessage(int reason, {int tries = 1}) {
  final why = switch (reason) {
    2 => "the library folder can't be written to",
    3 => 'the disk is full',
    1 || 4 || 5 || 6 || 7 || 8 || 9 || 10 || 11 => "the file couldn't be saved",
    12 || 15 || 16 => 'the connection failed',
    13 => 'the connection timed out',
    14 => 'your connection dropped',
    20 || 22 => 'the host refused it',
    24 => 'the host cut it off',
    17 || 18 || 19 || 21 || 23 || 25 => 'the host stopped sending',
    26 => 'cancelled',
    27 => 'the app closed',
    29 => 'the browser crashed',
    _ => '',
  };
  final after = tries > 1 ? ', after $tries tries' : '';
  return why.isEmpty ? 'Download stopped ($reason)$after' : 'Download stopped: $why ($reason)$after';
}

typedef ExtractionStatus = ({bool running, bool queued, bool done, bool failed, double progress, String? error});

final extractionStatusProvider = StateProvider<Map<String, ExtractionStatus>>((ref) => const {});

/// Bumped when a saved card changes, so the Archive tab reads them again.
final archiveCardsEpochProvider = StateProvider<int>((ref) => 0);

/// Every saved card in the library, linked or not.
final archiveCardsProvider = Provider<List<ArchiveCard>>((ref) {
  ref.watch(archiveCardsEpochProvider);
  ref.watch(libraryGroupsProvider);
  final library = ref.watch(libraryDirProvider);
  return library.isEmpty ? const [] : ArchiveCards.all(library);
});

/// Archives the Archive tab should unpack as soon as a scan has found them.
final extractRequestsProvider = StateProvider<List<String>>((ref) => const []);

final siteBrowserProvider = ChangeNotifierProvider<SiteBrowser>((ref) => SiteBrowser());

/// Files still arriving, as canonical paths. They carry their final name from
/// the start, so nothing should treat one as a finished archive.
final downloadingPathsProvider = Provider<Set<String>>((ref) {
  final paths = ref.watch(downloadsProvider.select((jobs) =>
      jobs.where((j) => j.stage == JobStage.downloading).map((j) => p.canonicalize(j.path)).join('\n')));
  return paths.isEmpty ? const {} : paths.split('\n').toSet();
});

/// What the next download in the browser is for: set when the Get sheet opens
/// a link, read when a download starts.
class DownloadIntent {
  final String title;
  final String cover;
  final String version;
  final String? baseKey;
  final String? replaceFolder;

  /// What to save beside the file. Null for anything that isn't the game
  /// itself, like a walkthrough or a mod from the same thread.
  final ArchiveCardDraft? card;
  const DownloadIntent({
    required this.title,
    this.cover = '',
    this.version = '',
    this.baseKey,
    this.replaceFolder,
    this.card,
  });
}

class DownloadsNotifier extends StateNotifier<List<DownloadJob>> {
  final Ref _ref;
  DownloadIntent? intent;
  StreamSubscription? _sub;

  /// Cards saved for downloads in progress, by download.
  final _cards = <int, ArchiveCard>{};

  DownloadsNotifier(this._ref) : super(const []) {
    _sub = _ref.read(siteBrowserProvider).downloads.listen(_onDownload);
    _ref.listen(extractionStatusProvider, (_, next) => _onExtraction(next));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _update(int id, DownloadJob Function(DownloadJob) change) {
    state = [for (final j in state) j.id == id ? change(j) : j];
  }

  void _onDownload(WebviewDownload d) {
    switch (d.state) {
      case WebviewDownloadState.started:
        final i = intent;
        state = [
          ...state,
          DownloadJob(
            id: d.id,
            title: i?.title ?? p.basename(d.path),
            cover: i?.cover ?? '',
            version: i?.version ?? '',
            baseKey: i?.baseKey,
            replaceFolder: i?.replaceFolder,
            total: d.total,
            path: d.path,
          ),
        ];
        final draft = i?.card;
        if (draft != null) _saveCard(d, draft);
      case WebviewDownloadState.progress:
        _update(d.id, (j) => j.copyWith(received: d.received, total: d.total));
      case WebviewDownloadState.restarted:
        _update(d.id, (j) => j.copyWith(tries: j.tries + 1, received: d.received));
      case WebviewDownloadState.interrupted:
        _update(d.id, (j) => j.copyWith(stage: JobStage.failed, message: downloadStopMessage(d.reason, tries: j.tries)));
        _cards.remove(d.id)?.delete();
        _ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
        _discardPartial(d.path);
        _releaseBrowser();
      case WebviewDownloadState.completed:
        _finished(d);
        _releaseBrowser();
    }
  }

  /// What a stopped download left is never a usable archive, and the next try
  /// should get the plain file name.
  Future<void> _discardPartial(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Removing the partial download failed: $e');
    }
    _ref.read(libraryProvider.notifier).scan();
  }

  /// Saves the game's data beside the file. It never gets in the way of the
  /// download: without it, the archive is just a plain row.
  Future<void> _saveCard(WebviewDownload d, ArchiveCardDraft draft) async {
    final library = _ref.read(settingsProvider).libraryDir;
    if (library.isEmpty) return;
    void refresh() => _ref.read(archiveCardsEpochProvider.notifier).update((n) => n + 1);
    try {
      final card = await ArchiveCards.create(library, p.basename(d.path), draft);
      _cards[d.id] = card;
      refresh();
      if (draft.coverUrl.isEmpty && draft.screenshotUrls.isEmpty) return;
      await WebViewHold.take(_ref);
      try {
        await MetadataService.downloadImages(
          gameFolder: card.folder,
          coverUrl: draft.coverUrl,
          screenshotUrls: draft.screenshotUrls,
          previewUrls: draft.previewUrls,
          scrapingService: _ref.read(scrapingServiceProvider),
        );
      } finally {
        WebViewHold.letGo(_ref);
      }
      refresh();
    } catch (e) {
      debugPrint('Saving the card for ${p.basename(d.path)} failed: $e');
    }
  }

  void _finished(WebviewDownload d) {
    _cards.remove(d.id);
    final ext = p.extension(d.path).toLowerCase();
    if (ext != '.zip' && ext != '.rar') {
      _update(d.id, (j) => j.copyWith(
            stage: JobStage.saved,
            received: d.received,
            total: d.total,
            path: d.path,
            message: 'In your library folder',
          ));
      _ref.read(libraryProvider.notifier).scan();
      return;
    }
    _update(d.id, (j) => j.copyWith(stage: JobStage.waiting, received: d.received, total: d.total, path: d.path));
    _ref.read(extractRequestsProvider.notifier).update((paths) => [...paths, d.path]);
    _ref.read(libraryProvider.notifier).scan();
  }

  void _onExtraction(Map<String, ExtractionStatus> statuses) {
    for (final job in state.where((j) => j.active && j.path.isNotEmpty)) {
      final s = statuses[job.path];
      if (s == null) continue;
      if (s.failed) {
        _update(job.id, (j) => j.copyWith(stage: JobStage.failed, message: s.error ?? 'Extraction failed'));
      } else if (s.done) {
        _update(job.id, (j) => j.copyWith(stage: JobStage.ready, extractProgress: 1));
        _removeReplaced(job);
      } else if (s.running) {
        _update(job.id, (j) => j.copyWith(stage: JobStage.extracting, extractProgress: s.progress));
      }
    }
  }

  /// The old version goes only after the new one has landed, and only when
  /// the user ticked that on the Get sheet.
  void _removeReplaced(DownloadJob job) {
    final folder = job.replaceFolder;
    if (folder == null) return;
    Directory(folder).delete(recursive: true).then((_) {
      _ref.read(libraryProvider.notifier).scan();
    }, onError: (_) {});
  }

  void _releaseBrowser() {
    final browser = _ref.read(siteBrowserProvider);
    if (!browserPanelOpen && !state.any((j) => j.stage == JobStage.downloading)) {
      browser.shutDown();
    }
  }

  /// Set by the site panel while it's on screen.
  bool browserPanelOpen = false;

  void panelClosed() {
    browserPanelOpen = false;
    _releaseBrowser();
  }

  void cancel(DownloadJob job) => _ref.read(siteBrowserProvider).cancelDownload(job.id);

  void dismiss(DownloadJob job) => state = state.where((j) => j.id != job.id).toList();
}

final downloadsProvider = StateNotifierProvider<DownloadsNotifier, List<DownloadJob>>(
  (ref) => DownloadsNotifier(ref),
);
