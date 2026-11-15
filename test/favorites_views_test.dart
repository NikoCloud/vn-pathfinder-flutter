// Favorites and adding games to Library views. Invented games throughout.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_pathfinder/models/game_group.dart';
import 'package:vn_pathfinder/models/game_version.dart';
import 'package:vn_pathfinder/models/user_data.dart';
import 'package:vn_pathfinder/providers/filter_provider.dart';
import 'package:vn_pathfinder/providers/library_provider.dart';
import 'package:vn_pathfinder/screens/library_screen.dart' show activeView;

GameGroup _game(String key) => GameGroup(
      baseKey: key,
      displayName: key,
      versions: [
        GameVersion(
          folderName: '$key-1.0',
          folderPath: Directory(key),
          baseKey: key,
          versionStr: '1.0',
          displayName: key,
          localSaveDir: Directory('saves'),
        ),
      ],
    );

class _Library extends LibraryNotifier {
  _Library(super.ref, List<GameGroup> groups) {
    state = LibraryState(groups: groups);
  }
}

class _UserData extends UserDataNotifier {
  _UserData(super.ref, UserData data) : super(initial: data);
  @override
  Future<void> save() async {}
}

ProviderContainer _library([UserData data = const UserData()]) {
  final c = ProviderContainer(overrides: [
    libraryProvider.overrideWith((ref) => _Library(ref, [_game('lantern'), _game('harbour'), _game('meadow')])),
    userDataProvider.overrideWith((ref) => _UserData(ref, data)),
  ]);
  addTearDown(c.dispose);
  return c;
}

List<String> _shown(ProviderContainer c) => c.read(filteredGroupsProvider).map((g) => g.baseKey).toList();

void main() {
  group('saved data', () {
    test('games tagged "Favorite" before favourites existed become favourites once', () {
      final old = UserData.fromJson({
        'tags': {
          'lantern': ['Romance', 'Favorite'],
          'harbour': ['favorite '],
          'meadow': ['Short'],
        },
      });
      expect(old.favorites, {'lantern', 'harbour'});

      // Once saved, the list is what it is: un-favouriting sticks.
      final later = UserData.fromJson({
        'favorites': ['lantern'],
        'tags': {
          'harbour': ['Favorite'],
        },
      });
      expect(later.favorites, {'lantern'});
    });

    test('favourites and view games survive a save', () {
      const data = UserData(favorites: {'lantern'}, viewGames: {'Watch list': ['harbour', 'meadow']});
      final back = UserData.fromJson(data.toJson());
      expect(back.favorites, {'lantern'});
      expect(back.viewGames, {'Watch list': ['harbour', 'meadow']});
    });
  });

  group('adding games', () {
    test('Favorites and a view each hold their own games', () {
      final c = _library();
      final ud = c.read(userDataProvider.notifier);
      ud.addToList(kFavoritesList, ['lantern']);
      ud.addToList('Watch list', ['harbour', 'meadow']);
      ud.addToList('Watch list', ['harbour']); // already there: no duplicate
      expect(c.read(userDataProvider).favorites, {'lantern'});
      expect(c.read(userDataProvider).viewGames['Watch list'], ['harbour', 'meadow']);
      expect(ud.inList('Watch list', 'meadow'), isTrue);

      ud.removeFromList('Watch list', 'meadow');
      ud.removeFromList(kFavoritesList, 'lantern');
      expect(c.read(userDataProvider).viewGames['Watch list'], ['harbour']);
      expect(c.read(userDataProvider).favorites, isEmpty);

      ud.forgetView('Watch list');
      expect(c.read(userDataProvider).viewGames.containsKey('Watch list'), isFalse);
    });
  });

  group('showing a list', () {
    test('Favorites shows exactly the favourites, and no built-in view is highlighted', () {
      final c = _library(const UserData(favorites: {'harbour'}));
      c.read(filterProvider.notifier).showList(kFavoritesList);
      expect(_shown(c), ['harbour']);
      expect(activeView(c.read(filterProvider)), isNull);

      // Picking a built-in view leaves the list.
      c.read(filterProvider.notifier).setView();
      expect(_shown(c).length, 3);
    });

    test("a view with games added shows exactly those, whatever its saved filters", () {
      final c = _library(const UserData(viewGames: {'Watch list': ['meadow', 'lantern']}));
      c.read(filterProvider.notifier).showList('Watch list');
      expect(_shown(c)..sort(), ['lantern', 'meadow']);
      // A saved view's own filters never carry the list.
      expect(c.read(filterProvider).toJson().containsKey('list'), isFalse);
    });
  });
}
