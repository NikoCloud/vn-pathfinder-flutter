# VN Pathfinder

A visual novel library manager for Windows. It finds the games in your library folder, keeps every version of a game together, fetches covers and details from the forums, manages mods, and tells you when a game has an update.

> **Release status:** VN Pathfinder 2.0 is in pre-release and has no downloadable build yet, so for now you [build it from source](#build-from-source). The latest tagged version is `v0.9.0`. Everything added since then is listed under [Unreleased](CHANGELOG.md#unreleased).
>
> Want something ready to run today? The previous Python version is available as [VN Pathfinder v1.1.0-beta](https://github.com/NikoCloud/VN-Pathfinder/releases/tag/v1.1.0-beta).

## Features

### Library

- Finds Ren'Py games and other Windows games in your library folder
- Groups every installed version of a game under one entry
- List and grid views with cover art and screenshots
- Search by title or creator
- Filter by tags, engine, status, available updates or Unfetched
- Sort by title, recently played or date added
- Tracks playtime, play count and last played
- Add your own notes, tags and cover art
- Set launch options for each game
- Automatic backups of your user data

### Game status

Every game gets a status automatically, based on its save files and play history:

| Status | Meaning |
|--------|---------|
| **Unplayed** | No saves or tracked playtime |
| **Playing** | You've played it |
| **Updated** | A newer version is installed than the one you played |
| **Skimmed** | Only autosaves, with no manual saves or quicksaves |

Set a status yourself from the game banner or the right-click menu. You can also pick **On Hold**, **Completed** or **Abandoned**. Choosing **Auto** hands the game back to detection.

### Update alerts

- A badge marks games with a newer version on F95Zone
- The version chip opens the game's thread so you can download it
- A filter shows only games with an update
- Checks run when your library loads, at most once every 6 hours

Games are matched by forum thread, using the link saved by Fetch Metadata. Games without a link are matched by exact title. LewdCorner and Azkosel's Corner updates are picked up from the Feed for games with a saved link to that forum.

### Metadata

- Fetch details and images from **VNDB**, **F95Zone**, **LewdCorner**, **itch.io** and **Azkosel's Corner**
- Take each field from a different source in one step
- Log in to the forums through the built-in browser, including sites behind Cloudflare
- The **Unfetched** filter shows games with no saved metadata yet

### Archives and mods

- Browse the ZIP, RAR, RPA and RPY files in your library folder
- Extract ZIP and RAR archives from inside the app
- Extracted games are named from the best of the archive's name and the folder inside it
- Turn mods on and off without deleting them, separately for each game version
- Find leftover files and folders with the orphan cleanup tool

### Feed

- Latest updates from **F95Zone**, **LewdCorner**, **Azkosel's Corner** and **Discord** channels
- Removes duplicates across sources, or filter by one source
- Refreshes every 6 or 12 hours, or only when you ask
- Cards are text-only so that no source gets more attention than another

## Requirements

- Windows 10 or 11, 64-bit (developed and tested on Windows 11)
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) for forum logins and fetching (included with Windows 11)
- [7-Zip](https://www.7-zip.org/) to extract RAR archives

## Getting started

1. Open **Settings → General** and choose your library folder.
2. Lockdown Mode is on by default, so the app stays offline. To use online features, turn it off in **Settings → Network**.
3. In **Settings → Network**, log in to the forums you use.
4. Select a game and choose **Fetch Metadata**.
5. Turn on **Game Update Checks** in **Settings → Network** to get update alerts.

## Privacy

- **Offline by default.** Nothing goes online until you turn off Lockdown Mode.
- **No accounts, telemetry or analytics.**
- **Your data stays on your PC.** App data is in `%APPDATA%\VN Pathfinder\`, and each game's metadata and images are in a `.vnpf` folder inside the game.
- **The app only contacts the services you use.** Fetch Metadata and the Feed contact the sites you've chosen. Update checks send F95Zone the forum thread IDs of your games, plus title searches for games without a saved link. To stop that, turn off Game Update Checks.
- **Stored without encryption.** Forum sessions and your Discord bot token are kept on your PC as plain files.

## Known issues

- Some switches in Settings don't do anything yet: Update Checks, Metadata Scraping, Site Logins, Download Page Links and Simultaneous Extractions. To keep the app offline, use Lockdown Mode.
- The light theme, accent color and font size settings only partly apply.
- The READ, WRITE and DISK figures shown during extraction aren't real measurements.
- The LewdCorner feed doesn't load at the moment because the site now rejects that request. LewdCorner metadata and images still work.
- Update checks ask F95Zone directly. LewdCorner and Azkosel's Corner updates only show up through the Feed.
- Failed searches report an error but aren't retried.
- ZIP extraction loads the whole archive into memory, so very large games can use a lot of RAM.
- Windows only for now. macOS and Linux need a different built-in browser.

## Roadmap

Planned, in no fixed order:

- A published Windows build and a public beta
- Game ratings, with sorting and filtering
- Library statistics
- Filtering by release date
- Reordering gallery images
- Automatic retries for failed searches
- One consistent card format in the Feed
- A backup metadata service for when sources are down
- macOS and Linux versions
- System tray support
- Mod manager integration and community mod sharing
- Translations
- In-app help
- Better keyboard navigation and accessibility
- iOS and Android, after 2.0

The full list, including the VN Pathfinder 1.0 features still to bring across, is in the [feature backlog](docs/dev/BACKLOG.md).

## Build from source

You'll need:

- [Flutter](https://flutter.dev/docs/get-started/install) 3.41.6
- Visual Studio 2022 with the **Desktop development with C++** workload
- Windows Developer Mode turned on

```bash
git clone https://github.com/NikoCloud/vn-pathfinder-flutter.git
cd vn-pathfinder-flutter
flutter pub get
flutter build windows --release
```

The app is built to `build\windows\x64\runner\Release\vn_pathfinder.exe`.

Run the tests with `flutter test`. Developer notes are in [docs/dev](docs/dev).

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/NikoCloud/vn-pathfinder-flutter/issues).

## License

Apache License 2.0. See [LICENSE](LICENSE).
