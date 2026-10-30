# Changelog

What's in each version of VN Pathfinder 2.0, newest first.

No downloadable 2.0 build has been published yet. Tagged versions are source snapshots.

## Unreleased

On `master`, not yet tagged.

### Added

- **Game status.** Every game gets a status detected from its save files and play history: Unplayed, Playing, Updated or Skimmed. Pick Playing, On Hold, Completed, Skimmed, Abandoned or Unplayed yourself from the game banner or the right-click menu, or set it back to Auto.
- **Update alerts.** A badge marks games with a newer version on F95Zone, and the version chip opens the game's thread. A new filter shows only those games. Turn it on with Game Update Checks in Settings → Network.
- **Unfetched filter.** Shows the games that have no saved metadata yet, so you can see what still needs fetching.
- **Feed tab.** Latest updates from F95Zone, LewdCorner, Azkosel's Corner and Discord channels, with duplicates removed and a filter for each source.
- **Azkosel's Corner** as a metadata source and forum login.
- **Archive panel.** Extraction progress, an indicator for archives you've already extracted, and delete options.
- **Version-aware extraction.** The extracted game is named from the best of the archive's name and the folder inside it, and that folder is flattened so the game is detected correctly.

### Changed

- Versions look the same everywhere and sort sensibly: Demo, then numbered versions, then Final, with alpha, beta and rc before the full release.
- Folder names can separate a dotted version with a space, as in `Game v0.8`.
- A newly installed version keeps the fetched title, developer, synopsis and tags from the older one.
- Last Played now counts save files as well as launches from the app.
- Library scans run in the background, so the window stays responsive.
- The embedded browser only runs while it's needed, which lowers idle memory use.

### Fixed

- Metadata fetching after the F95Zone, LewdCorner and Azkosel's Corner redesigns: titles, developers, synopses and images are read correctly again.
- Failed searches now say why ("Not logged in", "Blocked by a Cloudflare check") instead of showing "No results found".
- The first search after opening Fetch Metadata no longer fails.
- LewdCorner images now download, and their previews load in Fetch Metadata.
- New images appear right after Fetch Metadata, without a restart.
- The hidden browser now closes when Fetch Metadata closes.
- Long text no longer overflows in Game Properties or in the Fetch Metadata results.

## 0.9.0 - 2026-04-18

First tagged 2.0 version. Source only, no downloadable build.

### Added

- Library with folder scanning, list and grid views, search, tag filters and sorting.
- Game details with a cover and screenshot carousel, full-screen preview, notes and tags.
- Game launching with playtime tracking.
- Game Properties, including name, launch options, custom art and mods.
- Fetch Metadata from VNDB, F95Zone, LewdCorner and itch.io, with each field pickable from a different source.
- Forum logins through an embedded browser, including sites behind Cloudflare.
- Archive screen for browsing and extracting ZIP and RAR files.
- Add Game, orphan cleanup and automatic user data backups.
- Settings, right-click menus and notifications.
