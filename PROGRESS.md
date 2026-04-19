# VN Pathfinder 2.0 — Build Progress

**Stack:** Flutter 3.41.6 · Dart 3.11.4 · Riverpod 2.6 · window_manager 0.4.3  
**Target:** Windows (primary). macOS/Linux later. Mobile is 3.0+ scope.  
**Design ref:** `mockup/index.html` + `mockup/styles.css`  
**1.0 ref:** `F:\RenPy\_VNPathfinder\vn_pathfinder.py`

---

## Phase Status

| # | Phase | Status | Commit |
|---|-------|--------|--------|
| 1 | Project scaffold — shell, theme, models, providers | ✅ Done | `76b9d4a` |
| 2 | Library screen — sidebar + detail panel | ✅ Done | `34f13ac` |
| 3 | Settings modal | ✅ Done | `master` |
| 3.5 | Carousel fix + Color API bugs | ✅ Done | — |
| 4 | Launch + playtime tracking | ✅ Done | — |
| 5 | Library — grid mode | ✅ Done | — |
| 6 | Game Properties modal | ✅ Done | — |
| 7 | Metadata Fetch modal | ✅ Done (Phase 10) | — |
| 8 | Archive screen | ✅ Done | — |
| 9 | Add Game flow, orphan scanner, auto-backup | ✅ Done | — |
| 9.5 | Context menus, lightbox, toasts | ✅ Done | — |
| 10 | Metadata Fetch modal + all provider wiring complete | ✅ Done | — |
| 10.5 | Login system overhaul + VNDB card in Settings | ✅ Done | — |
| 11 | Search reliability — Cloudflare bypass for F95/LC searches | ✅ Done | — |
| 11.5 | Tag system + library/archive separation fixes | ✅ Done | — |
| 12 | RSS feed aggregator (F95Zone, LewdCorner, Discord) | ✅ Done | `d63189f` |
| 13 | Archive overhaul — hero panel, extraction UI, deletion | ✅ Done | `cd7ba31` |
| 13.5 | WebView2 lazy lifecycle + XenForo loop fix | ✅ Done | `643d8ab` |
| 14 | Polish pass — missing wiring, edge cases | 🔲 Backlog | — |

---

## Phase 1 — Done ✅

**Files created:**
- `lib/theme.dart` — AppColors, AppLayout, AppRadius, AppTheme.dark (matches mockup palette)
- `lib/models/user_data.dart` — UserData schema v4 (exact 1.0 mirror)
- `lib/models/game_group.dart` — GameGroup
- `lib/models/game_version.dart` — GameVersion
- `lib/models/archive_item.dart` — ArchiveItem + ArchiveType enum
- `lib/services/scanner_service.dart` — folder scan, name parse, version sort, art resolver (ported from 1.0)
- `lib/providers/settings_provider.dart` — AppSettings + SettingsNotifier
- `lib/providers/library_provider.dart` — LibraryNotifier + UserDataNotifier
- `lib/providers/filter_provider.dart` — FilterNotifier + filteredGroupsProvider
- `lib/utils/formatters.dart` — fmtTime, fmtDate, fmtBytes
- `lib/widgets/navbar.dart` — top nav bar (VP logo, LIBRARY/ARCHIVE tabs, lockdown badge)
- `lib/widgets/status_bar.dart` — bottom status bar
- `lib/widgets/app_shell.dart` — IndexedStack shell
- `lib/screens/library_screen.dart` — skeleton
- `lib/screens/archive_screen.dart` — skeleton
- `lib/main.dart` — window_manager init (1280×800, min 960×600, centered)

**Key decisions:**
- Plain Riverpod StateNotifier (no codegen) — avoids build_runner step during active development
- IndexedStack for tab switching — preserves scroll/state between Library and Archive
- UserData + settings persist to `%APPDATA%/VN Pathfinder/` (matches 1.0 path convention)
- Scanner runs in `Future(() => ...)` (background isolate-friendly, non-blocking UI)

---

## Phase 2 — Done ✅

