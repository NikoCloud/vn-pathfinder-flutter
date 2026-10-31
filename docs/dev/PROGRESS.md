# VN Pathfinder 2.0 — Build Progress

**Stack:** Flutter 3.41.6 · Dart 3.11.4 · Riverpod 2.6 · window_manager 0.4.3  
**Target:** Windows (primary). macOS/Linux later. Mobile is 3.0+ scope.  
**Design ref:** `mockup/index.html` + `mockup/styles.css`  
**1.0 ref:** GitHub: NikoCloud/VN-Pathfinder  
**Last updated:** 2026-10-30  
**Releases and features:** `README.md` and `CHANGELOG.md`. This file is developer reference only.

> **History rewrite (2026-10-29):** git history was rewritten to correct the commit author
> identity. Every commit hash changed. Hashes in this file and `KYUN.md` were updated to the
> new ones; any hash quoted elsewhere from before that date no longer exists.

---

## Phase Status

| # | Phase | Status | Commit |
|---|-------|--------|--------|
| 1 | Project scaffold — shell, theme, models, providers | ✅ Done | `e1b915f` |
| 2 | Library screen — sidebar + detail panel | ✅ Done | `470413b` |
| 3 | Settings modal | ✅ Done | `8c04b4b` |
| 3.5 | Carousel fix + Color API bugs | ✅ Done | `cecdd69` |
| 4 | Launch + playtime tracking | ✅ Done | `9ea6f43` (v0.9.0) |
| 5 | Library — grid mode | ✅ Done | `9ea6f43` (v0.9.0) |
| 6 | Game Properties modal | ✅ Done | `9ea6f43` (v0.9.0) |
| 7 | Metadata Fetch modal | ✅ Done (Phase 10) | `9ea6f43` (v0.9.0) |
| 8 | Archive screen | ✅ Done | `9ea6f43` (v0.9.0) |
| 9 | Add Game flow, orphan scanner, auto-backup | ✅ Done | `9ea6f43` (v0.9.0) |
| 9.5 | Context menus, lightbox, toasts | ✅ Done | `9ea6f43` (v0.9.0) |
| 10 | Metadata Fetch modal + all provider wiring complete | ✅ Done | `9ea6f43` (v0.9.0) |
| 10.5 | Login system overhaul + VNDB card in Settings | ✅ Done | `9ea6f43` (v0.9.0) |
| 11 | Search reliability — Cloudflare bypass for F95/LC searches | ✅ Done | `9ea6f43` (v0.9.0) |
| 11.5 | Tag system + library/archive separation fixes | ✅ Done | `9ea6f43` (v0.9.0) |
| 12 | RSS feed aggregator (F95Zone, LewdCorner, Discord) | ✅ Done | `36f39c1` |
| 13 | Archive overhaul — hero panel, extraction UI, deletion | ✅ Done | `e6716e8` |
| 13.5 | WebView2 lazy lifecycle + XenForo loop fix | ✅ Done | `7653177` |
| 14 | Azkosel's Corner provider (feed + metadata) + XenForo title/version fixes | ✅ Done | `661fdff`…`76b327d` |
| 15 | Scraper repair after forum redesigns, image pipeline, versioning, smart extraction | ✅ Done | `d27c83a` |
| 16 | Game status, update alerts, Unfetched filter | ✅ Done | `4056573` |
| 16.5 | Promised features: ratings, stats, hover preview, resizable layout, theming, extraction | ✅ Done | Not committed yet |
| 17 | Polish + remaining reliability | 🔲 Backlog | — |

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
│   ├── ArchiveScreen           ← Phase 8, overhauled Phase 13
│   └── FeedScreen              ← Phase 12
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

- Inactive patches: `{game}/.patches/{filename}` — at the game ROOT (sibling of `game/`), outside
  Ren'Py's load path. (Earlier versions of this file said `{game}/game/.patches/`; the code has
  always used the root — see `scanner_service.dart` and `properties_modal.dart`.)
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

**Commit:** `36f39c1`  
**`flutter analyze` result: 0 issues.**

---

## Phase 13 — Done ✅  (Archive screen overhaul)

**What was done:**

