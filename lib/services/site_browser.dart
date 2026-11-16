import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

import 'redirect_guard.dart';

/// The visible in-app browser the Get flow opens. The page in it is the site's
/// own: nothing is filled in, clicked or skipped, and whatever a site or host
/// asks of a visitor is for the person at the keyboard. All this adds is that a
/// download lands in the library and can be followed.
///
/// It shares its sign-ins with the rest of the app, because every WebView2 in
/// the app uses one profile. It stays alive after the panel closes until the
/// last download has finished.
class SiteBrowser extends ChangeNotifier {
  WebviewController? _controller;
  StreamSubscription? _urlSub, _loadingSub, _downloadSub, _historySub, _titleSub;

  String url = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;

  /// Set when WebView2 can't be started, so the panel can say so.
  String? error;

  final _guard = RedirectGuard();

  /// A page the guard stopped the browser from going to, for the panel's
  /// "Go there anyway". Null when nothing was stopped.
  String? get blocked => _guard.blocked;

  String _downloadFolder = '';
  Timer? _folderWatch;
  Set<String> _folderBefore = {};
  final _reported = <String>{};
  final _sizes = <String, int>{};
  var _nextFolderId = -1;

  final _downloads = StreamController<WebviewDownload>.broadcast();
  Stream<WebviewDownload> get downloads => _downloads.stream;

  WebviewController? get controller => _controller;
  bool get isOpen => _controller?.value.isInitialized ?? false;

  Future<void> open(String address, {required String downloadFolder}) async {
    error = null;
    url = address;
    _guard.reset(address);
    _downloadFolder = downloadFolder;
    _folderWatch?.cancel();
    _folderWatch = null;
    notifyListeners();
    try {
      var c = _controller;
      if (c == null) {
        c = WebviewController();
        await c.initialize();
        await c.setBackgroundColor(const Color(0xFFFFFFFF));
        await c.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
        _urlSub = c.url.listen((u) {
          url = u;
          final back = _guard.onUrl(u);
          if (back != null) _controller?.loadUrl(back);
          if (isMegaSite(siteOf(u))) _watchFolder();
          notifyListeners();
        });
        _loadingSub = c.loadingState.listen((s) {
          loading = s == LoadingState.loading;
          notifyListeners();
        });
        _historySub = c.historyChanged.listen((h) {
          canGoBack = h.canGoBack;
          canGoForward = h.canGoForward;
          notifyListeners();
        });
        _titleSub = c.title.listen((_) {});
        _downloadSub = c.downloads.listen((d) {
          _reported.add(p.normalize(d.path).toLowerCase());
          _downloads.add(d);
        });
        _controller = c;
      }
      await c.setDownloadFolder(downloadFolder);
      await c.loadUrl(address);
    } catch (e) {
      debugPrint('Site browser: $e');
      error = 'The in-app browser could not start. Is the WebView2 Runtime installed?';
    }
    notifyListeners();
  }

  /// "Go there anyway": follows the page the guard stopped.
  void goAnyway() {
    final target = _guard.blocked;
    if (target == null) return;
    _guard.allow(target);
    _controller?.loadUrl(target);
    notifyListeners();
  }

  void dismissBlocked() {
    _guard.blocked = null;
    notifyListeners();
  }

  /// Mega saves files from inside its page, which the browser doesn't report
  /// as a download (#47). While a Mega page has been open, an archive that
  /// appears in the download folder and stops growing is reported as one, so
  /// it shows in the dock and unpacks like any other.
  void _watchFolder() {
    if (_folderWatch != null || _downloadFolder.isEmpty) return;
    _folderBefore = _archivesIn(_downloadFolder).keys.toSet();
    _sizes.clear();
    _folderWatch = Timer.periodic(const Duration(seconds: 2), (_) => _checkFolder());
  }

  /// The folder's archives, keyed the way paths compare on Windows.
  static Map<String, String> _archivesIn(String folder) {
    try {
      return {
        for (final f in Directory(folder).listSync().whereType<File>())
          if (const {'.zip', '.rar', '.7z'}.contains(p.extension(f.path).toLowerCase()))
            p.normalize(f.path).toLowerCase(): f.path,
      };
    } catch (_) {
      return {};
    }
  }

  void _checkFolder() {
    for (final MapEntry(key: path, value: original) in _archivesIn(_downloadFolder).entries) {
      if (_folderBefore.contains(path) || _reported.contains(path)) continue;
      int size;
      try {
        size = File(original).lengthSync();
      } catch (_) {
        continue;
      }
      // Reported once it's the same size two checks running.
      if (size == 0 || _sizes[path] != size) {
        _sizes[path] = size;
        continue;
      }
      _reported.add(path);
      final id = _nextFolderId--;
      for (final state in [WebviewDownloadState.started, WebviewDownloadState.completed]) {
        _downloads.add(WebviewDownload(
            id: id, state: state, received: size, total: size, url: url, path: original, mime: '', reason: 0));
      }
    }
  }

  void back() => _controller?.goBack();
  void forward() => _controller?.goForward();
  void reload() => _controller?.reload();
  void cancelDownload(int id) => _controller?.cancelDownload(id);

  /// Stops the page but keeps the browser, so downloads carry on.
  void leave() => _controller?.loadUrl('about:blank');

  Future<void> shutDown() async {
    final c = _controller;
    _controller = null;
    _folderWatch?.cancel();
    _folderWatch = null;
    await _urlSub?.cancel();
    await _loadingSub?.cancel();
    await _historySub?.cancel();
    await _titleSub?.cancel();
    await _downloadSub?.cancel();
    url = '';
    loading = false;
    canGoBack = canGoForward = false;
    if (c != null) {
      try {
        await c.dispose();
      } catch (e) {
        debugPrint('Site browser: dispose: $e');
      }
    }
    notifyListeners();
  }
}
