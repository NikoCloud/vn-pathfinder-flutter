import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../services/scraping_service.dart';

/// A hidden widget that hosts the WebView2 instance for scraping.
///
/// The WebView is created lazily — only when [scrapingSessionProvider] > 0 —
/// and disposed when the session count drops back to zero. This keeps Chromium
/// out of memory during normal app use.
///
/// Must remain in the AppShell widget tree permanently so Flutter can attach
/// the native window handle whenever a session is active.
class ScrapingWebView extends ConsumerStatefulWidget {
  const ScrapingWebView({super.key});

  @override
  ConsumerState<ScrapingWebView> createState() => _ScrapingWebViewState();
}

class _ScrapingWebViewState extends ConsumerState<ScrapingWebView> {
  /// Guards against concurrent init/dispose calls.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(scrapingServiceProvider);

    // React to session count changes without running side-effects in build.
    ref.listen<int>(scrapingSessionProvider, (prev, next) {
      if (_busy) return;
      if (next > 0 && !service.isInitialized) {
        _init(service);
      } else if (next == 0 && service.isInitialized) {
        _disposeService(service);
      }
    });

    return Offstage(
      offstage: true,
      child: service.isInitialized
          ? Webview(service.controller)
          : const SizedBox.shrink(),
    );
  }

  Future<void> _init(ScrapingService service) async {
    _busy = true;
    await service.initialize();
    _busy = false;
    if (mounted) setState(() {});
  }

  Future<void> _disposeService(ScrapingService service) async {
    _busy = true;
    await service.dispose();
    _busy = false;
    if (mounted) setState(() {});
  }
}
