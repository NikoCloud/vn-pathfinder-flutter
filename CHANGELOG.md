# Changelog

What's in each version of VN Pathfinder 2.0, newest first.

No downloadable 2.0 build has been published yet. Tagged versions are source snapshots.

## Unreleased

On `master`, not yet tagged.

### Added

- **New look.** Midnight Edition is the default theme and Paperback is the light one, with wide art-led cards, serif titles and one set of controls across the app. The page takes on the colour of the art you point at.
- **Home tab.** Continue playing with your last save, your other recent games, new versions, new Feed releases and what's ready to play.
- **Game page.** One page for every game, owned or found on the Feed, with a version path and what changed in each version when the thread lists it.
- **Rebuilt Feed.** A Spotlight, shelves for new games, updates, complete games, your games and the games you're watching, day groups, search, filters by site and tag, cards or a list, and Mark all seen. Every card always shows how long ago the release went out. Every site gets the same card and covers are back, because every site now provides one.
- **Downloads from the Feed.** Pick a site, platform and file host and the site's own page opens in the app. The file lands in your library, gets extracted and shows up ready to play.
- **Games arrive already fetched.** A Feed download saves the game's cover, screenshots, description, tags and thread link beside the file, and they move into the game when it's extracted.
- **Archive cards.** Feed downloads and files that match a game you have show as cards with their art. Other files stay plain rows.
- **Assign to game data.** Assign can link a file to saved game data, for example after renaming a download, or give it a copy of a game's data.
- **Delete Archive** in a game's right-click menu.
- **Watch and Mute** for games on the Feed.
- **Quick views and saved views** in the Library, plus select-many to fetch metadata, set a status or hide.
- **Quick find.** Ctrl+K finds any game in your library or on the Feed.
- **Discreet.** Ctrl+Shift+D, or the eye in the title bar, blurs all art.
- **Save previews.** Home shows the picture from your last save.
- **Play time by week** in Stats, from a session log that starts with this version.
- **Hidden games.** Hide from Library replaces Remove from Library, and a filter brings them back.
- **Game status.** Every game gets a status detected from its save files and play history: Unplayed, Playing, Updated or Skimmed. Pick Playing, On Hold, Completed, Skimmed, Abandoned or Unplayed yourself from the game banner or the right-click menu, or set it back to Auto.
- **Update alerts.** A badge marks games with a newer version on F95Zone, and the version chip opens the game's thread. A new filter shows only those games.
- **Unfetched filter.** Shows the games that have no saved metadata yet, so you can see what still needs fetching.
- **Merge games.** Right-click a game and choose Merge into Another Game when two entries are really one game. Likely matches are listed first, your game files stay where they are, new versions join automatically, and Properties → Versions can separate them again.
- **Feed tab.** Latest updates from F95Zone, LewdCorner and Azkosel's Corner, with duplicates removed and a filter for each source. Discord channels are coming in a later release, and Settings marks them as coming soon.
- **Azkosel's Corner** as a metadata source and forum login.
- **Archive panel.** Extraction progress, an indicator for archives you've already extracted, and delete options.
- **Version-aware extraction.** The extracted game is named from the best of the archive's name and the folder inside it, and that folder is flattened so the game is detected correctly.
- **Ratings.** F95Zone and VNDB ratings are saved with each game and shown on its page. Sort by rating, or filter to 3 or 4 stars and up.
- **Stats tab.** Totals, playtime, games by status and engine, most-played games and top developers.
- **Resizable layout.** Drag the divider beside the game list. Double-click to reset.
- **Sort by developer** and a filter for games released in the last year.
- **Gallery editing.** Reorder, add and remove images in Properties → Art, or set any of them as the cover. A Change Image button on the art takes you there.
- **Image picker in Fetch Metadata.** Click any image to make it the cover, or remove the ones you don't want.
- **Tags** with built-in presets. Add a tag and choose Keep as a preset to reuse it.
- **Duplicate prompts.** A game's page offers to merge when another entry looks like the same game. Choosing Not a duplicate stops the prompt.
- **Keyboard shortcuts.** Up and Down move through the list, Enter plays, F1 opens help, and Left, Right and Esc work in the full-screen image view.
- **In-app help.** Open it with F1 or the Help button.
- **Minimize to tray.** Turn it on in Settings → General.
- **VN Pathfinder update check.** A notification tells you when a newer release is on GitHub.
- **Clean Up** in the Archive tab lists extracted archives so you can delete the ones you pick, and an **Orphans** button opens the cleanup tool.
- **Rename prompt** when a mod's name is already taken, instead of adding `_2` to it.
- **Packaging script** that builds a portable ZIP, plus an installer script for Inno Setup.

### Changed

