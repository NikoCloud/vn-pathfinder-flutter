# Feature Backlog

Everything VN Pathfinder has promised or planned that isn't fully in the app yet. Nothing here has been dropped. These are all candidates to build.

Checked against the code on 2026-10-31. Sources: every past version of the README, the Settings screens, the design mockup in `mockup/`, the published 1.0 feature list and the developer notes. The last README with the old roadmap is in git at `6f0f566:README.md`.

Bugs and requests from daily use are in [GitHub Issues](https://github.com/NikoCloud/vn-pathfinder-flutter/issues). Bug fixes and cleanup are tracked in `PROGRESS.md` → Phase 17. What has shipped is in `CHANGELOG.md`.

## Partly done

These are in the app, but something is still missing.

| Item | What's in | What's left |
|------|-----------|-------------|
| **Ratings** | F95Zone and VNDB ratings are saved, shown on the game page and on hover, and can be sorted and filtered | LewdCorner's Latest Updates data has `rating`, `rating_count`, `view_count` and `like_score`, but none of the 87 games checked had a rating. F95Zone's `views`, `likes` and `watched` aren't used yet |
| **Installer** | `installer/vn_pathfinder.iss` compiles through `tool/package_windows.ps1`. Install, shortcuts, launch, installing over the top and uninstalling all work, and uninstalling leaves app data alone | Those checks ran silently, so the wizard's pages still need clicking through by hand. It isn't code-signed, so Windows SmartScreen will warn people who download it. It doesn't check for the WebView2 Runtime |
| **Light theme** | Every screen follows the theme | The light colors haven't had a design review |

## Listed as done in older READMEs

Older READMEs marked these as finished or in the app. They aren't.

- **Accessibility.** The shared controls have labels, focus rings and keyboard use, and the app honours Windows' animation setting. Older dialogs (Settings, Properties, Fetch Metadata, Archive) haven't been through this yet.
- **Tablet and responsive layouts.** Described as a benefit of the rewrite, never built as a feature.

## Planned features

Never built.

- **Mute a developer.** Muting works per game today.
- **The rest of the Archive redesign.** Cards are in. The extraction banner, queue sections and table still have the old layout, and NikoCloud has that on the back burner.
- **7z archives.** They're listed but can't be extracted, though 7-Zip could do it.
- **Clearing saved game data nothing uses.** A card whose file was deleted in Explorer stays in `.vnpf-archives` so it can be assigned again.
- **Snap Layouts on the maximize button.** The custom title bar loses the Windows 11 flyout. It needs a native hit-test change in the runner. Edge snapping and Win+Z work.
- **Discord in the Feed.** Settings shows it as Coming soon. It needs an easier setup than a personal bot token, typed channel lines and a bot invited to every server. The first version is in git at `a23b0b8`.
- **Backend API.** Supabase plus a VNDB mirror, as a fallback when sources are down.
- **Mod manager integration.** ModDB and Nexus.
- **Community mod sharing.**
- **Localization.** Japanese, Russian and others.
- **Patch toggles on the game page.** Patches stay in Properties for now.
- **Direct update checks for LewdCorner and Azkosel's Corner.** They only come through the Feed today. LewdCorner's Latest Updates data could look up a whole tier, which would catch games that drop out of the 60-game feed.
- **A LewdCorner tier filter in the Feed.** The data supports All, Standard, Plus, AI and AI+.
- **Follow MEGA downloads made through the MEGA desktop app.** The page hands the link straight to that app, so the browser never sees a download. Updates to a game you own already show its art. For a new game, a file landing in the library while a Get is open could be matched to that game and keep its data.
- **Resume a stopped download.** The browser retries a dropped download by itself, 5 times, resuming only if the host allows it and otherwise starting from zero, which is costly on hosts with a daily limit. Once it gives up, the file is gone. WebView2 has `CanResume` and `Resume` on the download operation for a Resume button.
- **Staging folder.** A folder you choose on a fast drive, apart from where your games are stored. A game unpacks there so you can play it right away, then moves to storage in the background while you're doing something else, such as playing another game. It suits a library that's slow to reach, like a NAS or a hard drive, and a system with a small fast drive and plenty of slower storage. It never moves a game that's running, and an archive stays put until its game has finished moving, so a disconnected drive loses nothing. It needs a second library location (`libraryDir` is used across 11 files), a move queue that survives a crash, free-space checks, and a plan for games on a drive that's been unplugged. Play data follows the game, but custom art stores a full path and would need updating.
- **Fix wrong saved forum links.** Older auto-picks saved some links to a different game, which can affect update alerts. A check of 219 links found about seven suspects. Fetch Metadata could flag a thread whose title or developer doesn't match.

## Platforms

- **macOS 11+** (Intel and Apple Silicon) and **Linux** (GTK 3+). The repo only has a Windows project, and `webview_windows` needs replacing with a cross-platform browser such as `flutter_inappwebview`.
- **iOS and Android.** Planned for 3.0 or later.
- **Cross-platform testing** once those builds exist.

## Release and community

- **Publish a Windows build.** `v0.9.0` is a source tag with no GitHub Release. The packaging script makes a portable ZIP and an installer, but nothing has been published.
- **Settle the version number.** The tag says `0.9.0`, `pubspec.yaml` says `2.0.0+1`, and the app calls itself `2.0.0-alpha`.
- **Beta release** and **community beta testing.**
- **Talk to every provider about the app.** This is why the Feed stays neutral between sources.
- **Accessibility audit.**
- **Performance profiling.**
- **More automated tests.**
