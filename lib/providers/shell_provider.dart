import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed_item.dart';

/// The app's top-level tabs, in title bar order.
enum AppTab {
  home('Home'),
  library('Library'),
  archive('Archive'),
  feed('Feed'),
  stats('Stats');

  const AppTab(this.label);
  final String label;
}

final activeTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

/// What the game page is showing: a library game, a Feed release, or both when
/// a release is for a game you have.
class GameTarget {
  final String? baseKey;
  final RawFeedItem? item;

  /// Where Back goes.
  final AppTab origin;

  const GameTarget({this.baseKey, this.item, required this.origin});
}

final gamePageProvider = StateProvider<GameTarget?>((ref) => null);

/// Library shows the list and game side by side rather than the card wall.
final libraryDetailsProvider = StateProvider<bool>((ref) => false);

/// Quick find (Ctrl+K).
final finderOpenProvider = StateProvider<bool>((ref) => false);

// The art the page takes its colour from, as a local path or a web address:
// what you're pointing at, otherwise the game page's art, otherwise whatever
// the current tab leads with.
final ambientHoverProvider = StateProvider<String?>((ref) => null);
final ambientPageProvider = StateProvider<String?>((ref) => null);
final ambientRestProvider = StateProvider<Map<AppTab, String?>>((ref) => const {});

final ambientArtProvider = Provider<String?>((ref) {
  final hover = ref.watch(ambientHoverProvider);
  if (hover != null) return hover;
  if (ref.watch(gamePageProvider) != null) return ref.watch(ambientPageProvider);
  return ref.watch(ambientRestProvider)[ref.watch(activeTabProvider)];
});
