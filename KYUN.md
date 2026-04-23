# VN Pathfinder 2.0 — Change Journal (KYUN)

This file is a human-readable log of every significant change made to VN Pathfinder 2.0,
written for future agents and collaborators. Each entry documents **what the user asked for**,
**what was actually built**, and **why decisions were made the way they were**.

Technical details live in `PROGRESS.md`. This file focuses on the reasoning and context.

---

## Entry 1 — Project Born
**Commit:** `76b9d4a`

**Why this exists:**
VN Pathfinder 1.0 was a Python/Tkinter app. It worked, but Tkinter is ugly, hard to extend,
and can't deliver the UI quality the user wanted. The user decided to do a full rewrite in
Flutter — a modern UI framework that produces native Windows apps with smooth animations
and a proper widget system.

The goal from day one: **feature parity with 1.0, then expand**. Not a redesign from scratch.
The 1.0 data model (UserData, GameGroup, GameVersion, patch system) is preserved exactly
so existing libraries migrate cleanly.

**Key early decisions:**
- Flutter over Electron/Tauri/PyQt — better Windows native feel, faster UI, single binary
- Riverpod for state — predictable, testable, no boilerplate magic
- Windows-first — user doesn't have macOS/Linux to test on right now
- Impeller renderer (Vulkan) — opted in early for smoother animations on Windows

---

## Entry 2 — Library Screen
**Commit:** `34f13ac`

**User request:** Build the main library view. Sidebar with game list on the left, detail
panel on the right. Match the HTML mockup in `mockup/`.

**What was built:**
- 280px sidebar: search field, tag filter dropdowns, engine/status collapsibles, sort row
- Game list: virtualized (ListView.builder with fixed item height) for libraries with 1000+ games
- Detail panel: 400px hero banner with blurred cover background, screenshot carousel, title/dev/version
- Version selector dropdown (one game can have multiple installed versions)
- PLAY button wires to the game executable via `Process.run`
- MetaBar shows disk size (computed in an isolate so the UI never freezes), playtime, last played

**Why virtualized:**
The user's library could realistically have hundreds of games. A naive Column/ListView with
no item extent would force Flutter to lay out all items on every rebuild. Fixed `itemExtent: 62`
tells Flutter exactly how tall each item is and it only renders what's on screen.

---

## Entry 3 — Settings Modal
**Commit:** `eb1f3e7`, `842cabb`

**User request:** Settings modal with all the knobs from 1.0 — library path, lockdown mode,
site credentials, appearance, archive settings.

**What was built:**
5-tab modal (Ctrl+, shortcut):
1. **General** — library directory picker, slideshow speed, auto-backup toggle
2. **Network** — lockdown master switch (kills all outbound requests), per-provider toggles
3. **Appearance** — accent color swatches, font size
4. **Archives** — 7-Zip path, concurrent extraction limit, delete-after-extract
5. **About** — version, license, links

**Bug fixed post-delivery:**
Flutter 3.27 changed the Color API — `.r`, `.g`, `.b` now return 0.0–1.0 floats instead
of 0–255 ints. The code was using `.r.round()` which would return 0 or 1, not a color
channel value. Fixed to `.r * 255`. This affected every color-related widget in settings
and theme.

---

## Entry 4 — Phases 4–9 (bundled in v0.9.0)
**Commit:** `b87e0f2`

**User requests (multiple sessions):**
- Launch tracking: record last played date and total playtime per game
- Grid view: alternative to list view, showing cover art in a grid
- Game Properties modal: 5 tabs (Info, Notes, Tags, Patches, Versions)
- Archive screen: list .zip/.rar/.rpa files found in the library root
- Add Game flow: manually add a game by pointing at a folder
- Orphan scanner: find game folders that no longer exist on disk and offer to remove them
- Auto-backup: periodic JSON backup of userdata
- Context menus: right-click on game entries
- Screenshot lightbox: click a screenshot to view full-size
- Toast notifications: non-blocking feedback messages

**Notable decisions:**
- Patches use physical file moves (`File.rename()`) between `.patches/` and the game folder.
  This matches 1.0 behavior exactly — the game engine sees files appear/disappear.
- Tags have two sources: user-assigned (stored in UserData JSON) and fetched (stored in
  `.vnpf/metadata.json`). These are merged at query time, not at write time.