**Files created:**
- `lib/widgets/sidebar/sidebar.dart` — 280px sidebar, Home/view-toggle header, Add Game button
- `lib/widgets/sidebar/filter_panel.dart` — search (title/creator), tag include/exclude dropdowns (OR/AND), Engine + Status collapsibles, sort row
- `lib/widgets/sidebar/game_list.dart` — virtualized ListView.builder, 62px item extent
- `lib/widgets/sidebar/game_entry.dart` — cover thumb, title+dev+version meta, played-status dot, hover/select animations
- `lib/widgets/detail/hero_banner.dart` — 400px hero, blurred cover bg, screenshot carousel overlay, title/dev, version selector, PLAY + Properties buttons
- `lib/widgets/detail/screenshot_carousel.dart` — PageView with peek effect, auto-advance timer, dot indicators, prev/next nav
- `lib/widgets/detail/meta_bar.dart` — Disk Size (async isolate), Last Played, Play Time, Play Count, Version
- `lib/widgets/detail/detail_content.dart` — synopsis, tag chips, Edit/Fetch Metadata/Source Pages actions, notes textarea with auto-save
- `lib/screens/library_screen.dart` — Row(sidebar | detail), empty states, _DetailPane with version switching + game launch

**Key decisions:**
- `libraryScanProvider` wired into AppShell.build — activates auto-scan on startup and dir change
- Disk size computation uses `compute()` isolate — never blocks UI thread
- ListView.builder with fixed `itemExtent: 62` — virtualized for 1000+ game libraries

---

## Phase 3 — Done ✅

**Files created:**
- `lib/widgets/modals/settings_modal.dart` — 5-tab modal (General, Network, Appearance, Archives, About)
  - General: library dir picker, slideshow interval slider, auto-backup toggle, orphan scanner stub
  - Network: lockdown master switch (highlighted red when on), per-feature toggles (disabled when locked), F95Zone + LewdCorner credential cards
  - Appearance: theme dropdown, 5 accent color swatches, font size slider
  - Archives: 7-Zip status check, concurrent extractions slider, delete-after-extract toggle
  - About: VP logo, version, license info
- Ctrl+, keyboard shortcut wired in `app_shell.dart`

**Bugs fixed (post-handoff):**
- `ScreenshotCarousel`: `FractionalTranslation` replaced with `AnimatedSlide` — translation now properly animates instead of snapping
- `theme.dart` / `settings_modal.dart`: Color API fix — `.r * 255` instead of `.r.round()` (Flutter 3.27+ `.r` is 0.0–1.0 double, not 0–255 int)
- All lint issues resolved — `flutter analyze` reports 0 issues

---

## Architecture Notes

```
AppShell
├── AppNavbar (40px)
├── IndexedStack
│   ├── LibraryScreen           ← Phase 2
│   │   ├── Sidebar (280px)
│   │   │   ├── FilterPanel
│   │   │   ├── GameList (ListView.builder)
│   │   │   └── Add Game button
│   │   └── DetailPanel (flex: 1, scrollable)
│   │       ├── HeroBanner (400px)
│   │       │   └── ScreenshotCarousel (floating, 16:9)
│   │       ├── MetaBar
│   │       └── DetailContent
│   └── ArchiveScreen           ← Phase 8
└── AppStatusBar (32px)
```

## Data Flow

```
ScannerService.scanAll(libraryDir)
  → LibraryNotifier.groups
    → filteredGroupsProvider (FilterNotifier)
      → GameList (renders entries)
        → user selects → LibraryNotifier.select(baseKey)
          → DetailPanel reads selectedGroup
```

## Patch System (1.0 parity)

- Inactive patches: `{game}/game/.patches/{filename}`
- Active patches: moved to `{game}/game/{filename}` (physical file move)
- Toggle = `File.rename()` back and forth
- Key format: `{base_key}::{version_str or '_'}`

## Phase 10 — Done ✅

**Files created:**
- `lib/services/metadata_service.dart` — `MetadataResult` model + static search functions for VNDB,
  F95Zone, LewdCorner, itch.io; `xenforoLogin()` for XenForo cookie auth; `downloadImages()`
- `lib/widgets/modals/metadata_fetch_modal.dart` — Full search/preview/apply modal (900×680)
  - Left panel: search query field, provider tabs (VNDB | F95Zone | LewdCorner | itch.io), results list
  - Right panel: cover, title/developer, synopsis, tags, screenshot strip
  - Footer: "Download images" checkbox, progress indicator, Apply + Cancel buttons
  - Lockdown-aware (disables search when network is locked down)
  - On Apply: merges with existing .vnpf/metadata.json → downloads images → re-scans library

**Files modified:**
- `lib/providers/settings_provider.dart` — added `setSiteCredentials()` + `clearSiteCredentials()`
- `lib/screens/library_screen.dart` — wired `onFetchMetadata` → `showMetadataFetchModal(context, g)`
- `lib/widgets/modals/settings_modal.dart` — added `_ItchioLoginCard` (browser login card) and
  `_ItchioLoginDialog` scaffold (webview_windows pending full initialization)
