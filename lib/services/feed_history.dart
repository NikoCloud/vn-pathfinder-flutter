import '../models/feed_item.dart';
import 'update_check_service.dart';

/// How far back the Feed goes.
const feedWindow = Duration(days: 10);

/// A thread posted this recently is a new game, whatever its site says after
/// the first edit.
const newThreadWindow = Duration(days: 3);

/// The wait between pages of a site's list.
const listPageGap = Duration(seconds: 5);

/// A safety stop. Ten days of F95Zone is about 17 pages.
const maxListPages = 30;

/// Identifies a thread on its site. Not the link: forum links carry the thread
/// title, so a new version in the title changes them.
String threadKey(RawFeedItem row) {
  final number = UpdateCheckService.threadId(row.url);
  return number == null ? row.id : '${row.source}::$number';
}

/// A thread's first post, read from the thread itself.
class ThreadDates {
  final DateTime posted;
  final DateTime? edited;
  const ThreadDates(this.posted, this.edited);
}

/// The version of a thread the Feed last saw.
class ThreadRelease {
  final String version;

  /// When that version came out.
  final DateTime at;

  /// When the thread went up, when a site or the thread has said.
  final DateTime? posted;

  const ThreadRelease(this.version, this.at, this.posted);

  Map<String, dynamic> toJson() => {
        'version': version,
        'at': at.toIso8601String(),
        if (posted != null) 'posted': posted!.toIso8601String(),
      };

  static ThreadRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return ThreadRelease('${json['version'] ?? ''}', at, DateTime.tryParse('${json['posted']}'));
  }
}

/// A release is a new version of a thread, not a new date. Sites re-date
/// threads for other reasons: LewdCorner's list follows any edit of the first
/// post, and a forum's RSS follows the latest reply. So each thread's version
/// is remembered with its date, for longer than the Feed shows it.
///
///  * The same version keeps its date, however the site re-dated it.
///  * A new version takes the date of the edit that brought it.
///  * F95Zone's list is the exception: its dates held up in every check, so a
///    same-version fix there still counts.
class ReleaseRecord {
  /// Sites whose dates hold up on their own.
  static const _trustedLists = {'f95zone'};

  /// Sites with no list of their own, whose threads have to be opened for a
  /// date. Public feeds standing in for F95Zone or LewdCorner aren't here:
  /// that would be many more page loads on a site that just refused one.
  static const _datedFromThreads = {'azc'};

  /// Threads kept per site, newest first.
  static const _keep = 5000;

  final Map<String, ThreadRelease> _threads;

  ReleaseRecord([Map<String, ThreadRelease>? threads]) : _threads = threads ?? {};

  /// A record built from rows saved before there was one.
  factory ReleaseRecord.seeded(Iterable<RawFeedItem> rows) {
    final record = ReleaseRecord();
    for (final row in rows) {
      final at = row.publishedAt;
      if (at == null) continue;
      record._threads[threadKey(row)] = ThreadRelease(feedVersionKey(row), at, row.postedAt);
    }
    return record;
  }

  factory ReleaseRecord.fromJson(Object? json) {
    final record = ReleaseRecord();
    if (json is Map) {
      json.forEach((key, value) {
        final release = ThreadRelease.fromJson(value);
        if (release != null) record._threads['$key'] = release;
      });
    }
    return record;
  }

  Map<String, dynamic> toJson() {
    final bySite = <String, List<MapEntry<String, ThreadRelease>>>{};
    for (final entry in _threads.entries) {
      bySite.putIfAbsent(entry.key.split('::').first, () => []).add(entry);
    }
    return {
      for (final rows in bySite.values)
        for (final entry in (rows..sort((a, b) => b.value.at.compareTo(a.value.at))).take(_keep))
          entry.key: entry.value.toJson(),
    };
  }

  bool _isNewVersion(RawFeedItem row, ThreadRelease seen) {
    final version = feedVersionKey(row);
    return version.isNotEmpty && version != seen.version;
  }

  bool _isRecent(DateTime? posted, DateTime now) =>
      posted != null && now.difference(posted) < newThreadWindow;

  /// Whether [row] has no usable date until its thread has been read.
  bool needsThread(RawFeedItem row) {
    if (row.fromSiteList || !_datedFromThreads.contains(row.source)) return false;
    final seen = _threads[threadKey(row)];
    return seen == null || _isNewVersion(row, seen);
  }