### Archive hero panel + extraction UI (commit `f4cdb5d`)
- `lib/screens/archive_screen.dart` — full rewrite with Steam-style split layout:
  - Left: scrollable archive list with cover thumbs, file size, extraction status badges
  - Right: hero panel with archive preview, extraction path picker, progress indicator
  - Right-click context menu on archive rows (extract, assign as patch, reveal in Explorer, delete)
- Extracted archives get an "Extracted" indicator badge in the list

### Archive deletion + background isolate (commits `26bda17`, `e6716e8`)
- Added delete options to archive context menu (delete archive only, delete extracted folder, delete both)
- All delete operations run in a background `Isolate.run()` call to prevent UI freeze on large archives
- Confirmation dialog before destructive actions

**Commits:** `f4cdb5d`, `26bda17`, `e6716e8`  
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

**Commit:** `7653177`  
**`flutter analyze` result: 0 issues.**

---

## Phase 14 — Done ✅  (Azkosel's Corner provider + XenForo fixes)

**What was done:**

### Azkosel's Corner as a feed source (`661fdff`)
- One togglable source that polls two XenForo RSS feeds — node 13 (games) and node 32
  (forbidden-haven games) — and merges them under source key `azc`
- `feedSourceAzc` setting (JSON `feed_source_azc`), **off by default**
- Plain HTTP first, `ScrapingService` fallback (same pattern as LewdCorner)
- "Azkosel's" filter pill in the feed toolbar, purple source badge on cards

### Azkosel's Corner as a metadata provider (`1c3e726`, `76b327d`)
- Fifth tab in Fetch Metadata. `MetadataService.searchAzkosel()` searches nodes 13 + 32 in one
  XenForo query; results show as one list
- Thread enrichment (developer, synopsis, images, tags) reuses `fetchThreadDetails()`
- `azc_url` saved to `.vnpf/metadata.json` on apply
- `76b327d`: XenForo browser-login card for AzC in Settings → Network (session stored under
  `azc`), AzC toggle in Settings → Feed, fetch-modal `credKey` set to `azc` so the lock icon
  shows when logged out