- `pubspec.yaml` — added `webview_windows: ^0.4.0`

**Key decisions:**
- VNDB is the default/primary provider — no auth, solid API, returns cover + screenshots + tags
- F95Zone / LewdCorner: Settings → Network login now calls `xenforoLogin()` (two-step XenForo flow)
  and stores real session cookies (`xf_user`, `xf_session`). Selecting a search result triggers a
  second thread-page fetch (`fetchThreadDetails`) to extract cover image + screenshots from the OP post.
- itch.io: embedded WebView2 dialog via `webview_windows` — opens `https://itch.io/login`, polls
  `url` stream, extracts `document.cookie` on `/my-feed` redirect, saves to `siteCredentials['itchio']`
- Source links in the metadata preview panel now open in the system browser via `url_launcher`
- On Apply: existing metadata is merged (not overwritten) — only non-empty fields are updated,
  preserving any manual edits
- Image download is opt-out (checkbox in footer), respects 9-screenshot max

**Bug fixed (post-Phase 10):**
- `app_shell.dart` had a spurious `LibrarySidebar` outside `LibraryScreen` → doubled sidebar in list
  mode. Removed; `LibraryScreen` owns its own sidebar as designed.

## Metadata Storage (.vnpf/)

- `{game}/.vnpf/metadata.json` — title, developer, synopsis, tags, source URLs
- `{game}/.vnpf/cover.jpg` or `cover.png` — cover art
- `{game}/.vnpf/screenshot_1.jpg` … `screenshot_18.jpg` — carousel images

## Scraper Notes (Phase 7 / Phase 10)

### VNDB
- POST `https://api.vndb.org/kana/vn` — JSON body with `filters`, `fields`
- No auth required. Works with lockdown=OFF.
- Rate limit: generous (no API key needed for basic queries)

### F95Zone
- Requires `xf_user` + `xf_session` cookies (XenForo session)
- Obtained via form login POST to `https://f95zone.to/login/login`
- Store response `Set-Cookie` headers → persist in settings under `siteCredentials['f95zone']`
- Use `http` package with spoofed Chrome UA + headers (TLS fingerprint not enforced server-side)
- Search endpoint: `https://f95zone.to/search?q={title}&t=post&c[nodes][]=2`

### LewdCorner
- Same XenForo cookie pattern as F95Zone
- Login POST to `https://lewdcorner.com/login/login`
- Persist `xf_user` + `xf_session` in `siteCredentials['lewdcorner']`

### itch.io — IMPORTANT: Browser Login Required
- **Adult content is gated behind authenticated sessions.** The public itch.io API does NOT
  return adult/NSFW games without an authenticated cookie. API key approach is insufficient.
- **1.0 implementation (Python):** `pywebview` subprocess with `edgechromium` GUI, opens
  `https://itch.io/login`, polls `win.get_current_url()` every 500ms, on `/my-feed` URL calls
  `win.get_cookies()` (native WebView2 COM API — captures HTTP-only cookies), saves to
  `cookies_itchio.json`.
- **2.0 implementation (Flutter):** `webview_windows` package (WebView2 engine, Windows only).
  - Add `webview_windows: ^0.4.0` to `pubspec.yaml`
  - Open embedded `WebviewWidget` in a dialog, navigate to `https://itch.io/login`
  - Listen to `webviewController.url` stream; when URL contains `/my-feed`, login succeeded
  - Extract cookies via `webviewController.executeScript('document.cookie')`
  - **Limitation vs 1.0:** `executeScript` only returns non-HTTP-only cookies. The `itchio_token`
    CSRF/auth cookie is non-HTTP-only and should be sufficient for adult content access.
  - Save extracted cookies to `siteCredentials['itchio']` in settings
- **Settings UI:** Network tab itch.io card shows "Login with browser" button (not username/password).
  After successful login, show "✓ Connected" status with account name if parseable.
- **Search endpoint:** `https://api.itch.io/search/games?query={title}` with
  `Authorization: Bearer {itchio_api_key}` — BUT for adult content, must also pass the
  session cookies in the request headers or use the browser session directly.

### pubspec.yaml additions needed for Phase 10
```yaml
webview_windows: ^0.4.0   # itch.io embedded browser login (Windows only)
```

---

## Phase 10.5 — Done ✅  (Login system overhaul + VNDB card)

