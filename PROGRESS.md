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
| 2 | Library screen — sidebar + detail panel | 🔄 In Progress | — |
| 3 | Settings modal | ⏳ Pending | — |
| 4 | Launch + playtime tracking | ⏳ Pending | — |
| 5 | Library — grid mode | ⏳ Pending | — |
| 6 | Game Properties modal | ⏳ Pending | — |
| 7 | Metadata Fetch modal | ⏳ Pending | — |
| 8 | Archive screen | ⏳ Pending | — |
| 9 | Add Game flow, orphan scanner, auto-backup | ⏳ Pending | — |
| 10 | Context menus, lightbox, toasts, polish | ⏳ Pending | — |

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

## Phase 2 — In Progress 🔄

**Goal:** Full Library screen UI matching the mockup.

**Widgets to build:**
- `lib/widgets/sidebar/sidebar.dart` — sidebar container + bottom Add Game button
- `lib/widgets/sidebar/filter_panel.dart` — search, tag include/exclude dropdowns, engine/status collapsibles, sort row
- `lib/widgets/sidebar/game_list.dart` — virtualized ListView.builder of game entries
- `lib/widgets/sidebar/game_entry.dart` — single row: cover thumb, title, meta, status dot
- `lib/widgets/detail/hero_banner.dart` — 400px hero with blurred bg + screenshot carousel overlay + title/dev/play area
- `lib/widgets/detail/screenshot_carousel.dart` — PageView with peek-prev/next effect, dots, auto-advance
- `lib/widgets/detail/meta_bar.dart` — Disk Size / Last Played / Play Time / Play Count / Version
- `lib/widgets/detail/detail_content.dart` — synopsis, tags, action buttons, notes textarea
- `lib/screens/library_screen.dart` — replaces skeleton with Row(sidebar | detail)

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

## Metadata Storage (.vnpf/)

- `{game}/.vnpf/metadata.json` — title, developer, synopsis, tags, source URLs
- `{game}/.vnpf/cover.jpg` or `cover.png` — cover art
- `{game}/.vnpf/screenshot_1.jpg` … `screenshot_18.jpg` — carousel images

## Scraper Notes (Phase 7)

- VNDB: POST `api.vndb.org/kana/vn` — no auth, works in lockdown=OFF
- F95Zone: needs `xf_user` + `xf_session` cookies (Chrome TLS impersonation via http package + custom headers)
- LewdCorner: similar cookie pattern
- itch.io: OAuth via `url_launcher` → browser → capture redirect