  /// [row] with the date and label the rule gives it, noted in the record.
  /// [thread] is what its thread says, for a row that [needsThread].
  RawFeedItem settle(RawFeedItem row, DateTime now, {ThreadDates? thread}) {
    final key = threadKey(row);
    final seen = _threads[key];
    final posted = thread?.posted ?? row.postedAt ?? seen?.posted;
    final edited = thread?.edited ?? thread?.posted ?? row.publishedAt;

    final DateTime? at;
    if (row.fromSiteList && _trustedLists.contains(row.source)) {
      at = row.publishedAt;
    } else if (seen == null) {
      at = _isRecent(posted, now) ? posted : edited;
    } else if (_isNewVersion(row, seen)) {
      // Changing only a thread's title leaves the post's dates alone, so the
      // moment it was noticed is the closest there is.
      at = edited != null && edited.isAfter(seen.at) ? edited : now;
    } else {
      at = seen.at;
    }

    if (at != null) {
      final version = feedVersionKey(row);
      _threads[key] = ThreadRelease(version.isEmpty ? seen?.version ?? '' : version, at, posted);
    }
    return row.settled(at, isNew: _isRecent(posted, now));
  }
}

/// How far back a site's list has been read.
class SiteCatchUp {
  /// Everything on the list newer than this has been read.
  final DateTime? caughtUpTo;

  /// A catch-up that stopped early started from this date, which is where the
  /// next one has read enough to skip ahead.
  final DateTime? resumeFrom;

  /// The first page that catch-up didn't get.
  final int resumePage;

  const SiteCatchUp({this.caughtUpTo, this.resumeFrom, this.resumePage = 0});

  bool get stoppedEarly => resumeFrom != null;

  Map<String, dynamic> toJson() => {
        if (caughtUpTo != null) 'caught_up_to': caughtUpTo!.toIso8601String(),
        if (resumeFrom != null) 'resume_from': resumeFrom!.toIso8601String(),
        if (resumeFrom != null) 'resume_page': resumePage,
      };

  factory SiteCatchUp.fromJson(Object? json) {
    if (json is! Map) return const SiteCatchUp();
    return SiteCatchUp(
      caughtUpTo: DateTime.tryParse('${json['caught_up_to']}'),
      resumeFrom: DateTime.tryParse('${json['resume_from']}'),
      resumePage: json['resume_page'] as int? ?? 0,
    );
  }
}

/// Reads a site's list, newest first, back to where [from] says it was caught
/// up, and no further than [feedWindow]. [readPage] returns nothing when the
/// site refuses, and that ends the run: what it got stays, the caught-up date
/// doesn't move, and the next run skips what it already read. Null if the very
/// first page was refused.
Future<SiteCatchUp?> readBack(
  SiteCatchUp from, {
  required Future<List<RawFeedItem>> Function(int page) readPage,
  required void Function(List<RawFeedItem>) onRows,
  required DateTime now,
  Duration gap = listPageGap,
}) async {
  final floor = now.subtract(feedWindow);
  final caughtUp = from.caughtUpTo;
  final until = caughtUp != null && caughtUp.isAfter(floor) ? caughtUp : floor;
  final resume = from.resumeFrom;

  DateTime? newest;
  var skipped = resume == null;
  var page = 1;
  for (var reads = 0; reads < maxListPages; reads++) {
    if (reads > 0) await Future.delayed(gap);
    final rows = await readPage(page);
    final dates = rows.map((r) => r.publishedAt).whereType<DateTime>().toList()..sort();
    if (dates.isEmpty) break;
    onRows(rows);
    newest ??= dates.last;
    if (!dates.first.isAfter(until)) return SiteCatchUp(caughtUpTo: newest);
    if (!skipped && !dates.first.isAfter(resume!)) {
      // The last run read everything from here down to resumePage. New rows
      // have pushed that down by the pages just read.
      skipped = true;
      page += from.resumePage - 1;
    } else {
      page++;
    }
  }
  if (newest == null) return null;
  return SiteCatchUp(caughtUpTo: from.caughtUpTo, resumeFrom: newest, resumePage: page);
}