**Problem discovered during testing:**
- F95Zone and LewdCorner `xenforoLogin()` (plain HTTP POST) always returned "Login failed" because
  both sites sit behind Cloudflare. The bot-protection layer blocks the HTTP GET to `/login/` before
  a valid `_xfToken` can be extracted, so the subsequent POST always carries an empty CSRF token and
  the server rejects it without ever setting `xf_user`.
- VNDB appeared "missing" from Settings → Network — users expected to see all four providers listed
  there (alongside F95Zone, LewdCorner, itch.io), but VNDB had no card since it needs no auth.

**Files modified:**
- `lib/widgets/modals/settings_modal.dart`
  - Removed `_LoginCard` (username/password form) and its `_CredField` helper
  - Added `_XenforoLoginCard` — button-only card (same visual language as `_ItchioLoginCard`)
    showing "Login with browser" → opens `_XenforoLoginDialog`
  - Added `_XenforoLoginDialog` — full WebView2 embedded browser, same architecture as
    `_ItchioLoginDialog`; detects login success when URL leaves the `/login` path on the target
    domain; extracts `xf_session` (non-HTTP-only in XenForo) + optional username from nav bar JS
  - Added `_VndbInfoCard` — informational card in SITE LOGINS group; shows "Public API" badge,
    description, and a live **Test Connection** button (runs a `searchVndb('Steins Gate')` probe)
  - Updated `_NetworkPanel` to render `_VndbInfoCard` first, then two `_XenforoLoginCard`s, then
    `_ItchioLoginCard` — all four providers now visible in Settings → Network

- `lib/widgets/modals/metadata_fetch_modal.dart`
  - `_ProviderTabs._connected()`: added `xf_session` check alongside `xf_user` so the WebView-
    extracted session cookie correctly shows the tab as unlocked

**Key decisions:**
- Browser-based login (WebView2) is now the standard for ALL three auth-gated providers. This
  pattern reliably bypasses Cloudflare / JS-challenge bot-protection that blocks plain HTTP clients.
- `xf_session` is intentionally non-HTTP-only in XenForo (needed for XHR): `document.cookie` in
  the WebView returns it cleanly. `xf_user` (remember-me) may also be returned depending on the
  XenForo version and site config.
- The old `MetadataService.xenforoLogin()` static method is retained in `metadata_service.dart`
  but is no longer called by any UI code. It can be removed in a future cleanup pass.

**Scraper Notes — UPDATED:**

### F95Zone (updated)
- Login: WebView2 embedded browser (`_XenforoLoginDialog`, same as itch.io)
  - Navigates to `https://f95zone.to/login/`
  - Detects success when URL moves off `/login` path while still on `f95zone.to`
  - Extracts `xf_session` + (optionally) `xf_user` and `username` via `document.cookie` + JS
  - Saved to `siteCredentials['f95zone']`
- Search: `https://f95zone.to/search?q=…&t=post&c[nodes][]=2` — plain Dart `http` request with
  `xf_session` cookie header. **⚠ Known risk:** Cloudflare may also protect search endpoints.
  If searches return 403/empty, the fix is to run searches through the WebView too (Phase 11).
- Thread detail enrichment: `fetchThreadDetails()` fetches the game thread page and parses cover
  image + screenshots from the OP post via `html` parser.

### LewdCorner (updated)
- Login: same `_XenforoLoginDialog` pattern; `baseUrl = 'https://lewdcorner.com'`
- Search: `https://lewdcorner.com/search?q=…&t=post` with session cookie
- Same Cloudflare risk as F95Zone for search requests.

---

## Phase 11 — Done ✅  (Search reliability — Cloudflare bypass)

**What was done:**

**Root cause of login showing "Not connected" after successful WebView login:**
- `_XenforoLoginDialog._extractAndFinish()` stores `cookies['connected'] = 'true'` (no `xf_session`)
- But both `_XenforoLoginCard._connected` and `_ProviderTabs._connected()` only checked for
  `xf_session` / `xf_user`, never checking `connected`. So every login appeared to fail even when
  it worked perfectly in the WebView.

**Files modified:**
- `lib/widgets/modals/settings_modal.dart`
  - `_XenforoLoginCard._connected` — now accepts `credentials['connected'] == 'true'` (checked first)
  - `_XenforoLoginCardState._refreshSession` — now stores `connected: 'true'` instead of `xf_session: 'active'`
  - Fixed `use_build_context_synchronously` lint warning (SnackBar wrapped in `if (mounted)`)
