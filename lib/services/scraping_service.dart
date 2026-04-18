import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';

/// Provider for the ScrapingService
final scrapingServiceProvider = Provider<ScrapingService>((ref) => ScrapingService());

class _ScrapingRequest {
  final String url;
  final Completer<dynamic> completer;
  final String? script;
  _ScrapingRequest(this.url, this.completer, {this.script});
}

/// A service that leverages a hidden WebviewController to perform 
/// network requests as a browser to bypass Cloudflare/TLS fingerprinting.
class ScrapingService {
  final _controller = WebviewController();
  bool _isInitialized = false;
  final _initCompleter = Completer<void>();

  Future<void> get ready => _initCompleter.future;
  
  // Queue synchronization
  final List<_ScrapingRequest> _queue = [];
  bool _isProcessing = false;

  WebviewController get controller => _controller;
  bool get isInitialized => _isInitialized;

  /// Initializes the WebviewController. 
  /// This must be called from the UI thread (via ScrapingWebView widget).
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(const Color(0x00000000));
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      debugPrint('ScrapingService initialized.');
    } catch (e) {
      debugPrint('Failed to initialize ScrapingService: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    }
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

    try {
      if (!_isInitialized) {
        throw Exception('ScrapingService not initialized');
      }

      debugPrint('Scraping: ${request.url}');
      await _controller.loadUrl(request.url);

      // Wait for page to report as loaded
      bool loaded = false;
      final timeout = DateTime.now().add(const Duration(seconds: 25));
      
      final subscription = _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          loaded = true;
        }
      });

      // Poll until loaded or timeout
      while (!loaded && DateTime.now().isBefore(timeout)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      subscription.cancel();

      // Check for intermediate "Searching" pages common in XenForo
      int retries = 5;
      while (retries > 0) {
        await Future.delayed(const Duration(milliseconds: 2000));
        final html = await _controller.executeScript('document.documentElement.outerHTML');
        if (html is! String || (!html.contains('Searching...') && !html.contains('p-main-header'))) {
          // If we see p-main-header, we're likely on a real page. 
          // If we don't see "Searching...", we might be finished.
          break;
        }
        debugPrint('Detected intermediate search page, waiting... ($retries)');
        retries--;
      }

      // Extracts results
      if (request.script != null) {
        final result = await _controller.executeScript(request.script!);
        request.completer.complete(result);
      } else {
        final html = await _controller.executeScript('document.documentElement.outerHTML');
        request.completer.complete(html is String ? html : '');
      }
    } catch (e) {
      debugPrint('Scraping failed for ${request.url}: $e');
      request.completer.completeError(e);
    } finally {
      _isProcessing = false;
      // Cycle next item
      if (_queue.isNotEmpty) {
        _processQueue();
      }
    }
  }
}
