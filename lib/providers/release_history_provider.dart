import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed_item.dart';
import '../services/release_history.dart';

/// The permanent release history (see [ReleaseHistory]), filled by the Feed.
/// Saved a few seconds after it changes, so a refresh writes once.
class ReleaseHistoryStore extends ChangeNotifier {
  final ReleaseHistory history;
  ReleaseHistoryStore(this.history);

  Timer? _save;

  void record(Iterable<RawFeedItem> items) {
    if (!history.record(items)) return;
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(seconds: 5), history.save);
  }

  @override
  void dispose() {
    if (_save?.isActive ?? false) {
      _save!.cancel();
      history.save();
    }
    super.dispose();
  }
}

final releaseHistoryProvider = ChangeNotifierProvider<ReleaseHistoryStore>((ref) => ReleaseHistoryStore(ReleaseHistory.load()));
