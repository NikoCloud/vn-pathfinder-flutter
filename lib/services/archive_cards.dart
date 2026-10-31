import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/feed_item.dart';
import '../models/game_group.dart';
import '../models/game_version.dart';
import 'metadata_service.dart';
import 'scanner_service.dart';

/// The game a patch file is probably for, from its name: the longest shared
/// start of the two names, or the game's name anywhere inside the file's.
GameGroup? guessPatchGame(String fileStem, Iterable<GameGroup> groups) {
  String plain(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final stem = plain(fileStem);
  GameGroup? best;
  var bestScore = 0;
  for (final g in groups) {
    if (g.versions.isEmpty) continue;
    final key = plain(g.baseKey);
    if (key.isEmpty) continue;
    var score = 0;
    while (score < stem.length && score < key.length && stem[score] == key[score]) {
      score++;
    }
    if (stem.contains(key) && key.length > score) score = key.length;
    if (score > bestScore) {
      bestScore = score;
      best = g;
    }
  }
  return bestScore >= 4 ? best : null;
}

/// Ren'Py patch files, which work dropped straight into `game/`.
const patchExtensions = {'.rpa', '.rpy', '.rpyc', '.py'};

/// An archive of nothing but patch files, at most one folder deep, can go in
/// as loose files. Anything more has a structure of its own, so it stays
/// together as one folder.
bool isLoosePatchSet(Iterable<String> relativePaths) {
  return relativePaths.isNotEmpty &&
      relativePaths.every((path) {
        final parts = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
        return parts.length <= 2 && patchExtensions.contains(p.extension(path).toLowerCase());
      });
}

bool _taken(String name, Directory dir) =>
    File(p.join(dir.path, name)).existsSync() || Directory(p.join(dir.path, name)).existsSync();

/// [name], or with _2, _3 and so on if [dir] already has it.
String freeName(String name, Directory dir) {
  if (!_taken(name, dir)) return name;
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var i = 2;
  while (_taken('${stem}_$i$ext', dir)) {
    i++;
  }
  return '${stem}_$i$ext';
}

/// Moves an unpacked patch from [unpacked] into [patchesDir] and returns the
/// names it's stored under, which is what the Patches tab toggles. Loose patch
/// files go in one by one. Anything else stays together as one folder called
/// [folderName], so a mod keeps its images and folders. [chooseName] is asked
/// when that name is taken, and null calls it off.
Future<List<String>> storeUnpackedPatch(
  Directory unpacked,
  Directory patchesDir, {
  required String folderName,
  required Future<String?> Function(String taken) chooseName,
}) async {
  final files = unpacked.listSync(recursive: true).whereType<File>().toList();
  if (files.isEmpty) throw 'The archive contains no files.';

  if (isLoosePatchSet(files.map((f) => p.relative(f.path, from: unpacked.path)))) {
    return [
      for (final file in files)
        () {
          final name = freeName(p.basename(file.path), patchesDir);
          file.renameSync(p.join(patchesDir.path, name));
          return name;
        }(),
    ];
  }

  var name = folderName;
  if (_taken(name, patchesDir)) {
    final chosen = await chooseName(name);
    if (chosen == null) throw 'Not assigned: a patch named $name already exists.';
    name = chosen;
  }
  final dest = p.join(patchesDir.path, name);
  final entries = unpacked.listSync();
  if (entries.length == 1 && entries.first is Directory) {
    // One top folder: use it directly, so it isn't nested twice.
    entries.first.renameSync(dest);
  } else {
    Directory(dest).createSync();
    for (final entry in entries) {
      entry.renameSync(p.join(dest, p.basename(entry.path)));
    }
  }
  return [name];
}

/// What the app knows about a game while it's only an archive. Everything is
/// laid out the way a game folder is, with a `.vnpf` folder inside, so Fetch
/// Metadata's save and image code works on it and extracting just moves that
/// `.vnpf` into the game. The game then arrives already fetched.
///
/// It lives in `<library>\.vnpf-archives\<id>`. The scanner and Orphans skip
/// dot-folders, and it travels with the library.
class ArchiveCards {
  static const folderName = '.vnpf-archives';
  static const _linkFile = 'archive.json';

  static Directory root(String library) => Directory(p.join(library, folderName));

  /// Every saved card in [library], linked or not.
  static List<ArchiveCard> all(String library) {
    final dir = root(library);
    if (!dir.existsSync()) return const [];
    final cards = <ArchiveCard>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final card = ArchiveCard.read(entry);
      if (card != null) cards.add(card);
    }
    return cards;
  }

  /// A card for [fileName], before its images arrive.
  static Future<ArchiveCard> create(String library, String fileName, ArchiveCardDraft draft) async {
    final folder = _newFolder(library);
    await saveGameMetadata(folder, draft.metadata);
    final card = ArchiveCard(folder, fileName: fileName, version: draft.version, nameHint: draft.nameHint);
    card._write();
    return ArchiveCard.read(folder) ?? card;
  }

  /// A card for [fileName] holding a copy of a game's data, for an archive
  /// that's a version of a game you have.
  static Future<ArchiveCard> fromGame(
    String library,
    String fileName,
    GameVersion source, {
    required String version,
    required String nameHint,
  }) async {
    final folder = _newFolder(library);
    final vnpf = Directory(p.join(folder.path, '.vnpf'))..createSync(recursive: true);
    final from = Directory(p.join(source.folderPath.path, '.vnpf'));
    if (from.existsSync()) {
      for (final file in from.listSync().whereType<File>()) {
        await file.copy(p.join(vnpf.path, p.basename(file.path)));
      }
    }
    final card = ArchiveCard(folder, fileName: fileName, version: version, nameHint: nameHint);
    card._write();
    return ArchiveCard.read(folder) ?? card;
  }

  static Directory _newFolder(String library) {
    final folder = Directory(p.join(root(library).path, '${DateTime.now().microsecondsSinceEpoch}'));
    folder.createSync(recursive: true);
    return folder;
  }
}