- Assign has a search box and guesses the game from the file's name.
- A mod with its own folders or images now stays whole when assigned, instead of being refused. Extra files are no longer thrown away.
- Clean Up shows its total on the button, has Select all and Select none, and includes archives whose version is already in your library however they got there.
- An archive being extracted can't be deleted.
- The title bar is part of the app now: tabs, Find, Discreet, the network state and the window buttons in one bar. The old navbar and status bar are gone, and Rescan moved to the Library toolbar.
- Lockdown Mode switches from the title bar with one click.
- All fonts ship with the app, so nothing is fetched to draw text, even with Lockdown off.
- Nothing is set smaller than 11 pixels, labels are in sentence case, and emoji are replaced with icons.
- The hero art moves through a game's images at the Slideshow Interval, replacing the screenshot carousel.
- The Feed reads the full post from forum feeds, takes the developer from the thread title instead of showing who posted it, and keeps a newer version on another site instead of hiding it as a duplicate.
- The first refresh after updating replaces saved LewdCorner and Azkosel's Corner rows, which had no covers.
- When a site fails, the Feed says so and keeps what it already had.
- **A release is now a new version, not a new date.** LewdCorner re-dates a thread when its first post is edited, and Azkosel's Corner's feed follows the latest reply, so old releases kept returning to the top. The Feed now remembers each thread's version and keeps its date until the version changes. F95Zone's dates held up in every check and are used as they are.
- New LewdCorner threads keep their post date and stay marked New after their first edit.
- Azkosel's Corner cards take their date from the thread's first post, read once per version. The first refresh after updating opens about 40 threads, spaced out, and saved Azkosel's Corner rows are replaced.
- **The Feed catches up after time away.** Each site's list is read page by page back to where it left off, up to 10 days, with 5 seconds between pages. If a site stops answering, what was read stays and the next refresh continues from there.
- The Feed refreshes every 6 hours by default. A saved choice is kept.
- Game update checks wait for a Feed refresh to finish, so the two don't reach F95Zone at once.
- Lockdown stops a Feed refresh instead of showing a false "updated".
- Open Saves Folder goes straight to the folder the game uses.
- The Fetch Metadata source tabs are no longer cut off, and under Lockdown the dialog says the search is off.
- Versions look the same everywhere and sort sensibly: Demo, then numbered versions, then Final, with alpha, beta and rc before the full release.
- Folder names can separate a dotted version with a space, as in `Game v0.8`.
- A newly installed version keeps the fetched title, developer, synopsis and tags from the older one.
- Update checks also run while the app stays open.
- Update checks, metadata fetching and site logins are on by default once Lockdown Mode is off.
- The Feed can refresh every 24 hours.
- Clicking the Lockdown indicator opens Settings.
- Last Played now counts save files as well as launches from the app.
- Library scans run in the background, so the window stays responsive.
- The embedded browser only runs while it's needed, which lowers idle memory use.
- ZIP files now extract as a stream, so very large games no longer load into memory.

### Fixed

- Assigning a patch no longer leaves the file's row behind until the next rescan, and it now says where the patch went.
- Assign no longer offers entries with no installed game, which failed when picked.
- Copy Path in the Archive tab copies the path.
- F95Zone's list no longer fails because of one game. A version sent as a bare number, like 1.5, used to throw away the whole page.
- **Large ZIPs extract without running the PC out of memory.** A compressed file inside a ZIP was held in memory until it finished unpacking, so a game with a big data file could use many gigabytes, slow everything down and fail. Files are now written to disk as they unpack.
- A failed extraction says why, in the Archive tab's banner and on hover.
- A stopped download says why and how many tries it took, and its partial file no longer shows in Archive as ready to extract. Files still downloading stay out of Archive.
- A dropped download stays one download. The browser retries by itself, and each try used to appear as a new download that never finished, on a file whose name kept changing. The dock now says when it's retrying.
- Settings that did nothing now work: Update Checks, Metadata Scraping, Site Logins, Download Page Links and Simultaneous Extractions.
- Light theme, accent color and font size now apply across the whole app, and changing them no longer closes Settings.
- Extraction progress shows measured speed, amount done and time left, replacing made-up figures. Running extractions can be cancelled.
- A damaged ZIP now reports a failed extraction instead of a success.
- Failed searches are retried once.
- The F95Zone feed falls back to the public RSS feed when its usual source fails.
- Folders like `Game A.2.0.7.2` no longer show up as a separate game.
- Metadata fetching after the F95Zone, LewdCorner and Azkosel's Corner redesigns: titles, developers, synopses and images are read correctly again.
- Failed searches now say why ("Not logged in", "Blocked by a Cloudflare check") instead of showing "No results found".
- The first search after opening Fetch Metadata no longer fails.
- F95Zone developer names no longer include Patreon, itch.io and other links. Names you've already fetched are cleaned up too, without fetching again.
- Threads that only list a developer website no longer put that address in the Developer field. The field stays empty so you can use another source.
- A missing cover no longer stops the other images from saving.
- When LewdCorner can't serve a full-size image, Pathfinder tries your other sources for the same game. If there's no confirmed match it saves the public thumbnail and warns you. It won't use images from a source it can't confirm is the same game.
- LewdCorner covers now show in the Fetch Metadata preview instead of a blank tile.
- LewdCorner feed items now show their version, and can trigger update alerts for games with a saved LewdCorner link.
- The LewdCorner feed now holds 60 games instead of 30, and labels Plus games, which need a forum role.
- The LewdCorner feed still loads when you're logged out, using the public Games and AI Games feeds.
- Feed cards no longer show out-of-date text like "NEW 8 hours ago".
- Fetch Metadata lists an exact title match first, so a game's chat thread no longer gets picked instead of the game.
- Fetch Metadata now tells you when a thread hides its images from your account.
- Fetching again without getting a new cover keeps the cover you already had.
- WebP covers now display.
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
