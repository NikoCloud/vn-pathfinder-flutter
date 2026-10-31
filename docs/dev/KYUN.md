# VN Pathfinder 2.0 — Change Journal (KYUN)

This file is a human-readable log of every significant change made to VN Pathfinder 2.0,
written for future agents and collaborators. Each entry documents **what the user asked for**,
**what was actually built**, and **why decisions were made the way they were**.

Technical details live in `PROGRESS.md`. This file focuses on the reasoning and context.

---

## Entry 1 — Project Born
**Commit:** `e1b915f`

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
**Commit:** `470413b`

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
**Commit:** `8c04b4b`, `cecdd69`

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
**Commit:** `9ea6f43`

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
**Commits:** within `9ea6f43`, then refined in `1214ba6`

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
**Commit:** within `9ea6f43`

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
**Commit:** within `9ea6f43`

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
**Commit:** within `9ea6f43`

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
**Commit:** within `9ea6f43`

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
**Commit:** `36f39c1`

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
**Commits:** `f4cdb5d`, `26bda17`, `e6716e8`

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
**Commit:** `7653177`

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
**Commit:** `661fdff`

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

## Entry 14 — Azkosel's Corner in Fetch Metadata + XenForo Follow-ups (Phase 14)
**Commits:** `1c3e726`, `2c8eada`, `b3ad44f`, `384bf5c`, `76b327d` (2026-04-22 → 04-23)

**User request:** not logged at the time. Reconstructed from the commit messages during the
2026-10-29 docs refresh.

**What was built:**
- **AzC as a fifth Fetch Metadata provider** (`1c3e726`). Both game forums (nodes 13 and 32) are
  searched in one XenForo query and shown as a single result list — the user shouldn't have to
  care which forum a game lives in. Enrichment reuses `fetchThreadDetails()`.
- **AzC login** (`76b327d`). `1c3e726` shipped AzC as "no login required"; this commit reversed
  that, adding the same XenForo browser-login card as F95Zone/LewdCorner and marking AzC as
  auth-gated in the fetch modal.
- **Title prefix stripping** (`2c8eada`). XenForo prepends engine/status labels to thread titles,
  sometimes as spans and sometimes as plain text. Titles now get a two-pass clean (brackets, then
  known prefix words), and thread pages re-read the title from the H1, where prefixes are always
  spans — the most reliable source regardless of how the search page formatted it.
- **Feed version badges** (`b3ad44f`). Stripping `[v1.5]`-style brackets for display was also
  throwing away the version. It's now extracted first and kept in `rawBody` as a `Version:` line.
- **Feed WebView session** (`384bf5c`). Correction to the Phase 13.5 known-issues entry: the real
  symptom was not "feed holds the WebView alive". After the lazy-init change the feed never
  acquired a session, so the WebView was never initialized and every source that needed it threw
  "not initialized". `refresh()` now acquires the session and releases it in `finally`.

---

## Entry 15 — History Rewrite to Fix Author Identity
**Date:** 2026-10-29

**User request:** after about six months away, the user asked for a status breakdown. The review
found the identity problem below, and the user chose to fix the README *and* rewrite history.

**Problem:**
- All 32 commits (and the `v0.9.0` tagger) carried the local Windows account name and a
  placeholder email, because the repo-local git config was set to that account. On a public repo
  this broke the project's own identity rule.
- README linked to GitHub URLs under that name — which also meant the links were dead.
- `CLAUDE.md` and this file named the account inside the very rule that forbids naming it.

**What was done:**
- `git filter-branch` in a scratch clone rewrote author and committer to
  `NikoCloud <63919429+NikoCloud@users.noreply.github.com>` — GitHub's private noreply address,
  which links commits to the account without exposing an email. Dates and messages unchanged.
- The same pass removed the name from `README.md`, `CLAUDE.md` and `KYUN.md` in every historical
  version (README links now point to `NikoCloud/vn-pathfinder-flutter` and `NikoCloud/VN-Pathfinder`).
