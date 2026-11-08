import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/feed_item.dart';
import '../models/game_group.dart';
import '../models/game_version.dart';

/// Made-up games and releases for the first-run tour. They only ever live in
/// memory: their folders don't exist and nothing about them is saved.

/// A folder that doesn't exist, so nothing can be read from or written to it.
final _nowhere = p.join(Directory.systemTemp.path, 'vn-pathfinder-tour-samples');

const _games = [
  ('Harbor Lights', '0.6', 'Quiet Tide Games', ['romance', 'slice of life']),
  ('The Clockwork Garden', '1.2', 'Gearwhistle', ['mystery', 'fantasy']),
  ('Starfall Station', '0.3.1', 'Lowlight Studio', ['sci-fi', 'drama']),
  ('Paper Lanterns', 'Final', 'Inkwell & Co', ['romance', 'comedy']),
  ('Ironwood Manor', '0.9', 'Oakhall', ['mystery', 'horror']),
  ('Northbound', '2.0', 'Long Road Studio', ['adventure', 'drama']),
];

List<GameGroup> sampleGames() => [
      for (final (title, version, developer, tags) in _games)
        () {
          final key = 'tour-sample-${title.toLowerCase().replaceAll(' ', '-')}';
          return GameGroup(
            baseKey: key,
            displayName: title,
            versions: [
              GameVersion(
                folderName: '$title-$version',
                folderPath: Directory(p.join(_nowhere, key)),
                baseKey: key,
                versionStr: version,
                displayName: title,
                localSaveDir: Directory(p.join(_nowhere, key, 'saves')),
                hasVnpf: true,
                metadata: {
                  'title': title,
                  'developer': developer,
                  'synopsis': 'A sample game for the tour. It isn\'t real, and it disappears when the tour ends.',
                  'tags_fetched': tags,
                },
              ),
            ],
          );
        }(),
    ];

List<RawFeedItem> sampleReleases() {
  final now = DateTime.now();
  RawFeedItem release(String title, String version, String source, int hours, {String kind = ''}) => RawFeedItem(
        id: '$source::tour-sample-$title',
        source: source,
        sourceLabel: source,
        title: title,
        rawBody: [
          'Version: $version',
          'Developer: Sample Studio',
          'Tags: romance, mystery',
          if (kind.isNotEmpty) 'Kind: $kind',
        ].join('\n'),
        url: 'https://example.invalid/tour/${title.toLowerCase().replaceAll(' ', '-')}',
        publishedAt: now.subtract(Duration(hours: hours)),
        channelName: 'Latest Updates',
      );
  return [
    release('Harbor Lights', '0.7', 'f95zone', 2),
    release('Moonlit Ferry', '0.1', 'lewdcorner', 5, kind: 'new'),
    release('Paper Lanterns', 'Final', 'f95zone', 9, kind: 'complete'),
    release('Copper Skies', '0.4', 'lewdcorner', 20),
    release('Glasshouse', '1.0', 'f95zone', 30, kind: 'new'),
  ];
}
