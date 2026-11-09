import '../services/scanner_service.dart' show compareVersionStrings;
import 'game_group.dart';
import 'game_version.dart';
import 'user_data.dart';

/// A game's play status. Stored per game in UserData.status (by id) when the
/// user picks one; otherwise detected — see [effectiveGameStatus].
enum GameStatus {
  unplayed('unplayed', 'Unplayed'),
  playing('playing', 'Playing'),
  updated('updated', 'Updated'),
  onHold('on-hold', 'On Hold'),
  completed('completed', 'Completed'),
  skimmed('skimmed', 'Skimmed'),
  abandoned('abandoned', 'Abandoned');

  const GameStatus(this.id, this.label);

  final String id;
  final String label;

  static GameStatus? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Statuses the user can pick. Updated is detected, never set by hand.
  static const manual = [playing, onHold, completed, skimmed, abandoned, unplayed];
}

/// Whether a game has been played: a manual played/unplayed mark (stored per
/// version folder, as 1.0 did), tracked playtime, or save files.
bool isGamePlayed(GameGroup g, UserData ud) {
  for (final v in g.versions) {
    if (ud.manualUnplayed.contains(v.folderName)) return false;
    if (ud.manualPlayed.contains(v.folderName)) return true;
  }
  if ((ud.playtime[g.baseKey] ?? 0) > 0) return true;
  return g.versions.any((v) => v.saves.lastSaveAt != null);
}

/// When a game was last played: its last tracked session or its newest save
/// file, whichever is later. Null if neither exists.
DateTime? gameLastPlayedAt(GameGroup g, UserData ud) {
  var latest = DateTime.tryParse(ud.lastPlayed[g.baseKey] ?? '');
  for (final v in g.versions) {
    final saved = v.saves.lastSaveAt;
    if (saved != null && (latest == null || saved.isAfter(latest))) latest = saved;
  }
  return latest;
}

/// A newer version is installed than the one last played. Folder dates aren't
/// used — copying a library resets them — so the first of these that applies:
///   1. the version last launched from the app;
///   2. saves in the newest version's own folder → it's been played;
///   3. saves in an older version's folder only → the newest hasn't been;
///   4. the game version recorded in the newest save, when both are numbers.
bool hasUpdateSinceLastPlayed(GameGroup g, UserData ud) {
  final latest = g.latestVersion;
  if (latest == null || latest.versionStr.isEmpty) return false;
  final launched = ud.lastPlayedVersion[g.baseKey];
  if (launched != null) return isClearlyNewer(latest.versionStr, launched);
  if (latest.saves.hasLocalSaves) return false;
  if (g.versions.any((v) => v.saves.hasLocalSaves)) return true;
  final saved = _newestSaveVersion(g);
  return saved != null && isClearlyNewer(latest.versionStr, saved);
}

/// Played, but only Ren'Py's autosaves exist — no save the player made
/// (page/slot or quicksave). Skimming players don't save by hand; autosaves
/// still appear before every choice.
bool looksSkimmed(GameGroup g) {
  var auto = 0, manual = 0;
  for (final v in g.versions) {
    auto += v.saves.autoSaves;
    manual += v.saves.manualSaves;
  }
  return auto > 0 && manual == 0;
}

String? _newestSaveVersion(GameGroup g) {
  SaveInfo? newest;
  for (final v in g.versions) {
    final at = v.saves.newestSaveAt;
    if (at != null && (newest == null || at.isAfter(newest.newestSaveAt!))) newest = v.saves;
  }
  return newest?.newestSaveVersion;
}

/// [candidate] is clearly a higher version than [current]: both numbered
/// ("0.12", "v1.0") and higher, or [candidate] is "Final" and [current] isn't.
/// A labelled version compares by its "v…" part ("Part 8 v0.114" → "v0.114").
/// Chapter, episode, part, act, book and season versions compare by their
/// numbers, but only against the same kind of label: "Ch.3.6.5" is newer than
/// "Chapter-3.6", while "Chapter-3" and "0.2" never compare. Words after the
/// numbers ("Public", "pc") don't count, so equal numbers are never newer.
bool isClearlyNewer(String candidate, String current) {
  final lc = _labelled(candidate), lcur = _labelled(current);
  if (lc != null || lcur != null) {
    if (lc == null || lcur == null || lc.$1 != lcur.$1) return false;
    final a = lc.$2, b = lcur.$2;
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return a.length > b.length;
  }
  final c = _numberedPart(candidate), cur = _numberedPart(current);
  if (cur.isEmpty) return false;
  if (c.toLowerCase() == 'final') return cur.toLowerCase() != 'final';
  final numbered = RegExp(r'^v?\.?\d', caseSensitive: false);
  if (!numbered.hasMatch(c) || !numbered.hasMatch(cur)) return false;
  return compareVersionStrings(c, cur) > 0;
}

/// (kind, numbers) for a version led by a word label with no "v…" part:
/// "Ch.3.6.5" → (chapter, [3, 6, 5]), "Episode 2 Public" → (episode, [2]).
/// Null for anything else, including "Chapter 2 v0.3", which compares by its
/// "v…" part.
(String, List<int>)? _labelled(String version) {
  final m = RegExp(
    r'^(ch(?:ap(?:ter)?)?|ep(?:isode)?|part|pt|act|book|season)[\s._-]*(\d+(?:[._]\d+)*)\b(.*)$',
    caseSensitive: false,
  ).firstMatch(version.trim());
  if (m == null) return null;
  if (RegExp(r'\bv\.?\d', caseSensitive: false).hasMatch(m[3]!)) return null;
  final word = m[1]!.toLowerCase();
  final kind = word.startsWith('ch')
      ? 'chapter'
      : word.startsWith('ep')
          ? 'episode'
          : word == 'pt'
              ? 'part'
              : word;
  return (kind, RegExp(r'\d+').allMatches(m[2]!).map((x) => int.parse(x[0]!)).toList());
}

/// The version itself, without a leading label: "Part 8 v0.114" → "v0.114".
String _numberedPart(String version) {
  final v = version.trim();
  if (RegExp(r'^v?\.?\d', caseSensitive: false).hasMatch(v)) return v;
  final tagged = RegExp(r'\bv\.?\d[\w.]*', caseSensitive: false).firstMatch(v);
  return tagged?.group(0) ?? v;
}

/// The status the library shows and filters on.
///   • A status the user picked wins — except Playing and On Hold show as
///     Updated when a newer version arrives, so a game parked waiting for an
///     update surfaces when it lands (and returns once it's played).
///   • Otherwise it's detected: Unplayed, Skimmed, Updated, or Playing.
GameStatus effectiveGameStatus(GameGroup g, UserData ud) {
  final picked = GameStatus.fromId(ud.status[g.baseKey]);
  final detected = detectedGameStatus(g, ud);
  if (picked == null) return detected;
  if (detected == GameStatus.updated &&
      (picked == GameStatus.playing || picked == GameStatus.onHold)) {
    return GameStatus.updated;
  }
  return picked;
}

/// The status without the user's pick: Unplayed, Skimmed, Updated, or
/// Playing. Skimmed comes before Updated — an update to a game you only
/// skimmed isn't news.
GameStatus detectedGameStatus(GameGroup g, UserData ud) {
  if (!isGamePlayed(g, ud)) return GameStatus.unplayed;
  if (looksSkimmed(g)) return GameStatus.skimmed;
  return hasUpdateSinceLastPlayed(g, ud) ? GameStatus.updated : GameStatus.playing;
}
