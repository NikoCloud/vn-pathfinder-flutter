# VN Pathfinder 2.0 — Claude Context

## Project Identity
- **App:** VN Pathfinder 2.0 (Flutter rewrite of 1.0 Python/Tkinter app)
- **Owner:** NikoCloud (GitHub: https://github.com/NikoCloud) — ALWAYS use NikoCloud for anything online/public
- **Repo:** https://github.com/NikoCloud/vn-pathfinder-flutter
- **Legacy repo (1.0 reference):** https://github.com/NikoCloud/VN-Pathfinder
- **Local 1.0 source:** `F:\RenPy\_VNPathfinder\vn_pathfinder.py`

## What This Is
A complete rewrite of VN Pathfinder (visual novel library manager) in Flutter/Dart. Goal is feature parity with 1.0, then expand. The user manages a personal adult visual novel library — this is expected and intentional.

## Tech Decisions (Already Made — Don't Re-debate)
- **Framework:** Flutter (latest stable)
- **State management:** Riverpod (StateNotifierProvider + FutureProvider)
- **Renderer:** Impeller (Vulkan on Windows)
- **Platform target:** Windows FIRST. macOS/Linux later when user has access to test. Mobile is 3.0+ scope.
- **Design source:** HTML mockup in `mockup/` folder — implement Flutter to match it

## Architecture
```
lib/
  main.dart
  models/         # Game, Patch, UserData, etc. — mirror 1.0 data model
  providers/      # Riverpod providers (games, patches, settings)
  notifiers/      # StateNotifier classes
  screens/        # LibraryScreen, ArchivesScreen, SettingsScreen
  widgets/        # Reusable components (GameCard, DetailPanel, Carousel, etc.)
  services/       # File I/O, scraping, patch management
  utils/          # Helpers
```

## Key 1.0 Features to Replicate (Priority Order)
1. Library tab — game list/cards, search, filter by tags, sort
2. Detail panel — metadata, image carousel, patch toggles, launch button
3. Archives tab — file list (ZIP/RAR/RPA), extract, assign as patch
4. Settings — library directory, lockdown mode, scraping toggles
5. Metadata fetch — multi-source scraper (F95Zone, LewdCorner, itch.io)
6. Patch management — .patches/ folder, enable/disable toggles, version-scoped
7. Orphan cleanup tool

## Data Model (from 1.0)
- `UserData` — top-level container, JSON persisted at `~/.vn_pathfinder/userdata.json`
- `GameGroup` — one entry per game title, contains multiple `GameVersion` entries
- `GameVersion` — path, version string, metadata (title, dev, tags, notes, synopsis, images)
- `applied_patches` — `Dict["{base_key}::{version_str}", Dict[str, bool]]`
- Schema version: 4 (current in 1.0)

## Developer Notes
- User is NOT a Flutter/Dart developer — Claude writes all code
- User IS the designer — they provide mockups, Claude implements
- Keep commits clean and descriptive
- Never expose local Windows paths (C:\Users\mizua\...) in public-facing content
- Always use NikoCloud as the identity, never "mizua" (that's the Windows account)
- License: Apache 2.0

## Mockup
Located in `mockup/` folder. This is the design reference — implement Flutter to match it.
The mockup is HTML/CSS built by the user. Review it before building any screen.
