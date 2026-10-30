# Feature Backlog

Everything VN Pathfinder has promised or planned that isn't fully in the app yet. Nothing here has been dropped. These are all candidates to build.

Checked against the code on 2026-10-30. Sources: every past version of the README, the Settings screens, the design mockup in `mockup/`, the published 1.0 feature list and the developer notes. The last README with the old roadmap is in git at `6f0f566:README.md`.

Bug fixes and cleanup are tracked in `PROGRESS.md` → Phase 17. What has shipped is in `CHANGELOG.md`.

## Ratings

Promised in the old README as F95Zone ratings, plus filtering by rating. Not built, but most of the data work is done.

- **What exists:** F95Zone returns a rating out of 5 in the same `latest_data.php` response the Feed and update checks already read. The same response also has `views`, `likes` and `watched`.
- **What's missing:** the rating only appears as text on Feed cards. Nothing saves it to a game or shows it in the library.
- **To build:** save the rating with each game, show it on the game details, then add sorting and filtering. VNDB's API also publishes ratings.

## Looks built but isn't

These appear in the app today but don't do what they say. Users can see them, so they matter most.

| Where | What it says | What actually happens |
|-------|--------------|-----------------------|
| Settings → Network → **Update Checks** | "Check for VN Pathfinder updates on startup" | Saved, never read. The app has no update check for itself. |
| Settings → Network → **Metadata Scraping** | "Fetch game info from F95Zone, LewdCorner, itch.io" | Saved, never read. Turning it off doesn't stop fetching. Only Lockdown Mode does. |
| Settings → Network → **Site Logins** | "Enable authentication to access restricted content" | Saved, never read. Logins work either way. |
| Settings → Network → **Download Page Links** | "Show links to game source pages" | Saved, never read. The source buttons always show. |
| Settings → Archives → **Simultaneous Extractions** | "Number of concurrent extraction jobs" | Saved, never read. Extractions always run one at a time. |
| Settings → Appearance → **Color Theme** | Dark, Light or System | Light changes the page background and default text, but the widgets use 811 fixed dark colors. Only one reads the theme. |
| Settings → Appearance → **Accent Color** | Changes the accent color | Same problem. Most of the app uses the fixed accent. |
| Settings → Appearance → **Font Size** | Changes the text size | Only changes the default text style. Most widgets set their own size. |
| Archives → extraction panel → **READ, WRITE, DISK** | Speed in MB/s and disk use | Made up: file count × 0.5, × 0.3 and × 2. Nothing is measured. |

## Listed as done in older READMEs

Older READMEs marked these as finished or in the app. They aren't.

- **Game stats dashboard** (total games, by developer, playtime). Once marked done, later moved to the future list. Playtime is tracked, but the screen doesn't exist.
- **Drag-to-reorder gallery images.** Once marked done, later moved to the future list.
- **Sort by developer.** Sorting is by title, recently played or date added.
- **F95Zone ratings in fetched metadata.** See [Ratings](#ratings).
- **Feed refresh up to 24 hours.** The options are 6 hours, 12 hours or manual.
- **Better keyboard navigation.** The only shortcut is Ctrl+, for Settings.
- **Accessibility.** Screen reader labels aren't set up.
- **Tablet and responsive layouts.** Described as a benefit of the rewrite, never built as a feature.
- **Smooth scrolling with 1000+ games.** Never measured. The test library has about 214 games.

## VN Pathfinder 1.0 features still to bring across

The first goal for 2.0 was full parity with 1.0. These are the gaps.

| 1.0 feature | 2.0 today |
|-------------|-----------|
| Installer and portable EXE | No published build |
| Update check for the app itself | A switch exists but does nothing |
| Real extraction progress with MB/s and ETA | Progress bar, but no ETA and made-up speeds |
| Cancel a running extraction | Only queued extractions can be removed |
| Image manager in Fetch Metadata: see every image in a numbered list and promote any of them to cover | You choose a source for the images, and its first image is the cover |
| "Change Image" on hover, with multi-file select | Custom art in Properties → Art |
| Resizable art area | Fixed size |
| Arrow keys in the full-screen image view | Not supported |
| Colored tag chips with built-in genre and status presets | Plain tags |
| User-promoted tag presets | Saved 1.0 presets are kept in user data, but there's no screen for them |
| Rename dialog when a mod's name clashes | Adds `_2`, `_3` to the name without asking |
| Lockdown indicator opens Settings when clicked | Indicator only |
| Delete Extracted Archives checklist | Delete per archive, and Clear & Delete All for completed extractions |

## Planned features

Never built.

- **Feed normalization.** One consistent card format across sources. The Feed settings still show a note promising this.
- **Backend API.** Supabase plus a VNDB mirror, as a fallback when sources are down.
- **System tray.** Minimize to tray.
- **Advanced filtering.** By release date and rating.
- **Mod manager integration.** ModDB and Nexus.
- **Community mod sharing.**
- **Localization.** Japanese, Russian and others.
- **In-app help and user documentation.**
- **Feed cover images.** Only if every provider can supply them, so that no source gets more attention than another.
- **Orphan cleanup button.** It's only reachable from Settings → General today.
- **Direct update checks for LewdCorner and Azkosel's Corner.** They only come through the Feed today.
- **Update checks while the app stays open.** Checks only run when the library loads.

## Platforms

- **macOS 11+** (Intel and Apple Silicon) and **Linux** (GTK 3+). The repo only has a Windows project, and `webview_windows` needs replacing with a cross-platform browser such as `flutter_inappwebview`.
- **iOS and Android.** Planned for 3.0 or later.
- **Cross-platform testing** once those builds exist.

## Release and community

- **Publish a Windows build.** `v0.9.0` is a source tag with no GitHub Release.
- **Settle the version number.** The tag says `0.9.0`, but `pubspec.yaml` says `2.0.0+1`.
- **Beta release** and **community beta testing.**
- **Talk to every provider about the app.** This is why the Feed stays neutral between sources.
- **Accessibility audit.**
- **Performance profiling.**
- **More automated tests.**
