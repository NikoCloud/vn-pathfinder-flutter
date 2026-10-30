import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';

/// Tracks the number of open scraping sessions.
/// ScrapingWebView initializes the WebView when this > 0 and disposes when it
/// drops back to 0, so Chromium is only alive while actually needed.
final scrapingSessionProvider = StateProvider<int>((ref) => 0);

/// Provider for the ScrapingService singleton.
final scrapingServiceProvider = Provider<ScrapingService>((ref) => ScrapingService());

class _ScrapingRequest {
  final String url;
  final Completer<dynamic> completer;
  final String? script;
  final bool reuseOrigin;
  _ScrapingRequest(this.url, this.completer, {this.script, this.reuseOrigin = false});
}

/// Thrown when a queued request is cancelled before it executes.
class ScrapingCancelledException implements Exception {
  const ScrapingCancelledException();
  @override
  String toString() => 'ScrapingCancelledException: request was cancelled';
}

/// A scraping failure whose message is shown to the user as-is.
class ScrapingException implements Exception {
  final String message;
  const ScrapingException(this.message);
  @override
  String toString() => message;
}

/// A service that leverages a hidden WebviewController to perform
/// network requests as a browser to bypass Cloudflare/TLS fingerprinting.
///
/// Lifecycle: the WebView is NOT initialized on construction. Call [initialize]
/// (done by ScrapingWebView when a scraping session opens) and [dispose] (done
/// when the session closes) to bracket each use.
class ScrapingService {
  WebviewController _controller = WebviewController();
  bool _isInitialized = false;
  bool _isInitializing = false;
  /// Origin of the page the WebView last finished loading (for [evalOnOrigin]).
  String? _loadedOrigin;
  Completer<void> _initCompleter = Completer<void>();

  Future<void> get ready => _initCompleter.future;

  // Queue synchronization
  final List<_ScrapingRequest> _queue = [];
  bool _isProcessing = false;

  WebviewController get controller => _controller;
  bool get isInitialized => _isInitialized;

