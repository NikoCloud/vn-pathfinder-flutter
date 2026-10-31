import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

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

  final _downloads = StreamController<WebviewDownload>.broadcast();
  Stream<WebviewDownload> get downloads => _downloads.stream;

  WebviewController? get controller => _controller;
  bool get isOpen => _controller?.value.isInitialized ?? false;

  Future<void> open(String address, {required String downloadFolder}) async {
    error = null;
    url = address;
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
        _downloadSub = c.downloads.listen(_downloads.add);
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

  void back() => _controller?.goBack();
  void forward() => _controller?.goForward();
  void reload() => _controller?.reload();
  void cancelDownload(int id) => _controller?.cancelDownload(id);

  /// Stops the page but keeps the browser, so downloads carry on.
  void leave() => _controller?.loadUrl('about:blank');

  Future<void> shutDown() async {
    final c = _controller;
    _controller = null;
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