- The grid view needed a separate horizontal filter bar (the sidebar doesn't fit in grid layout).
  A `gridViewProvider` StateProvider toggles between modes.

---

## Entry 5 — Metadata Fetch Modal
**Commits:** within `b87e0f2`, then refined in `99752ab`

**User request:** Build the metadata fetch system — search multiple providers (VNDB, F95Zone,
LewdCorner, itch.io), preview results, let the user pick which fields come from which source,
and download images.

**What was built:**
A "field mixer" modal. Instead of committing to one provider's data wholesale, every field
(title, developer, synopsis, tags, images) has independent source selection. The user can
pull the title from VNDB, the cover image from F95Zone, and the tags from LewdCorner — all
in one apply action.

All four providers search in parallel. Results auto-populate as they arrive. The first result
from each provider is auto-picked, populating the mixer immediately. Picking a result from
F95Zone or LewdCorner triggers a second "enrichment" fetch of the actual thread page to get
full-res images, synopsis, and tags (the search result page only has titles and links).

**Why the enrichment fetch:**
F95Zone search results only return thread titles and URLs. The cover and screenshots live
on the thread page itself (in the first post's bbCode content). A second scrape is unavoidable
for any provider built on XenForo forum software.

**Image download:**
Images are saved to `.vnpf/` inside the game folder, not next to the exe. This keeps the
game folder clean. The cover is always `cover.jpg`/`cover.png`. Screenshots are numbered
`screenshot_1.jpg` through `screenshot_N.jpg`. A `_new` rename dance is used — download to
temp names first, then only delete the old pack if at least one new image succeeded.

---

## Entry 6 — Login System Overhaul (Phase 10.5)
**Commit:** within `b87e0f2`

**User request:** F95Zone and LewdCorner logins always fail — the "✓ Connected" never shows.
Fix it.

**Root cause:**
The original login code used a plain HTTP POST (like a form submission). Cloudflare blocks this
at the TLS fingerprinting layer before the request even reaches the XenForo server. The CSRF
token fetch also fails, so the POST carries an empty `_xfToken` and the server rejects it.

**Solution:**
Replace the username/password form with a "Login with browser" button that opens a WebView2
dialog. The user logs in normally in a real browser window embedded in the app. When the URL
leaves the `/login` path, login succeeded. The WebView's cookie store retains the session.

This is the same pattern used for itch.io (which has always used browser login because adult
content requires an authenticated session). It's now the standard for all three auth-gated
providers.

**Why not just use a headless HTTP client with the right headers:**
Cloudflare's bot protection inspects TLS fingerprints (JA3 hash), not just headers. Dart's
`http` package uses a different TLS stack than a real browser, and Cloudflare detects it.
Only a real Chromium engine (WebView2) passes cleanly.

---

## Entry 7 — Cloudflare Bypass for Searches (Phase 11)
**Commit:** within `b87e0f2`

**User request:** F95Zone searches return nothing even when logged in. Fix searches.

**Root cause:**
Even after fixing login, the search requests were still sent via Dart's `http` package —
which Cloudflare also blocks for the same TLS fingerprint reason.

**Solution:**
Route all F95Zone/LewdCorner/itch.io HTTP requests through `ScrapingService` — a hidden
`WebviewController` (Chromium) that lives offscreen in the app. Every search navigates
this WebView to the search URL and reads `document.documentElement.outerHTML` via JS.
Cloudflare sees a real browser making the request.

The WebView's cookie store is shared across all navigations, so login cookies persist
automatically. No explicit cookie forwarding needed.

**XenForo intermediate page handling:**
F95Zone search shows a "Searching…" interstitial page before redirecting to results.
The scraping service polls for this by checking the HTML and waiting up to 10 seconds
for it to resolve. (A bug in this logic was later fixed — see Entry 11.)

---

## Entry 8 — "✓ Connected" Still Not Showing (Phase 11 continuation)
**Commit:** within `b87e0f2`

**User report:** After completing the WebView login, F95Zone still shows "Not connected"
in both Settings and the Fetch Metadata modal.

**Root cause:**
The WebView login dialog stored `credentials['connected'] = 'true'` as the success marker.
But the "connected" check in both Settings and the modal only looked for `xf_session` and
`xf_user` — keys that the WebView login doesn't write. The login was actually working; the
UI just didn't know how to read its own output.

**Fix:**
Updated both check sites (`_XenforoLoginCard._connected` and `_ProviderTabs._connected`)
to check `credentials['connected'] == 'true'` first, then fall back to the legacy cookie
keys for any data migrated from older versions.

---

## Entry 9 — Tags and Archive Ghost Entries (Phase 11.5)
**Commit:** within `b87e0f2`

**User reports:**
1. Tags fetched via Fetch Metadata don't appear in the filter dropdown.
2. Archive files (.zip/.rar) show up as blank entries in the game library list.

**Tag fix:**
The filter system only read tags from `UserData.tags` (user-assigned). Tags from Fetch
Metadata are stored in `.vnpf/metadata.json` under `tags_fetched`. These were never indexed
into the filter. Fixed by merging both sources in `allTagsProvider` and the filter logic.

**Archive ghost entries fix:**
The scanner picks up any folder in the library directory and creates a `GameGroup` for it.
Archive files extracted in-place create a folder with no game executable, resulting in a
`GameGroup` with zero `versions`. The library list filter now requires `g.versions.isNotEmpty`
to exclude these empty groups. They remain accessible in the Archive tab where they belong.

---

## Entry 10 — RSS Feed Aggregator (Phase 12)
**Commit:** `d63189f`

**User request:** Add a feed/news tab that aggregates update posts from F95Zone and LewdCorner
so the user can see when games in their library get new versions, without opening a browser.

**What was built:**
- Feed service that fetches RSS/Atom from F95Zone, LewdCorner, and Discord
- Feed screen as a third tab in the app (Library / Archive / Feed)
- Source filter pills to show/hide individual feeds
- Lockdown-aware (feed refresh disabled when network lockdown is on)
- Auto-refresh with manual refresh button

---

## Entry 11 — Archive Screen Overhaul (Phase 13)
**Commits:** `bb2e2a2`, `16e0238`, `cd7ba31`

**User request:** The archive screen was a bare list. Make it match the quality of the
library screen — hero panel, extraction UI, context menus, deletion options.

**What was built:**
- Steam-style split layout: archive list left, hero/action panel right
- Right-click context menu per archive: extract, assign as patch, reveal in Explorer, delete
- "Extracted" badge on archives that have already been unpacked
- Extraction progress shown in the hero panel
- Deletion options: archive only, extracted folder only, or both
- All delete operations run in a background `Isolate.run()` call

**Why background isolate for deletion:**
Deleting large extracted game folders (multi-GB) can take several seconds on spinning disks.
Running it on the main thread froze the UI completely. Moving it to an isolate keeps the
app responsive while the OS does the file work.

---

## Entry 12 — WebView2 RAM Usage (Phase 13.5)
**Commit:** `643d8ab`

**User report:** Task Manager shows `vn_pathfinder.exe` using ~22 GB of RAM at idle.
"Why is my game launcher using 22GB of RAM?"

**Root cause — two separate bugs:**

**Bug 1: Always-on WebView2**
The embedded Chromium instance (`ScrapingWebView`) was initialized at app startup and kept
alive for the entire session — even when just browsing the library. WebView2 is a full
Chromium engine. It caches pages, keeps JS heaps alive, and accumulates memory with every
page load. After scraping F95Zone/LewdCorner search results and thread pages, it had loaded
~8–10 pages and never released them.

**Bug 2: XenForo intermediate page loop never exits early**
The scraping service has a retry loop to wait for XenForo's "Searching…" interstitial to
resolve. The exit condition was:
```dart
if (!html.contains('Searching...') && !html.contains('p-main-header')) break;
```
But `p-main-header` is the standard page header present on **every** F95Zone page —
search results, thread pages, everything. So `!contains('p-main-header')` was always
`false`, and the loop always ran all 5 retries (10 seconds of extra waiting and JS execution)
even on fully-loaded pages. This compounded the memory usage by keeping the WebView busy.

**User follow-up:** "Why not all 3 [fixes]? And why are we even running the WebView for the
session duration if we only use it for fetch and feed refreshes?"

This was exactly right. The WebView should only exist while it's needed.

**Solution:**
- Added `scrapingSessionProvider` (a Riverpod ref-count integer)
- `ScrapingWebView` watches the count: initializes WebView when count goes 0→1, disposes
  when count drops back to 0
- `MetadataFetchModal` increments on open, decrements (and cancels pending requests) on close
- `ScrapingService.dispose()` tears down the native WebView2 controller and resets to a
  fresh state ready for the next session
- `ScrapingService.cancelPending()` immediately completes all queued requests with
  `ScrapingCancelledException` — no zombie page loads continue after the modal closes
- Fixed the loop condition to `!isSearching || hasPageHeader` — exits as soon as the page
  is ready

**Result:**
- Idle: ~20–50 MB (no Chromium process)
- During Fetch Metadata: ~200–400 MB (one browser tab, normal)
- After closing Fetch Metadata: back to idle within seconds

---

## Architectural Patterns (Reference)

### Why Riverpod StateNotifier instead of BLoC/GetX/etc.
The user is not a Flutter developer. Every state change needs to be readable without deep
framework knowledge. Riverpod's `ref.watch()` / `ref.read()` is explicit about what's
being observed. No streams to manage, no `context.read<MyBloc>()` ceremony.

### Why ScrapingService instead of a proper HTTP client
Cloudflare blocks Dart's `http` package at the TLS fingerprint layer. There's no
user-configurable fix for this — it requires a real browser engine. WebView2 is embedded
in every modern Windows 11 installation, so there's no download cost. The "hidden browser"
pattern is the same thing 1.0's Python `pywebview` did, just native instead of subprocess.

### Why `.vnpf/` metadata folders instead of a central database
The 1.0 design stored everything in a single `userdata.json`. This works but means losing
the file = losing all metadata. Storing metadata next to the game folder means:
- Moving a game folder preserves its metadata
- The library can be on a different drive from the app data
- Per-game backup is trivial (just zip the folder)

### Why physical file moves for patches instead of a database toggle
The game engine (RenPy, RPGM, etc.) looks for files in specific directories. It has no
concept of "disabled". The only way to make a patch truly inactive is to move the file
somewhere the engine won't find it. `File.rename()` across the same volume is instantaneous
(just a directory entry update, no data copy).

### Why IndexedStack for tab switching
`IndexedStack` keeps all tab widgets alive in memory but only shows one. This preserves
scroll position, selected game, and filter state when switching between Library and Archive.
A `PageView` or navigator would destroy and recreate the hidden tabs.

---

## Entry 13 — Azkosel's Corner Feed Provider (Phase 14)
**Commit:** `8ef2568`

**User request:** "New provider time. It has 2 latest update threads — one for mainstream games
and one for 'forbidden' games. Can we handle that?"

**Background:**
The user shared the site's global RSS feed (`/index.php?forums/-/index.rss`) which covers the
entire forum — including off-topic, AI chat, creator galleries, etc. The relevant categories are
two specific forum nodes:
- Node 13: regular games — `/index.php?forums/games.13/index.rss`
- Node 32: forbidden games — `/index.php?forums/forbidden-haven-games.32/index.rss`

**What was built:**
- `feedSourceAzc` bool in `AppSettings` (defaults `false` — opt-in, not opt-out like F95/LC)
- `setFeedSourceAzc()` in `SettingsNotifier` + `feed_source_azc` JSON key
- Two `_fetchRss()` calls in `FeedService.fetchAll()` gated on `settings.feedSourceAzc`,
  one per forum node, both using source key `'azc'` and label `'AzC'`
- Both calls use plain-HTTP-first / ScrapingService-fallback (same as LewdCorner)
- "Azkosel's" filter pill in the feed toolbar
- Purple source badge in feed cards (`0x26B04AB0` bg, `0xFFCC80CC` text)

**Why two separate `_fetchRss()` calls instead of one:**
`_fetchRss()` takes a single URL. The merge happens automatically — both return `RawFeedItem`
lists with source `'azc'`, and `Future.wait()` in `fetchAll()` flattens all results together
before the sort. No special handling needed. The deduplication pass in `FeedService.deduplicate()`
will also correctly deduplicate across the two AzC feeds if the same title appears in both.

**Why opt-in default:**
F95Zone and LewdCorner are established providers the user was already using. Azkosel's Corner
is new — defaulting it off means existing installs don't silently start fetching a new source.
The user enables it intentionally in Settings → Feed.

---

## Known Remaining Issues (as of Phase 14)

| Issue | Severity | Notes |
|-------|----------|-------|
| FeedScreen uses ScrapingService without session management | Medium | Feed refresh holds WebView alive; should increment/decrement `scrapingSessionProvider` |
| `xenforoLogin()` in `metadata_service.dart` is dead code | Low | Never called; safe to delete in a cleanup pass |
| Patch toggle on paths with spaces | Unknown | `File.rename()` should handle spaces, but not tested end-to-end |
| Dynamic accent color live hot-switch | Low | Provider wiring exists; ThemeData rebuild path not tested |
| `webview_windows` is Windows-only | Deferred | Cross-platform needs `flutter_inappwebview` behind a platform conditional |

---

## Identity Note

The developer account is **NikoCloud** everywhere public-facing (GitHub, commits, README).
The local Windows account name (`mizua`) must never appear in commits, public docs, or URLs.
`CLAUDE.md` enforces this — always check before pushing anything that touches paths or attribution.