/// The saved data for one archive.
class ArchiveCard {
  final Directory folder;

  /// The archive this belongs to, by name. Empty once it's been unlinked.
  final String fileName;
  final String version;

  /// The name to extract under, so an update lands in the game it belongs to.
  final String nameHint;
  final Map<String, dynamic> metadata;

  const ArchiveCard(
    this.folder, {
    required this.fileName,
    this.version = '',
    this.nameHint = '',
    this.metadata = const {},
  });

  static ArchiveCard? read(Directory folder) {
    final link = File(p.join(folder.path, ArchiveCards._linkFile));
    if (!link.existsSync()) return null;
    try {
      final json = jsonDecode(link.readAsStringSync()) as Map<String, dynamic>;
      return ArchiveCard(
        folder,
        fileName: json['file'] as String? ?? '',
        version: json['version'] as String? ?? '',
        nameHint: json['name_hint'] as String? ?? '',
        metadata: loadGameMetadata(folder),
      );
    } catch (_) {
      return null;
    }
  }

  String get title => metadata['title'] as String? ?? '';
  String get developer => metadata['developer'] as String? ?? '';
  List<String> get tags => (metadata['tags_fetched'] as List?)?.map((t) => '$t').toList() ?? const [];

  Directory get vnpf => Directory(p.join(folder.path, '.vnpf'));

  String? get cover {
    for (final name in ['cover.jpg', 'cover.png', 'cover.webp']) {
      final file = File(p.join(vnpf.path, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  void _write() {
    File(p.join(folder.path, ArchiveCards._linkFile)).writeAsStringSync(jsonEncode({
      'file': fileName,
      'version': version,
      'name_hint': nameHint,
    }));
  }

  /// This card, now belonging to [name]. Empty unlinks it, and it waits to be
  /// assigned to a file again.
  ArchiveCard linkTo(String name) {
    final card = ArchiveCard(folder, fileName: name, version: version, nameHint: nameHint, metadata: metadata);
    card._write();
    return card;
  }

  /// The folder to extract to: the game's real name, not the archive's or the
  /// folder inside it, which can be anything. Null without a version, because
  /// a folder name needs one to sort.
  String? get extractName {
    final name = nameHint.isNotEmpty ? nameHint : title;
    if (name.isEmpty || version.isEmpty) return null;
    // Titles can hold characters Windows won't take in a folder name.
    return '$name-$version'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(RegExp(r'[. ]+$'), '').trim();
  }

  /// Hands the data to an extracted game folder. A game that arrived with its
  /// own `.vnpf` keeps it.
  void moveInto(Directory gameFolder) {
    final target = Directory(p.join(gameFolder.path, '.vnpf'));
    if (vnpf.existsSync() && !target.existsSync()) vnpf.renameSync(target.path);
    delete();
  }

  void delete() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }
}

/// A card's contents, gathered before the download starts.
class ArchiveCardDraft {
  final Map<String, dynamic> metadata;
  final String version;
  final String nameHint;
  final String coverUrl;
  final List<String> screenshotUrls;
  final Map<String, String> previewUrls;

  const ArchiveCardDraft({
    required this.metadata,
    this.version = '',
    this.nameHint = '',
    this.coverUrl = '',
    this.screenshotUrls = const [],
    this.previewUrls = const {},
  });

  /// A copy with these images, for tests and callers that have their own.
  ArchiveCardDraft withImages(String cover, List<String> screenshots) => ArchiveCardDraft(
        metadata: metadata,
        version: version,
        nameHint: nameHint,
        coverUrl: cover,
        screenshotUrls: screenshots,
        previewUrls: previewUrls,
      );

  /// From what the Feed and the thread say. The thread knows more, so it wins
  /// where it has an answer. The link is always the thread the file came from.
  factory ArchiveCardDraft.build({
    required String title,
    required String version,
    required String source,
    required String threadUrl,
    String nameHint = '',
    RawFeedItem? item,
    MetadataResult? details,
  }) {
    String best(String thread, String? feed) => thread.isNotEmpty ? thread : feed ?? '';

    final meta = details?.toMetadataJson() ?? <String, dynamic>{};
    meta['title'] = title;
    void put(String key, String value) {
      if (value.isNotEmpty) meta[key] = value;
    }

    put('developer', best(details?.developer ?? '', item?.developer));
    put('synopsis', best(details?.synopsis ?? '', item?.overview));
    final tags = (details?.tags.isNotEmpty ?? false) ? details!.tags : item?.tags ?? const <String>[];
    if (tags.isNotEmpty) meta['tags_fetched'] = tags;
    final rating = (details?.rating ?? 0) > 0 ? details!.rating : item?.rating ?? 0;
    if (rating > 0) meta['rating'] = rating;
    meta['source_url'] = threadUrl;
    final link = const {'f95zone': 'f95_url', 'lewdcorner': 'lc_url', 'azc': 'azc_url'}[source];
    if (link != null) meta[link] = threadUrl;

    return ArchiveCardDraft(
      metadata: meta,
      version: version,
      nameHint: nameHint,
      coverUrl: best(details?.coverUrl ?? '', item?.coverUrl),
      screenshotUrls: details?.screenshotUrls ?? const [],
      previewUrls: details?.previewUrls ?? const {},
    );
  }
}