- The annotated `v0.9.0` tag was recreated with its original message and date.
- `core.autocrlf` was disabled in the scratch clone: the system Git config has it on, which would
  have silently rewritten line endings in every commit.
- Verified before pushing: the name appears nowhere in history; per commit, only those three files
  differ; every date and message is byte-identical. Then force-pushed with a lease on the old head.
- The local clone was reset to the new history and its repo-local `user.name` / `user.email` set to
  NikoCloud.

**Consequences:**
- Every commit hash changed. Hashes in `PROGRESS.md` and this file were updated in the follow-up
  docs-refresh commit; hashes quoted anywhere else from before 2026-10-29 no longer exist.
- Old commits may stay reachable on GitHub by direct SHA URL until GitHub garbage-collects them.
  The repo had 0 forks.

---

## Entry 16 — Scrapers Repaired After the Forum Redesigns
**Commit:** `d27c83a` (2026-10-30)

**User report:** after the app was rebuilt on a new machine: "logins succeed, and some data is
coming through, it just seems that pages may have been updated and it's not where the app expects
it to be… except for F95 which is coming up empty almost all the time."

**How it was diagnosed:** the real parsers were run against saved live pages — guest pages via
plain HTTP, logged-in pages via headless Edge on a temporary copy of the app's WebView2 profile
(deleted afterwards) — and a debug build logged every page the hidden browser loaded while the user
tested. That split the problem into site changes, old bugs, and app-side races.

**What was wrong:**
- **F95 "empty":** a startup race (searches queued before the WebView finished starting failed
  instantly, shown as "No results found") plus search terms built from folder names ("AFamily
  Venture"). F95's pages and search were fine logged in.
- **LewdCorner and Azkosel's Corner redesigns:** both now render custom thread fields (developer
  links, other games…) as bbWrappers above the first post, so the parser read a 7-character field
  instead of the post — no synopsis, no images. Azkosel's Corner also marks the first post as an
  article (`message--article`). LewdCorner's title H1 gained an icon whose hidden label read as
  "discussion".
- **Old bugs:** the synopsis regex ended in `\Z`, which Dart reads as the letter "z" — "Frozen
  Past" became "Fro". The developer kept " - Patreon - Discord". Errors and logged-out pages were
  indistinguishable from "no results".

**Why errors now throw:** every failure used to become an empty list, which is how a startup race,
an expired login and a site redesign all looked identical to the user. The modal already displayed
exceptions; the scrapers just never raised any.

---

## Entry 17 — Image Pipeline and the Hidden Browser
**Commit:** `d27c83a` (2026-10-30)

**User reports:** LewdCorner preview tiles were "just 10 blank images"; after Apply, new art only
appeared after restarting the app; and the hidden browser kept running after Fetch Metadata closed
("a MAJOR bug").

**Root causes:**
- **Blank previews:** previews use plain `Image.network`; LewdCorner's full-size attachment links
  return a 403 login page without the session. Public thumbnails exist for most images (used for
  previews now); full-size embeds such as a cover have none, so those load through the WebView.
- **Downloads never worked through the WebView:** `executeScript` returns an async script's
  unresolved promise (it arrived as an empty map), so every login-only download failed and the app
  kept the old images. The fetch now parks its result in a page global and is polled.
- **Art only after restart:** Apply rewrites `cover.jpg`/`screenshot_N.jpg` under the same names and
  Flutter caches decoded images by path. Two failure modes looked like one; the user asked for a
  restart-only test, which proved files had been written but not shown.
- **Browser left running:** the modal called `ref` in `dispose()`, which Riverpod forbids; it threw
  before releasing the scraping session, so the WebView never shut down.

---

## Entry 18 — Consistent Versioning and Version-Aware Extraction
**Commit:** `d27c83a` (2026-10-30)

**User request:** "understand how the versioning works, so I can make sure it's all consistent" —
then "do all 4" of the proposed fixes, plus: extraction should be version-aware, because "some zips
actually have better naming conventions than the folder inside of it".

