import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/metadata_service.dart';
import 'settings_provider.dart';
import '../services/scraping_service.dart';

/// Art for games you don't have yet, kept on disk at
/// %APPDATA%\VN Pathfinder\feed_images so the Feed works offline and Lockdown
/// can show what was already fetched. Nothing is requested under Lockdown.
class FeedImageCache {
  static Directory get dir =>
      Directory(p.join(Platform.environment['APPDATA'] ?? '', 'VN Pathfinder', 'feed_images'));

  static File fileFor(String url) => File(p.join(dir.path, sha1.convert(utf8.encode(url)).toString()));

  static const _maxAge = Duration(days: 14);

  /// Removes images nothing has used lately. The Feed only keeps ten days.
  static Future<void> prune() async {
    try {
      if (!dir.existsSync()) return;
      final cutoff = DateTime.now().subtract(_maxAge);
      await for (final entry in dir.list()) {
        if (entry is File && entry.lastModifiedSync().isBefore(cutoff)) await entry.delete();
      }
    } catch (e) {
      debugPrint('Feed images: prune failed: $e');
    }
  }
}

/// One image at a time per site host, so a wall of cards doesn't look like a
/// scraper to the sites.
class _Gate {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

final _gates = <String, _Gate>{};

/// Some sites only show images to logged-in visitors, so those go through the
/// app's hidden WebView. It stays up briefly between images rather than
/// starting over for each one.
class WebViewHold {
  static bool _held = false;
  static Timer? _release;

  static Future<void> take(Ref ref) async {
    _release?.cancel();
    if (!_held) {
      _held = true;
      ref.read(scrapingSessionProvider.notifier).update((n) => n + 1);
    }
    await ref.read(scrapingServiceProvider).ready.timeout(const Duration(seconds: 20));
  }

  static void letGo(Ref ref) {
    _release = Timer(const Duration(seconds: 30), () {
      _held = false;
      ref.read(scrapingSessionProvider.notifier).update((n) => (n - 1).clamp(0, 999));
    });
  }
}

/// The local path of a web image, null until it's on disk. Reading this
/// starts the download unless Lockdown is on.
final feedImageProvider = Provider.family<String?, String>((ref, url) {
  final file = FeedImageCache.fileFor(url);
  if (file.existsSync()) return file.path;
  return ref.watch(_feedImageFetchProvider(url)).valueOrNull;
});

final _feedImageFetchProvider = FutureProvider.family<String?, String>((ref, url) async {
  final locked = ref.watch(settingsProvider.select((s) => s.lockdown));
  if (locked) return null;
  final host = Uri.tryParse(url)?.host ?? '';
  final gate = _gates.putIfAbsent(host, _Gate.new);
  return gate.run(() async {
    final file = FeedImageCache.fileFor(url);
    if (file.existsSync()) return file.path;
    try {
      var bytes = await MetadataService.fetchImageBytes(url, null);
      if (bytes == null && _needsLogin(host)) {
        await WebViewHold.take(ref);
        try {
          bytes = await MetadataService.fetchImageBytes(url, ref.read(scrapingServiceProvider));
        } finally {
          WebViewHold.letGo(ref);
        }
      }
      if (bytes == null || bytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('Feed images: $e');
      return null;
    }
  });
});

bool _needsLogin(String host) =>
    host.contains('lewdcorner') || host.contains('f95zone') || host.contains('azkosel');