- `lib/widgets/modals/metadata_fetch_modal.dart`
  - `_ProviderTabs._connected()` — same fix; `connected == 'true'` accepted alongside legacy keys
- `lib/services/scraping_service.dart` — removed unnecessary `foundation.dart` import
- `lib/services/webview_browser.dart` — **deleted** (was dead code; `ScrapingService` handles all WebView transport)

**Search transport (already implemented in previous session):**
- All F95Zone/LewdCorner searches go through `ScrapingService` (headless `WebviewController`)
  which IS a Chromium engine — passes Cloudflare TLS checks without any cookie forwarding needed.
- The WebView2 app-level cookie store (`%APPDATA%\…\EBWebView`) persists login cookies, including
  HTTP-only `xf_user`. All WebView navigations automatically use these cookies.
- `ScrapingWebView` (hidden widget in `AppShell`) initializes `ScrapingService` on app start from
  the UI thread as required.

**`flutter analyze` result: 0 issues.**

---

## Phase 11.5 — Done ✅  (Tag system + library/archive separation)

**What was done:**

### Tag system fixes
1. **`allTagsProvider`** — now merges two sources:
   - `ud.tags[baseKey]` — user-assigned tags from UserData (1.0 compatible)
   - `v.metaTags` — tags from each version's `.vnpf/metadata.json`
     (`tags_fetched` field from Fetch Metadata, plus `tags` legacy 1.0 field)
   Before: only `ud.tags` was indexed → tags fetched via Fetch Metadata never appeared in filter dropdowns.

2. **`filteredGroupsProvider` tag filters** — include/exclude filters now use `_allTagsForGroup(g, ud)`
   which calls `v.metaTags` on all versions. Before: only `ud.tags[g.baseKey]` was checked.

3. **`_allTagsForGroup()` helper** added as a top-level function used by both the filter provider
   and (in the future) any widget that needs the merged tag view for a group.

### Library/archive separation
4. **`filteredGroupsProvider`** — added `g.versions.isNotEmpty` guard:
   ```dart
   var result = groups
       .where((g) => g.versions.isNotEmpty && !ud.hidden.contains(g.baseKey))
       .toList();
   ```
   Before: archive-only `GameGroup` entries (no installed game, just a zip/rar in the library root)
   appeared as ghost entries in the library list. Now they are correctly invisible in the library
   and remain accessible only in the Archive tab.

### F95Zone / LewdCorner tag extraction
5. **`_parseThreadPage()`** in `MetadataService` — now extracts XenForo tag list from thread pages:
   ```dart
   doc.querySelectorAll('.js-tagList a.tagItem, .tagList a.tagItem, ...')
   ```
   Tags from the thread page replace the empty `result.tags` from the initial search result.

### itch.io tag extraction
6. **`_parseItchSearchHtml()`** — added best-effort tag parsing from game search cells
   (`.game_genre a, .tag_cloud a, a.tag, span.tag_label`).

### Image download improvement
7. **`downloadImages()`** — now accepts an optional `ScrapingService` parameter.
   - First attempt: plain `http.get()` with proper `Referer` header (works for public CDNs, VNDB, itch.io)
   - Fallback: if HTTP returns non-200, and `ScrapingService` is available, runs a JS `fetch()` inside
     the WebView (which has the session cookies). Returns base64-decoded bytes.
   - `_apply()` in `MetadataFetchModal` now passes `scrapingService` to `downloadImages()`.

**Files modified:**
- `lib/providers/filter_provider.dart` — versions guard, `_allTagsForGroup`, `allTagsProvider` merge
- `lib/services/metadata_service.dart` — tag extraction in `_parseThreadPage`, itch.io tags,
  `downloadImages` with WebView fallback, `_fetchImageBytes`, `_refererFor`, `_siteBaseUrl`, `_jsString`
- `lib/widgets/modals/metadata_fetch_modal.dart` — pass `scrapingService` to `downloadImages`
- `PROGRESS.md` — this update

**`flutter analyze` result: 0 issues.**

---

## Phase 12 — Done ✅  (RSS feed aggregator)

**What was done:**
- New `lib/services/feed_service.dart` — fetches and parses RSS/atom feeds from F95Zone, LewdCorner, and Discord webhook/feed URLs
- New `lib/providers/feed_provider.dart` — `FeedNotifier` with `FeedEntry` model, auto-refresh, per-source toggles
- New `lib/screens/feed_screen.dart` — feed UI (card list, source filter pills, refresh button, lockdown-aware)
- `lib/widgets/app_shell.dart` — added FeedScreen to IndexedStack (3rd tab)
- `lib/widgets/navbar.dart` — added Feed tab to top nav