**What was inconsistent (seen in the real library):** six places formatted versions four ways
("vv0.03.27", "vChapter", raw "0.12.7"); "Chapter-1" parsed as "Chapter"; "Episode-10-pc" kept its
platform tag; "Final" sorted as the oldest version; letter suffixes tied; and a newly installed
version lost the fetched title and synopsis (art fell back to older versions, text didn't).

**What changed:** one formatter (`fmtVersion`), parser fixes, a defined order
(`compareVersionStrings`), and text metadata falling back like art. Across the 233 library folders
no game changed library entry and nine version strings improved. Extraction now flattens the inner
folder and names the result from the best of both names — see PROGRESS.md → Versioning Model.

**Why flatten:** extracting into a folder named after the archive left games one level deep, where
the scanner can't see a Ren'Py `game/` folder — three such games were treated as generic exe games
(no Ren'Py save detection, wrong patch folder). The four already-nested games were flattened by hand
with an undo record kept outside the repo.

**Why `-dupN` instead of merging:** re-extracting an archive merges into the folder it created
before, but extraction never merges into some other existing folder — a re-upload of the same
version can't silently overwrite files in a game the user already has.

---

## Entry 19 — Game Status, Update Alerts and Unfetched
**Commit:** `4056573` (2026-10-30)

**Why save files, not folder dates:** copying a library resets folder dates, which marked 60 games
as Updated by mistake. Save files keep their own record: the version in the save, and whether it
was a manual save or an autosave.

**Why autosaves mean Skimmed:** Ren'Py autosaves before choices whether or not anyone is reading
closely, but a manual save is deliberate. A game with only autosaves was skimmed.

**Why match updates by thread ID:** titles collide (two different games are called "Guilty
Pleasure") and differ in punctuation. Thread IDs don't. Title search accepts only one exact match,
because a wrong link is worse than none.

**Why Unfetched is a filter:** status describes how you've played a game, and a game can be
Playing and Unfetched at once. As a status it would replace Playing or Skimmed.

**Why the `.vnpf` rule:** it's the simplest check and matches what users expect. Games with text
but no images count as fetched.

---

## Entry 20 — Why Image Fallback Must Confirm the Game

When LewdCorner lost a full-size file, the first fallback simply took images from the user's other
picked sources. A real test looked perfect: nine tiny thumbnails became ten 1920×1080 images. They
were the wrong game. Lost Daughter's saved F95Zone link was an old auto-pick of Long Lost Daughter,
by a different developer.

Wrong art is worse than small art, because nothing tells you it's wrong. So `sameGame` needs the
title and the developer to match, and an unknown developer means no. It misses some real matches
(Neko-Hime and NekoFairys), which only costs a thumbnail and a warning.

---

## Entry 21 — LewdCorner's Tiers

LewdCorner sorts games into tiers. Standard and AI are public; Plus and AI+ need a forum role.
Logged-out visitors can still read Plus titles and post text through public RSS, but the images are
hidden, so a feed built on that RSS would list games its reader can't use. That's why the logged-out
fallback reads the Games and AI Games forums only.

**Why Plus games are labelled, not filtered:** the site doesn't report roles (`user_info` only says
you're logged in), so the app can't know who has access. Hiding Plus would remove games from people
who can open them.

---

## Entry 22 — Clearing the Backlog

**Why the hovered card is drawn twice:** a grid paints its cards in order, so a card scaled in place
ends up under the next one. Lifting it into an overlay solves that, and `IgnorePointer` means the
real card underneath still takes the click.

**Why Cancel uses a marker file:** killing the extraction isolate leaves its file handles open on
Windows, so the half-finished folder can't be deleted. The worker checks for a marker file and stops
by itself.

**Why theme colors are getters:** there were more than 800 fixed color references. Turning them into
getters on `AppColors` moved the whole app to the theme without touching each widget. The cost is
that `const` widgets don't rebuild by themselves, so a theme change marks the whole tree for rebuild.

**Why F95Zone ratings refresh a few at a time:** thread pages have no rating, and the bulk version
checker doesn't return one. Only title search does, so a refresh is one request per game. Doing the
whole library in one go made Cloudflare refuse that search for at least 10 minutes, so each check
now does up to 20 games, 3 seconds apart, and stops at the first refusal.

**Why the developer label needs a colon:** `Developer website: https://…` and `Developer Notes:` both
start with "Developer". Accepting a space after the word turned them into developer names.

---

## Design Decision — Feed Cards Are Text-Only

The F95 feed data includes cover images, and the Feed tab deliberately strips them. This is
intentional: the feed must not favor any provider. Some sources (Discord, and possibly future ones)
can't supply images, and image cards would draw more attention than text-only ones. The plan is to
approach every provider about the app, so the layout stays neutral — the same principle as
cross-source deduplication ("first-published wins, no platform bias"). Show images only if every
provider can supply them.

---

## Design Decision — Discord Is Coming Soon

Discord channels were taken out of the Feed until there's a better way to set them up. They needed a
personal bot token, typed `channelId:ServerName:#channel` lines, and a bot invited to every server,
which most people can't do. The Feed focuses on the forum sites until then.

Settings keeps a DISCORD (COMING SOON) section with no fields. The fetching code, filter pill and
saved token fields were removed, not hidden, so nothing is left half-connected. The first version is
in git at `a23b0b8` (`_fetchDiscord` in `feed_service.dart`). A separate dev build was considered and
dropped, because it would have meant running two builds side by side.

---

## Known Remaining Issues (as of 2026-10-31)

Full detail in `PROGRESS.md` → Phase 17.

| Issue | Severity | Notes |
|-------|----------|-------|
| Scraping failures look like "no results" | ✅ Fixed | `d27c83a` — errors are shown; see Entry 16 |
| No Cloudflare challenge-page detection | ✅ Fixed | `d27c83a` — challenge pages are waited out, then reported |
| No real tests | ✅ Fixed | 291 tests in `test/` |
| Transient scraping failures aren't retried | ✅ Fixed | `retryOnce` in Fetch Metadata |
| Older LewdCorner attachments unavailable | Medium | Full-size files refused even logged in; thumbnails remain |
| Zip extraction loads the whole archive into RAM | ✅ Fixed | Streams on an isolate (Entry 22), and each file inside is written as it unpacks (`unpackZipFile`) |
| F95Zone feed relies on one endpoint | ✅ Fixed | Falls back to public RSS |
| `xenforoLogin()` in `metadata_service.dart` is dead code | ✅ Fixed | Removed |
| Secrets stored as plain JSON | Low | Session cookies in `%APPDATA%\VN Pathfinder\` (local only) |
| Patch toggle on paths with spaces | Unknown | `File.rename()` should handle spaces, but not tested end-to-end |
| Theme settings barely apply | ✅ Fixed | `AppColors` getters; see Entry 22 |
| `webview_windows` is Windows-only | Deferred | Cross-platform needs `flutter_inappwebview` behind a platform conditional |
| No published build | Medium | `v0.9.0` is a source tag; `pubspec.yaml` says `2.0.0+1`; the app says `2.0.0-alpha` |
| Network setting defaults | ✅ Fixed | On in both, with Lockdown on by default |
| Properties can hide a game from Unfetched | Low | Rename, launch arguments and exe override create `.vnpf` |
| `A.`-prefixed versions | ✅ Fixed | Version regex |

---

## Identity Note

The developer account is **NikoCloud** everywhere public-facing (GitHub, commits, README).
The local Windows account name must never appear in commits, public docs, or URLs.
`CLAUDE.md` enforces this — always check before pushing anything that touches paths or attribution.
The repo-local git config must also be NikoCloud (`user.name NikoCloud` + the noreply email above).
Entry 15 happened because it wasn't — check `git config user.name` in any fresh clone.

---

## Design Decision — The Midnight Redesign

**Why cards went wide.** Of 114 real covers, 106 were wide, with a median ratio of 1.87. The old portrait grid kept about 35% of a typical cover; 16:9 keeps about 95%. Covers on forums are made wide, so the cards are too.

**Why covers came back to the Feed.** Images were stripped so no site would get more attention than another, because not every source had them. Every site now has them: F95Zone's list, LewdCorner's list and the image in Azkosel's Corner posts. The neutrality rule itself hasn't changed: time order, the same card size and labels for every site, and the first post of a version wins.

**Why amber means one thing.** It's only for a new version you don't have, so it can be spotted across a wall of art. Tags are neutral for the same reason: when everything is coloured, nothing stands out.

**Why a download goes through the site's real page.** The sites and hosts are the ones doing the work, and their checks, waits and ads are how they stay up. Pathfinder opens the real page and leaves it alone. It adds nothing but noticing the file. Nothing in the app solves, skips or hides any of it.

**Why title matches can't claim an update.** Titles collide (there are two Guilty Pleasures). A release matched on title alone says "In library". Only a thread match says "You have v0.8".

**Why Archive looks the way it does.** NikoCloud called the proposed Archive bland and put it on the back burner, so it has the new tokens and nothing else until that's revisited.

**Why a download brings its data with it.** NikoCloud's idea: the Feed already knows what a file is, so save that beside it and the Archive can show a card. The bigger gain is that the game arrives fetched, with the thread link right because it's the thread the file came from, unlike a title search. The data sits in the same shape as a game folder so nothing new had to learn to read it.

**Why Assign keeps whole mods again.** 2.0 had narrowed Assign to loose files and refused anything nested, throwing away images and readmes. 1.0 kept the folder. NikoCloud asked for parity, and refusing a mod helps no one, so loose patch files still go in flat and anything else stays whole.

## Design Decision — A Release Is a New Version

A Feed date only means something if it means the same thing on every site, and it doesn't. Measured
on the live sites in October 2026:

- **F95Zone's list** can be trusted. Replies up to 19 hours newer than a row didn't move it, a later
  first-post edit didn't move it, and 63 of 63 rows shared with a saved list kept their date.
- **LewdCorner's list** follows any edit of the first post. `timestamp` equals `edited_ts` on edited
  rows and `posted_ts` otherwise, and the rows that moved between two reads kept their version (3 of
  3, a small sample). A new thread also flips from `new` to `upd` on its first edit.
- **Azkosel's Corner's RSS** follows the latest reply, on 8 of 8 threads sampled, including threads
  9 months old showing as minutes old. It's a list of busy threads, not of releases. Any XenForo
  forum feed behaves this way.

So the rule is that a release is a new version of a thread, and the Feed remembers each thread's
version with its date, for longer than it shows the row. The same version keeps its date, which also
means a re-dated old thread falls back out of the Feed's window. LewdCorner uses the post date for a
new thread and the edit date when the version really changed. Azkosel's Corner has no usable date at
all, so each new version's thread is opened once and its first post read. F95Zone keeps its own
dates, because they earn it: a fix released under the same version still counts there.

Threads are keyed by number, not by link: forum links carry the title, and the title carries the
version, so a link changes at exactly the moment the history matters.

What this costs, on purpose: a thread with no version keeps its first date, a LewdCorner row seen
for the first time has no history so a small edit can pass once, and a same-version fix doesn't show
on LewdCorner or Azkosel's Corner. Public feeds standing in for F95Zone or LewdCorner don't open
threads, because they only stand in when that site has just refused a request.

## Design Decision — Catching Up

`lastRefreshed` can't say how far the Feed has read, because it moves even when a site failed. Each
site now has its own caught-up date, which only moves when a catch-up finishes.

A run reads page by page, 5 seconds apart, until it reaches that date or 10 days back. A refused
page ends the run: what it got stays, and it notes where it stopped. Starting from page 1 every time
would hit the same limit at the same depth and never get past it, so the next run reads down to
where the last one started, then skips the pages it already has. New rows push everything down by
the pages just read, which is how it knows where to land.

The Feed goes before the update check, because they share an F95Zone address and a burst from one
gets the other refused.