### XenForo fixes (`2c8eada`, `b3ad44f`, `384bf5c`)
- **Title cleanup:** `_cleanXenforoTitle` / `_cleanFeedTitle` strip `[bracket]` tags, then known
  prefix words (Ren'Py, VN, 3DCG, Unity, …). `_parseThreadPage` re-reads the title from the
  thread H1, where prefixes are always spans
- **Feed version badge:** the version in RSS title brackets (e.g. `[v1.5]`) is extracted before
  stripping and prepended to `rawBody` as a `Version:` line, so AzC and LewdCorner cards get badges
- **Feed WebView session:** `FeedNotifier.refresh()` now increments `scrapingSessionProvider`
  before fetching and decrements it in `finally` — fixes "not initialized" errors on feed refresh
  (this was the open item from Phase 13.5)

**`flutter analyze`:** 0 issues when re-run on 2026-10-30 (Flutter 3.41.6), before the Phase 15 work.

---

## Phase 15 — Done ✅  (Scraper repair, image pipeline, versioning, smart extraction)

**Commit:** `d27c83a` · **`flutter analyze`:** 0 issues · **Tests:** 19 passing

Found by building and running the app again after six months; most issues were diagnosed by running
the real parsers against saved live pages (guest and logged-in). See KYUN entries 16–18 for the why.

### Scrapers (`scraping_service.dart`, `metadata_service.dart`)
- **Startup race:** the fetch modal opened a scraping session and searched in the same frame;
  requests queued before the WebView finished starting threw "not initialized" and showed as
  "No results found". `_processQueue` now waits on `ready` (20 s).
- **Errors are visible:** `ScrapingException` messages reach the modal ("Not logged in to F95Zone",
  "Blocked by a Cloudflare check…", "…returned an empty page"). Login is detected from XenForo's
  `data-logged-in="false"` (members-only searches with no results). Cloudflare "Just a moment…"
  pages (`_cf_chl_opt`) are waited out for up to 20 s. VNDB and itch.io throw instead of returning [].
- **First post:** `article.message--post` or `--article` (Azkosel's Corner), body from
  `.message-body .bbWrapper` — LewdCorner/AzC render custom thread fields as bbWrappers above it.
- **Fields:** developer/release date from custom fields (`dl.pairs--customField`: "Developer
  Name", "Developer/Studio", "Release Date"); OP-text developer drops " - Patreon - …".
- **Synopsis:** `\Z` replaced with `(?![\s\S])` (Dart reads `\Z` as a literal "z"); `<br>` becomes a
  line break; indented and icon-drawn spoiler labels (": Genre:") end it; "View attachment" lines dropped.
- **Titles:** `_threadTitleText` strips span/i/svg (LewdCorner's H1 icon read as "discussion").
- **Images:** `div.bbImageWrapper[data-src]` (all three forums now) and XenForo
  `/attachments/name-png.123/` links; `previewUrls` maps login-only images to public thumbnails.
- **Search:** one `_searchXenforo` for all three forums; game threads (`[version] [dev]` titles)
  rank first so auto-pick avoids stray threads.

### Images and the hidden browser
- **WebView leak:** the modal used `ref` in `dispose()` (forbidden), threw, and never released its
  session — Chromium kept running. It now reads the service/notifier in `initState`.
- **WebView image fetch never worked:** `executeScript` returns an async script's promise, not its
  result. `_fetchImageBytes` now stores the result in `window.__vnpFetch[slot]` and polls;
  `evalOnOrigin` reuses the loaded page instead of navigating for every image.
- **New art after Apply:** files reuse their names and Flutter caches decoded images by path, so
  Apply clears `imageCache` and bumps `imageEpochProvider`, which the detail pane, sidebar
  thumbnail and grid cover key on.
- **AzC feed:** the WebView fallback reads the document source (`_documentSourceJs`) instead of
  Chrome's HTML wrapper around a text/XML response.

### Versioning and extraction
See **Versioning Model** below. Also: Properties tab rail 148 → 168 px (overflow), Feed loading
spinner no longer nests `Expanded`, `_camelSplit` splits "AFamily" → "A Family".

---

## Phase 16 — Done ✅  (Game status, update alerts, Unfetched filter)

**Commit:** `4056573`, plus later fixes · **`flutter analyze`:** 0 issues · **Tests:** 96 passing

### Game status (`models/game_status.dart`)
- **Resolution:** `effectiveGameStatus` returns the user's pick (`UserData.status`), else
  `detectedGameStatus`. A picked Playing or On Hold still shows Updated when a newer version is
  detected. Updated can't be picked by hand (`GameStatus.manual`).
- **Detection order:** Unplayed → Skimmed → Updated → Playing.
- **Skimmed:** autosaves with no page saves or quicksaves.
- **Updated:** `UserData.lastPlayedVersion` (recorded on launch) if known. Otherwise the newest
  folder having local saves means not updated, and an older folder having them means updated.
  Last, the `_version` in the newest save is compared with the folder version, numbered only.
- **Saves:** `SaveInfo` is read at scan time by `_readSaves` (names, a few stats, and only the
  `json` entry of the newest save). The scan runs in `Isolate.run`.

### Update alerts (`services/update_check_service.dart`, `providers/update_provider.dart`)
- **Versions:** `sam/checker.php?threads=` on f95zone.to, batches of 50, no login.
- **Games without a saved F95Zone link:** title search through `latest_data.php`. It accepts only
  a single exact match (ignoring case and punctuation), at 1 request per second. Misses retry
  after 7 days.
- **Other forums:** feed items match a game's saved link by source and thread ID.
- **Newer:** `isClearlyNewer` compares the `v…` part ("Part 8 v0.114" → `v0.114`).
- **Cadence:** after each library scan, at most every 6 hours (no timer, so an open app doesn't
  re-check by itself). Cached in `update_check.json`, gated by Lockdown and `check_game_updates`.

### Unfetched filter
- `GameVersion.hasVnpf` is set at scan time. `GameGroup.isUnfetched` means no version has a
  `.vnpf` folder.
- It's a filter (`unfetchedOnly`, `unfetchedCountProvider`), not a status, because a game can be
  both Playing and Unfetched.

### Merging games (`UserData.gameMerges`, `withGameMerged`)
- `gameMerges` maps a folder's own `baseKey` to the game it joins. `_buildGroups` applies it to
  versions and archives, so no files move and new versions of the merged game join by themselves.
  A version keeps its own `baseKey`, which is how Properties → Versions knows it can be separated.
- Merging moves play history, notes, tags and mod state to the target. Separating removes the
  entry from `gameMerges`; play history stays with the target.
- `UpdateCheckService.looksLikeSameGame`: same forum thread or same title. Suggestions only.

### Developer names
- `cleanDeveloperName` (`utils/formatters.dart`) keeps the first line, drops separated links and
  trailing link labels. It runs on fetched names and in `GameVersion.metaDeveloper`, so saved
  names are cleaned without fetching again.
- F95Zone runs links into the name (`Quonix <a>Patreon</a>`). When the OP line starts with the
  developer in the thread title's last bracket, the bracket wins, whatever the link is called.

### Images
- `downloadBestImages` tries the chosen source, then other sources `sameGame` confirms (same title
  and same developer, prefix allowed; unknown means no). Only then does it keep `previewUrls`
  thumbnails. A wrong saved F95Zone link once pulled another game's art here, hence the check.
- `downloadImages` replaces the cover and screenshots separately, so a partial re-fetch doesn't
  delete what it couldn't replace. `cover.webp` is now found.
- Logged in, LewdCorner embeds some images at full size with no thumbnail link, so
  `_addGuestPreviews` reads the logged-out page once to fill those in.

### LewdCorner feed and tiers
- **Forums under Games:** Games 6, Games+ 119, AI Games 212, AI Games+ 213, Ports 110, Ports+ 125,
  ATF Games & Mods 284. Search reaches them through `c[child_nodes]=1`. The `+` forums need a forum
  role: their threads open, but images are replaced by `.messageHide--attach`, which sets
  `MetadataResult.imagesLocked`.
- **Data:** `latest-updates.php?api=1&action=list` (`tier`, `perPage`, also `sort`, `platform`…)
  returns JSON with `version`, `developer`, `tags`, `platforms`, `node_id`, `is_premium`, `rating`.
  It needs a logged-in session; otherwise 403 "Invalid API key". `tier` takes Plus, Standard, AI or
  AI+; left out, it returns every tier. `is_premium` is true for Plus and AI+.
- **Roles can't be read:** `action=user_info` only reports `is_logged_in`, so Plus games are labelled
  rather than filtered. A logged-in account without a role hasn't been tested.
- **Feed:** `_fetchLewdCorner` reads 60 items through the WebView. Logged out, it reads the public
  RSS of `games.6` and `ai-games.212`. `games.119` also has public RSS, but it's left out on
  purpose. The default list isn't missing Plus: Plus games just update less often.
- `feedPlainText` (`models/feed_item.dart`) is shared by the cards and `extractFeedVersion`, for
  cached items and other RSS sources. Before it, LewdCorner's `<strong>Version:</strong>` never
  matched, so its items had no version.
- `_searchXenforo` lists exact title matches first. Chat threads can carry the same bracket tags as
  the game, and the first result gets auto-picked.

### Fixes
- Fetch Metadata results row: the developer `Text` is now `Flexible`, so long names get an
  ellipsis (184 px overflow). The one-off 267 px overflow logged during a search is probably the
  same row and hasn't recurred.

---

## Phase 16.5 — Done ✅  (Promised features)

Clears most of `BACKLOG.md`. User-facing list: `CHANGELOG.md` → Unreleased.

### Grid hover (`widgets/sidebar/game_grid.dart`)
- The grid paints in order, so scaling a card in place puts it under the next one. The hovered card
  is drawn again in an `OverlayPortal`, placed with `CompositedTransformTarget/Follower` and wrapped
  in `IgnorePointer`, so clicks still reach the real card.
- `_hoverScale` is 1.12. `nudgeInside` keeps the lifted card inside the grid at the edges.
- `_HoverDetails` sits on a dark gradient in both themes, so it uses fixed colors.

### Layout (`screens/library_screen.dart`, `widgets/common/drag_handle.dart`)
- `_ResizableSplit`: sidebar at least 220, detail at least 460. Saved as `sidebarWidth`.
- Art height is saved as `heroHeight`. 0 means automatic, 240 to 1000 otherwise. Double-click resets both.

### Theming (`theme.dart`, `app.dart`)
- `AppColors` getters read a mutable `AppPalette` and accent, set by `AppColors.apply`. `const` widgets
  can't pick up a change, so `_rebuildEverything` calls `markNeedsBuild` across the tree. That keeps
  state, so Settings stays open through a theme change.
- Font size is a `MediaQuery` `TextScaler` of `fontSize / 13`, because widgets set their own sizes.

### Extraction (`services/extraction_service.dart`)
- ZIPs stream on an isolate through `_CountingOutput`, which reports real bytes. RAR progress comes
  from 7-Zip's `-bsp1` output (`parseSevenZipProgress`).
- Cancel writes a `.cancel` marker the worker checks. `Isolate.kill` leaves file handles locked on
  Windows, so the temp folder couldn't be removed.
- `concurrentExtractions` sets how many run at once.

### Ratings (`providers/update_provider.dart`)
- Saved by Fetch Metadata from F95Zone and VNDB (VNDB's 0–100 becomes 0–5).
- F95Zone thread pages have no rating. `latest_data.php` search rows do, so `_refreshRatings` looks
  up to 20 games at each version check, 3 s apart, skipping any looked up in the last 7 days
  (`ratingLookups`, `ratingsDue`). One search returns many games, so those count as looked up too.
- It stops at the first failure and the rest stay due. A first version that searched the whole
  library at one a second made about 150 requests in 2.5 minutes, and Cloudflare answered 429 on
  `latest_data.php` for at least 10 minutes afterwards. `checker.php` wasn't tested during that time.
- Title lookups stop the same way, so a refused search can't block the version check.
- `gameRatingsProvider` prefers the live F95Zone value, then the saved one.

### Large libraries (measured 2026-10-30)
Fixture folders with small metadata on a local SSD, on the development PC. Real libraries with
save files and large images will be slower.

| Library | Scan |
|---------|------|
| 1,000 games | 5.4 s |
| 3,000 games | 14.3 s |

Scrolling 1,012 games from end to end and back in a profile build, 600×800 covers, each with its
own file:

| View | Frames | Slower than 16 ms | Build p50 / p99 | Raster p50 / p99 |
|------|--------|-------------------|-----------------|------------------|
| List | 1,151 | 4 | 3.3 / 11.8 ms | 1.6 / 3.4 ms |
| Grid | 1,034 | 11 | 0.9 / 16.1 ms | 2.1 / 4.4 ms |

### Other
- `GalleryService` owns `.vnpf` image order, cover and removal. Screenshots sort in natural order.
- `TrayService` only registers its listeners while Minimize to Tray is on. Windows removes the tray
  icon on `WM_DESTROY`, so closing the app leaves no ghost icon.
- `AppUpdateService` reads GitHub's `releases/latest`, and stays quiet until a release exists.
- Network switches default to on in both `AppSettings()` and `fromJson`. Lockdown stays on by default.
- `tool/package_windows.ps1` reads the version from `appVersion`, copies the three Visual C++ runtime
  DLLs beside the exe, and writes a portable ZIP. `installer/vn_pathfinder.iss` has a new AppId so 2.0
  installs beside 1.0.

---

## Versioning Model (reference)

- **One folder = one version.** `parseFolderName` takes the version from the folder name: the part
  after `-`, `_` or (before a dotted version) a space, matching `_versionRe` (`0.12.7`, `v0.5`, `Demo`, `Chapter-1`, `Episode-10`,
  `Act.4.3.1.Beta`, `Final`, …). Platform/junk words after it are dropped, including `_`-joined ones
  (`v0.4.8_Win` → `v0.4.8`). A leading `v` is **kept** in `versionStr`.
- **Grouping:** folders with the same `baseKey` (title tokens, separators removed, lowercased) are
  one library entry. Playtime, user tags, notes, hidden and custom art are keyed by `baseKey`.
- **Ordering:** `compareVersionStrings` — unknown (empty) < Demo < numbered < Final; numbers compare
  in order (0.11.12 < 0.12.7; 1.0 < 1.0.1); then pre-releases before the release
  (Alpha < Beta < RC < plain), then letters after it (0.5 < 0.5a < 0.5b). Latest = last.
- **Display:** always `fmtVersion` — one lowercase `v` on numbers (`V0.2` → `v0.2`,
  `v.0.14.0` → `v0.14.0`), words as words (`Chapter 1`), empty → `Unknown`.
- **Per version folder:** `.vnpf/` metadata + images (Fetch Metadata writes to the latest version)
  and `.patches/` (patch state keyed `baseKey::versionStr`).
- **Reading metadata:** title, developer, synopsis, fetched tags and source links come from the
  newest version that has them (`GameGroup.newestMeta`); cover/screenshots fall back the same way.
- **Extraction:** archives unpack into a hidden `.vnp-extract-*` folder (the scanner skips dot-folders);
  a single inner folder is flattened into the library; `planExtractFolderName` picks the title
  (one matching a library game, else the more descriptive; inner folder on a tie; generic names like
  `game`/`Windows` ignored) and the more specific version; the result is `<Title>-<version>`.
  `ExtractionLog` (`%APPDATA%\VN Pathfinder\extractions.json`) records where each archive went.
  Re-extracting merges only into that archive's own previous folder; other clashes get `-dupN`.

---

## Phase 17 — Backlog / Polish

Fixes and cleanup only. Promised and planned features are in `BACKLOG.md`.

### Release
- **Publish a Windows build** — `v0.9.0` is a source tag with no GitHub Release, `pubspec.yaml`
  says `2.0.0+1` and `appVersion` says `2.0.0-alpha`. Decide the version scheme before the first
  published build. Inno Setup isn't on the build machine, so the installer has never been compiled

### Reliability
- **Older LewdCorner attachments** — `/attachments/…` answers 200 HTML, "This attachment cannot be
  shown at this time", even logged in. Sampled IDs up to 554,287 failed and from 726,105 worked.
  Only thumbnails remain (about 150 px tall, `/2x/` is 404). May be temporary: re-test sometimes
- **Slow exit during a Feed refresh** — closing the app while the startup refresh has the hidden
  browser open kept the process alive for about 7 s. Idle, it exits in under a second. No browser
  processes stay behind either way
- **Unfetched false negatives** — Properties (rename, launch arguments, exe override) and Add Game
  also create `.vnpf`, so those games drop out of Unfetched without being fetched

### Carried over
- **macOS / Linux** — `webview_windows` is Windows-only; swap to `flutter_inappwebview` behind a platform conditional for cross-platform
- **Patch system end-to-end** — toggle (File.rename) on Windows paths with spaces not yet tested

### Housekeeping
- **Tests** — 291 tests in `test/` use small synthetic pages, folder names and game data; extend
  them when a site changes again
- **Toolchain** — builds on Flutter 3.41.6 (pinned by `pubspec.lock`); current stable is newer —
  upgrade as its own step
- **Secrets at rest** — Site session cookies are stored as plain JSON in
  `%APPDATA%\VN Pathfinder\` (local only; low priority)

## Redesign

The app was rebuilt around the Midnight Edition design. Older sections above describe the widgets as they were at the time; `navbar.dart`, `status_bar.dart`, `sidebar.dart`, `game_grid.dart`, `game_list.dart`, `game_entry.dart`, `horizontal_filter_bar.dart`, `hero_banner.dart`, `meta_bar.dart`, `detail_content.dart` and `screenshot_carousel.dart` are gone.

### Foundation

- `lib/theme.dart`: `AppPalette.dark` is Midnight, `AppPalette.light` is Paperback. `AppText` holds the type scale (`title`, `heading`, `blurb`, `body`, `meta`, `caption`, `data`). `AppMotion` is read through `of(context)` so Windows' animation setting zeroes it. `AppColors.onArt*` are for text on art in either theme.
- The accent saved as `AppColors.defaultAccentHex` (or the old default) means "the theme's own", so it stays readable on both themes.
- `lib/widgets/common/kit.dart`: `Pressable` gives any control hover, pressed, focus ring, keyboard activation and a label. `VpButton`, `VpIconButton`, `VpChip`, `VpBadge`, `VpTag`, `VpField`, `VpSegmented`, `VpTool`, `VpShelf`, `VpCard`, `VpFact` and `showVpMenu` sit on it.
- `lib/widgets/common/art.dart`: `GameArt` is the one way to draw game art. It takes a path or a web address, decodes at display size and applies Discreet. `AmbientLayer` draws the blurred page colour.
- `lib/widgets/common/art_card.dart`: `ArtCard`, `Spotlight`, `ArtFade`, `wallColumns`.
- `lib/widgets/title_bar.dart`: the window uses `TitleBarStyle.hidden`.
- `lib/providers/shell_provider.dart`: `AppTab`, `activeTabProvider`, `gamePageProvider`, `finderOpenProvider`, `libraryDetailsProvider` and the ambient providers.

### Feed and games

- `RawFeedItem` reads its facts from `rawBody` lazily: `developer`, `tags`, `rating`, `overview`, `coverUrl`, `kind`. `feedTitleKey` is the one title key for dedupe, Watch and Mute.
- What each site's list gives, sampled live on 60 rows each: LewdCorner's `is_new_game` was false on all 60 and `is_new` true on 43, so `is_new` is what counts as a new game. A `Completed` entry in `badges` means complete (14 of 60). F95Zone's `new` was true on 5 and prefix 18 was on 9. Azkosel's Corner titles end in a developer bracket on 38 of 40 threads and its posts have no developer line, so forum RSS takes the developer from the title.
- `withoutPublicRows` keeps a site's public forum feed out of the Feed once that site's Latest Updates rows exist. Forum feeds date a thread by its latest post, so during one F95Zone fallback 19 rows all carried the same three minutes and no art.
- `feed_cache.json` has a `format`. When it's older than `_cacheFormat`, the next launch refreshes straight away, and `SavedFeed.read` drops the rows that format can't be trusted for. A site that fails keeps its rows.
- `lib/providers/feed_view_provider.dart`: `FeedMatcher` (thread ID, then title), `buildFeedRows`, `shelfRows`, `matchesFeedFilter`, `pickSpotlight`. Only a thread match can claim a newer version, because titles collide.
- `lib/providers/feed_images_provider.dart`: covers are cached in `%APPDATA%\VN Pathfinder\feed_images`, one request at a time per host, nothing under Lockdown. Login-only images go through the hidden WebView, held for 30 seconds between images.
- `lib/services/thread_parser.dart`: download links and changelog out of a thread's first post. `MetadataService.fetchThread` returns both that and the usual details. `threadProvider` reads a thread once per run.
- `lib/models/version_path.dart` and `widgets/game/version_path_view.dart`: the route on the game page.
- `lib/widgets/game/game_page.dart`: `GamePage` is the full-window page, `GameView` is shared with the Library's Details view.

### Getting a game

- `third_party/webview_windows` is a copy of 0.4.0 with `DownloadStarting` passed through. See its `PATCHES.md`. `flutter_inappwebview` was the other option, but a second WebView2 plugin would not share an environment with the one holding the forum sessions.
- `lib/services/site_browser.dart`: the visible browser. It shares the app's WebView2 profile, so sign-ins carry over, and stays alive after the panel closes until the last download ends.
- `lib/providers/downloads_provider.dart`: `DownloadJob` stages are downloading, waiting, extracting, ready, saved and failed. `DownloadIntent` says what the next download is for.
- The Archive tab owns extraction, so it publishes `extractionStatusProvider` and takes `extractRequestsProvider`, which it starts once a scan has listed the archive.
- `lib/widgets/get/`: the Get sheet and the download dock.

### Library, Home and Stats

- `lib/screens/library_screen.dart`: one toolbar, `LibraryView` quick views, saved views in `settings.savedViews`, `_Wall`, `_Details` and the bulk bar. `filter_panel.dart` is now the drawer's contents.
- `lib/screens/home_screen.dart` and `lib/services/save_shots.dart`: save previews come from the `screenshot.png` entry in a Ren'Py save, cached in `%APPDATA%\VN Pathfinder\save_shots`.
- `UserData.sessions` logs each play session. `weeklyPlay` in `library_stats.dart` buckets them by Monday-to-Sunday week.

### Tests

- `test/ui_smoke_test.dart` walks every tab and both kinds of game page at 1440x900 and at the minimum window size, in both themes, on the bundled fonts. A layout error fails it.
- `FeedNotifier.seeded` and `UpdateCheckNotifier.seeded` start without touching the disk or the network, so tests never read a real cache.

### Archive cards

- `lib/services/archive_cards.dart`. A card is `<library>\.vnpf-archives\<id>\`, holding `archive.json` (file name, version, name hint) and a normal `.vnpf`. It's laid out like a game folder so `saveGameMetadata` and `downloadImages` work on it unchanged.
- `ArchiveCardDraft.build` is filled by the Get sheet from the Feed row and the thread, with the thread winning. `DownloadsNotifier._saveCard` writes it when the download starts and fetches the images. An interrupted download removes it. Extras links get no card.
- `_placeExtracted` names the folder from `ArchiveCard.extractName` when there is one, then `moveInto` renames the `.vnpf` into the game. `nameHint` is the group's `displayName`, so an update joins the game it belongs to.
- The link is by file name. A renamed file becomes a plain row until Assign relinks it.
- `gameForArchive` finds the game: the extraction log first, then the matching key. `archiveIsInstalled` needs the same version string.

### 1.0 parity check of Archive and Assign

Compared against `vn_pathfinder.py` in the 1.0 repo.

- Restored: whole-folder patches (`storeUnpackedPatch`), game search and name guess (`guessPatchGame`), the refresh and message after assigning, blocking delete during extraction, Clean Up's total and Select all or none, Delete Archive from a game.
- Better than 1.0: Clean Up needs the version to match, because 1.0's `matched_folder` falls back to the latest version and would call an unextracted update safe to delete. RAR extraction doesn't need the manual steps.
- Different on purpose: `.patches` is at the game root rather than `game/.patches`. Patches parked by 1.0 aren't read, but the library this was checked on has none in either place.

### Feed releases and catch-up

- `services/feed_history.dart`: `threadKey`, `ReleaseRecord` (`needsThread`, `settle`, saved per site, newest 5000), `SiteCatchUp` and `readBack`, with no network code so all of it is tested directly in `test/feed_history_test.dart`.
- `FeedService.fetchAll` hands rows to `onRows` as each page arrives and returns `FeedFetch` (`problems`, `sites`). `readThreadDates` reads a thread's first post.
- `FeedNotifier.refresh` lands list rows page by page, saves, then opens threads one at a time for rows that need it, 2 seconds apart, stopping after 3 misses in a row. `idle` is what the update check waits on, for up to 10 minutes.
- `feed_cache.json` is format 3, with `releases` and `sites`. Loading format 2 drops Azkosel's Corner rows and seeds the record from the rest. `SavedFeed.read` holds this.
- `mergeFeedItems` keys on `threadKey`, so one thread has one row even when its link changes, and a public feed row never replaces a list row for the same thread. LewdCorner rows carry `Posted:` from `posted_ts`.
- `parseF95List` assumes no field's type. F95Zone sends a version as a number when it looks like one, and a single cast failure used to lose the page and fall back to public RSS.

### Extraction memory and stopped downloads

- `archive` 4.0.9's `ZLibDecoder.decodeStream` collects its output in `ChunkedConversionSink.withCallback` until the input ends, and reads 1 KB at a time, so `ArchiveFile.writeContent` holds each compressed file whole in memory. `unpackZipFile` in `extraction_service.dart` replaces it for deflated files, with `RawZLibFilter`, 1 MB input chunks and output written as it's produced. Stored files already stream through `OutputFileStream.writeStream`.
- A truncated ZIP doesn't throw in that package: it decodes to no files. Both that and `ArchiveException` report the same plain message.
- `downloadStopMessage` turns WebView2's interrupt reason into words and keeps the number. The reason was already in `WebviewDownload`; nothing read it.
- `_discardPartial` removes what a stopped download left and rescans. Partial files are never kept, because nothing can resume them yet.
- A download has its final name from the first byte, so `downloadingPathsProvider` keeps it out of Archive until it's finished.
- Chromium retries a dropped download 5 times, and each try fires `DownloadStarting`. Measured with a local server that hangs up: with validators and byte ranges it resumes with `Range`, and without them it asks for the whole file again. The plugin now treats a known address as the same download (see `third_party/webview_windows/PATCHES.md`) and the dock shows the try number. Earlier operations stay alive in `earlier_tries_` until the download ends, because releasing one silenced the events of the next try.
