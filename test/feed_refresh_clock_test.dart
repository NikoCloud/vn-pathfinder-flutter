// The Feed's automatic refresh follows the clock, counted from the last
// refresh.
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/providers/feed_provider.dart';

void main() {
  final last = DateTime(2026, 11, 15, 12);

  test('due once the interval has passed since the last refresh, however long the app was asleep', () {
    expect(feedRefreshDue(lastRefreshed: last, lastTry: last, hours: 6, now: last.add(const Duration(hours: 5, minutes: 59))), isFalse);
    expect(feedRefreshDue(lastRefreshed: last, lastTry: last, hours: 6, now: last.add(const Duration(hours: 6))), isTrue);
    expect(feedRefreshDue(lastRefreshed: last, lastTry: last, hours: 6, now: last.add(const Duration(days: 2))), isTrue);
  });

  test('never refreshed means due now; manual only is never due', () {
    expect(feedRefreshDue(lastRefreshed: null, lastTry: null, hours: 6, now: last), isTrue);
    expect(feedRefreshDue(lastRefreshed: null, lastTry: null, hours: 0, now: last), isFalse);
  });

  test('a refresh that failed is tried again after 15 minutes, not every minute', () {
    final tried = last.add(const Duration(hours: 7));
    expect(feedRefreshDue(lastRefreshed: last, lastTry: tried, hours: 6, now: tried.add(const Duration(minutes: 5))), isFalse);
    expect(feedRefreshDue(lastRefreshed: last, lastTry: tried, hours: 6, now: tried.add(const Duration(minutes: 15))), isTrue);
  });

  test('the next refresh is the interval after the last one, or now when that has passed', () {
    expect(nextFeedRefresh(lastRefreshed: last, hours: 6, now: last.add(const Duration(hours: 1))), last.add(const Duration(hours: 6)));
    final late = last.add(const Duration(hours: 9));
    expect(nextFeedRefresh(lastRefreshed: last, hours: 6, now: late), late);
    expect(nextFeedRefresh(lastRefreshed: last, hours: 0, now: late), isNull);
  });
}
