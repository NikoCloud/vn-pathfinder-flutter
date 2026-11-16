import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/metadata_service.dart';
import '../services/scraping_service.dart';
import '../services/thread_parser.dart';
import 'settings_provider.dart';
import 'update_provider.dart';

/// A game's thread, read once per run. Nothing is requested under Lockdown.
class ThreadInfo {
  final MetadataResult details;
  final ThreadDownloads downloads;
  const ThreadInfo(this.details, this.downloads);
}

final threadProvider = FutureProvider.family<ThreadInfo?, String>((ref, url) async {
  if (url.isEmpty || ref.watch(lockdownProvider)) return null;
  ref.keepAlive();
  final sessions = ref.read(scrapingSessionProvider.notifier);
  sessions.update((n) => n + 1);
  try {
    final found = await MetadataService.fetchThread(url, ref.read(scrapingServiceProvider));
    if (found == null) return null;
    final info = ThreadInfo(found.$1, found.$2);
    // Update alerts use what the thread says too, so a game just opened or
    // fetched doesn't wait for the daily check.
    ref.read(updateCheckProvider.notifier).noteThreadVersion(url, info.details.version);
    return info;
  } catch (e) {
    debugPrint('Thread read failed: $e');
    return null;
  } finally {
    sessions.update((n) => (n - 1).clamp(0, 999));
  }
});