  /// Initializes the WebviewController.
  /// Must be called from the UI thread (via ScrapingWebView widget).
  /// Safe to call when already initialized — returns immediately.
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(const Color(0x00000000));
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      debugPrint('ScrapingService initialized.');
    } catch (e) {
      debugPrint('Failed to initialize ScrapingService: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    } finally {
      _isInitializing = false;
    }
  }

  /// Cancel all pending queued requests without touching the controller.
  void cancelPending() {
    final count = _queue.length;
    for (final req in _queue) {
      if (!req.completer.isCompleted) {
        req.completer.completeError(const ScrapingCancelledException());
      }
    }
    _queue.clear();
    debugPrint('ScrapingService: cancelled $count pending requests.');
  }

  /// Cancel pending requests, dispose the native WebView2 controller, and
  /// reset internal state so [initialize] can be called again next session.
  Future<void> dispose() async {
    cancelPending();
    _isProcessing = false;

    if (_isInitialized) {
      try {
        _controller.dispose();
      } catch (e) {
        debugPrint('ScrapingService: controller dispose error (ignored): $e');
      }
    }

    // Fresh state for next session
    _controller = WebviewController();
    _isInitialized = false;
    _isInitializing = false;
    _loadedOrigin = null;
    _initCompleter = Completer<void>();
    debugPrint('ScrapingService disposed.');
  }

  /// Navigates to a URL and returns the page source (HTML).
  /// Enforces sequential processing to prevent navigation collisions.
  Future<String> getString(String url) async {
    final completer = Completer<dynamic>();
    _queue.add(_ScrapingRequest(url, completer));
    _processQueue();
    return (await completer.future) as String;
  }

  /// Navigates to a URL and evaluates a script. Returns the result.
  Future<dynamic> evalOnPage(String url, String script) async {
    final completer = Completer<dynamic>();
    _queue.add(_ScrapingRequest(url, completer, script: script));
    _processQueue();
    return completer.future;
  }

  /// Like [evalOnPage], but when the WebView is already showing a page from
  /// [url]'s origin, runs [script] there without navigating again. For
  /// same-origin fetches that only need the session cookies (image downloads).
  Future<dynamic> evalOnOrigin(String url, String script) async {
    final completer = Completer<dynamic>();
    _queue.add(_ScrapingRequest(url, completer, script: script, reuseOrigin: true));
    _processQueue();
    return completer.future;
  }

  /// Returns cookies for the given URL using document.cookie.
  Future<Map<String, String>> getCookies(String url) async {
    if (!_isInitialized) return {};
    final res = await evalOnPage(url, 'document.cookie');
    final map = <String, String>{};
    if (res is String) {
      for (final part in res.split(';')) {
        final pair = part.trim().split('=');
        if (pair.length >= 2) {
          map[pair[0]] = pair.sublist(1).join('=');
        }
      }
    }
    return map;
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    final request = _queue.removeAt(0);
    final stopwatch = Stopwatch()..start();

    try {
      if (!_isInitialized) {
        // Callers open a scraping session and queue their first requests in
        // the same breath, while the WebView is still starting up — wait for
        // it instead of failing those requests.
        try {
          await ready.timeout(const Duration(seconds: 20));
        } on TimeoutException {
          throw const ScrapingException('The embedded browser did not start in time.');
        }
      }

      if (request.reuseOrigin &&
          request.script != null &&
          _loadedOrigin == Uri.parse(request.url).origin) {
        final result = await _controller.executeScript(request.script!);
        if (!request.completer.isCompleted) request.completer.complete(result);
        return;
      }

      debugPrint('Scraping: ${request.url}');

      // Wait for page to report as loaded. Listen before navigating so a fast
      // navigationCompleted isn't missed.
      bool loaded = false;
      final timeout = DateTime.now().add(const Duration(seconds: 25));

      final subscription = _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          loaded = true;
        }
      });
      await _controller.loadUrl(request.url);

      // Poll until loaded or timeout
      while (!loaded && DateTime.now().isBefore(timeout)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      subscription.cancel();

      // XenForo shows an intermediate "Searching…" page before redirecting to
      // results. Wait until either:
      //   (a) the "Searching…" indicator is gone, OR
      //   (b) a real page header (p-main-header) is visible.
      // Cap at 5 retries × 2 s = 10 s max.
      const maxRetries = 5;
      var html = '';
      for (var i = 0; i < maxRetries; i++) {
        await Future.delayed(const Duration(milliseconds: 2000));
        html = await _pageHtml();
        final isSearching = html.contains('Searching...');
        final hasPageHeader = html.contains('p-main-header');
        // Ready when the search spinner is gone OR the real page structure exists
        if (!isSearching || hasPageHeader) break;
        debugPrint(
            'Detected intermediate search page, waiting… (${maxRetries - i - 1} retries left)');
      }

      // Cloudflare's "Just a moment…" check clears itself in a real browser
      // after a few seconds and redirects to the page. Wait for that rather
      // than handing the check page back as if it were the result.
      final challengeDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (_isChallengePage(html) && DateTime.now().isBefore(challengeDeadline)) {
        await Future.delayed(const Duration(seconds: 1));
        html = await _pageHtml();
      }
      if (_isChallengePage(html)) {
        throw ScrapingException(
            'Blocked by a Cloudflare check on ${Uri.parse(request.url).host} — try again in a minute.');
      }
      final origin = await _controller.executeScript('location.origin');
      _loadedOrigin = origin is String ? origin : null;

      // Extract results
      if (request.script != null) {
        final result = await _controller.executeScript(request.script!);
        debugPrint('Scraped in ${stopwatch.elapsedMilliseconds} ms (loaded=$loaded): '
            '${result is String ? '${result.length} chars' : result.runtimeType}');
        if (!request.completer.isCompleted) request.completer.complete(result);
      } else {
        debugPrint('Scraped in ${stopwatch.elapsedMilliseconds} ms (loaded=$loaded): '
            '${html.length} chars${_loginState(html)}');
        if (!request.completer.isCompleted) {
          request.completer.complete(html);
        }
      }
    } catch (e) {
      debugPrint('Scraping failed for ${request.url}: $e');
      if (!request.completer.isCompleted) {
        request.completer.completeError(e);
      }
    } finally {
      _isProcessing = false;
      if (_queue.isNotEmpty) {
        _processQueue();
      }
    }
  }

  Future<String> _pageHtml() async {
    final html = await _controller.executeScript('document.documentElement.outerHTML');
    return html is String ? html : '';
  }

  /// Cloudflare's interstitial check page. `_cf_chl_opt` only appears on the
  /// check itself — `challenge-platform` scripts also load on normal pages.
  static bool _isChallengePage(String html) =>
      html.contains('_cf_chl_opt') || html.contains('<title>Just a moment...</title>');

  /// XenForo sites flag every page with data-logged-in; surfaced in the log.
  static String _loginState(String html) {
    if (html.contains('data-logged-in="true"')) return ', logged in';
    if (html.contains('data-logged-in="false"')) return ', LOGGED OUT';
    return '';
  }
}