**Commit:** `d63189f`  
**`flutter analyze` result: 0 issues.**

---

## Phase 13 — Done ✅  (Archive screen overhaul)

**What was done:**

### Archive hero panel + extraction UI (commit `bb2e2a2`)
- `lib/screens/archive_screen.dart` — full rewrite with Steam-style split layout:
  - Left: scrollable archive list with cover thumbs, file size, extraction status badges
  - Right: hero panel with archive preview, extraction path picker, progress indicator
  - Right-click context menu on archive rows (extract, assign as patch, reveal in Explorer, delete)
- Extracted archives get an "Extracted" indicator badge in the list

### Archive deletion + background isolate (commits `16e0238`, `cd7ba31`)
- Added delete options to archive context menu (delete archive only, delete extracted folder, delete both)
- All delete operations run in a background `Isolate.run()` call to prevent UI freeze on large archives
- Confirmation dialog before destructive actions

**Commits:** `bb2e2a2`, `16e0238`, `cd7ba31`  
**`flutter analyze` result: 0 issues.**

---

## Phase 13.5 — Done ✅  (WebView2 lazy lifecycle + XenForo loop fix)

**What was done:**

### Problem
`vn_pathfinder.exe` was consuming ~22 GB RAM at idle because the embedded Chromium (WebView2) instance was initialized at app startup and kept alive for the entire session, even during normal library browsing when no scraping was happening.

A second bug caused all F95Zone/LewdCorner page loads to wait the full 10-second retry delay even when the page had already fully loaded, compounding the memory churn.

### Changes

**`lib/services/scraping_service.dart`:**
- Added `scrapingSessionProvider = StateProvider<int>` — reference count of active scraping consumers
- Added `ScrapingCancelledException` — thrown to queued requests when cancelled
- `ScrapingService` no longer initializes on construction; `initialize()` is idempotent + guarded by `_isInitializing` flag
- New `cancelPending()` — drains the queue immediately, completing all pending Completers with `ScrapingCancelledException`
- New `dispose()` — calls `cancelPending()`, disposes the native WebView2 controller, creates fresh state; service is fully re-usable after `dispose()` + `initialize()`
- **Fixed XenForo intermediate-page loop bug:** old condition `!html.contains('p-main-header')` was always `true` on real F95Zone/LC pages (the page header is always present), so all 5 × 2 s retries fired on every load. Fixed to `!isSearching || hasPageHeader` — exits as soon as the page is ready

**`lib/widgets/common/scraping_webview.dart`:**
- Now watches `scrapingSessionProvider` via `ref.listen`
- Calls `service.initialize()` when count transitions 0 → positive (WebView spins up on demand)
- Calls `service.dispose()` when count drops back to 0 (WebView torn down, Chromium process exits)
- Renders `Webview(controller)` only while initialized; `SizedBox.shrink()` otherwise

**`lib/widgets/modals/metadata_fetch_modal.dart`:**
- `initState` — increments `scrapingSessionProvider` before starting search (acquires a session)
- `dispose` — calls `service.cancelPending()` then decrements session count (releases session, triggers WebView disposal if count reaches 0)

### Result
- Idle RAM: ~20–50 MB (no Chromium)
- During Fetch Metadata: ~200–400 MB (normal for a browser tab)
- Closing the modal: RAM released within seconds
- Pending searches cancelled immediately on modal close — no zombie scraping

**Commit:** `643d8ab`  
**`flutter analyze` result: 0 issues.**

---

## Phase 14 — Backlog / Polish

- **WebView session management for FeedScreen** — feed refresh also uses ScrapingService; should acquire/release `scrapingSessionProvider` the same way MetadataFetchModal does
- **Dynamic accent color** at runtime: settings provider + AppTheme wiring exists, needs end-to-end test
- **Orphan scanner trigger** — wired via Settings → General → "Scan Now" only; consider a persistent toolbar button
- **Remove dead `xenforoLogin()`** from `metadata_service.dart` (browser login is the only auth path now)
- **macOS / Linux** — `webview_windows` is Windows-only; swap to `flutter_inappwebview` behind a platform conditional for cross-platform
- **Patch system end-to-end** — toggle (File.rename) on Windows paths with spaces not yet tested
- **Version prefix edge cases** — scanner strips `v`/`V`; verify `ver2.0`, `version1`, etc.
