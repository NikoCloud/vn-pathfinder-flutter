import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../services/scraping_service.dart';

/// A hidden widget that hosts the WebView2 instance for background scraping.
/// Must be placed in the widget tree (e.g., in AppShell) to keep the browser alive.
class ScrapingWebView extends ConsumerStatefulWidget {
  const ScrapingWebView({super.key});

  @override
  ConsumerState<ScrapingWebView> createState() => _ScrapingWebViewState();
}

class _ScrapingWebViewState extends ConsumerState<ScrapingWebView> {
  @override
  void initState() {
    super.initState();
    // Start initialization as soon as the widget is inserted
    _init();
  }

  Future<void> _init() async {
    final service = ref.read(scrapingServiceProvider);
    await service.initialize();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(scrapingServiceProvider);
    
    // We must return a Webview widget so that the controller can attach to a native window.
    // We use Offstage to keep it hidden from the user.
    return Offstage(
      offstage: true,
      child: service.isInitialized
          ? Webview(service.controller)
          : const SizedBox.shrink(),
    );
  }
}
