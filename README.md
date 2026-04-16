# VN Pathfinder 2.0 — Flutter Rewrite

> **Status:** 🚧 In Development | **Target:** Feature Parity with 1.0 | **ETA:** Valve Time™

VN Pathfinder 2.0 is a complete rewrite of the popular visual novel library management tool, built with **Flutter** for true cross-platform compatibility, modern UI/UX, and superior performance.

---

## 📋 Overview

This is a **work-in-progress rebuild** of VN Pathfinder targeting **Windows, macOS, and Linux** with a refreshed codebase and beautiful new interface. The initial milestone is **feature parity with version 1.0** — once we achieve that, we'll build on it with new capabilities.

### Why Flutter? Why Now?

**VN Pathfinder 1.0** (Python + Tkinter) was a proof-of-concept that worked well and built a small but dedicated community. However:

- **Platform Lock-in:** Tkinter on Windows is clunky; native experiences on macOS and Linux were compromised
- **UI/UX Ceiling:** Tkinter's limited theming and widget library made it hard to build something *beautiful*
- **Performance:** Python startup times and GUI responsiveness suffered at scale (hundreds of games)
- **Maintenance:** Single-language codebase tied to Python's ecosystem, making long-term maintenance harder

**Flutter solves these:**
- ✅ **True Cross-Platform:** Single codebase compiles to native Windows, macOS, Linux binaries
- ✅ **Beautiful UI:** Modern Material 3 design system with smooth animations, dark mode, responsive layouts
- ✅ **Fast:** Compiled Dart with minimal startup time and buttery-smooth 60/120 FPS UI
- ✅ **Future-Proof:** Growing ecosystem, backed by Google, used by major apps (Google Ads, eBay, BMW, etc.)

This rewrite is an investment in **longevity and quality** — not just a port, but a thoughtful modernization.

---

## 🎯 Feature Parity Goals (1.0 → 2.0)

### Core Library Management
- ✅ Add/remove games from your personal visual novel library
- ✅ Recursive folder scanning with auto-detection of Ren'Py games
- ✅ Customizable library root directory (per-device configuration)
- ✅ Game metadata: title, developer, version, tags, notes, release date
- ✅ Search & filter by title, developer, or custom tags
- ✅ Sort by multiple fields (title, developer, date added, last played)

### Archive & Patch Management
- ✅ Archive browser with ZIP/RAR/loose file (.rpa, .rpy) detection
- ✅ Non-destructive patch/mod system with version tracking
  - Extract patches to versioned `.patches/` folders
  - Toggle patches on/off without deletion (pure move semantics)
  - Per-version patch state (different game versions have independent patch sets)
  - Collision detection and user-friendly rename dialogs
- ✅ Extract RAR archives with optional 7-Zip backend
- ✅ Last-modified date display for archive files

### Content Fetching & Metadata
- ✅ Multi-source metadata scraping:
  - **F95Zone** (games, tags, version info, ratings)
  - **itch.io** (games, metadata)
  - **Lewd Corner** (games, metadata, images)
- ✅ Fetch game banners, cover art, and in-game screenshots
- ✅ Auto-populate tags from scraping sources
- ✅ Manual metadata editing with local persistence

### Gallery & Preview
- ✅ Image carousel for game banners and screenshots
- ✅ Drag-to-reorder gallery images
- ✅ Full-screen image preview

### User Interface & UX
- ✅ Dark mode and light mode with system preference detection
- ✅ Responsive layout (works on different screen sizes)
- ✅ Orphan cleanup tool (identify games without library entries)
- ✅ Game stats dashboard (total games, by developer, playtime tracking)
- ✅ Settings panel with configurable options
- ✅ Multi-language support structure (currently English)

### Data & Privacy
- ✅ Local-first architecture — all data stored in user's home directory
- ✅ No telemetry, no tracking, no sign-ups required
- ✅ Optional scraping toggle (can disable internet features entirely)
- ✅ User data format: JSON with version migration support
- ✅ Automatic backups of user data

---

## 🔄 What's Different in 2.0?

### Codebase Changes
| Aspect | 1.0 (Python) | 2.0 (Flutter) |
|--------|--------------|---------------|
| **Language** | Python 3.11+ | Dart 3.x |
| **GUI Framework** | Tkinter | Flutter + Material 3 |
| **Rendering** | Software/Tk engine | Impeller (GPU-accelerated; Vulkan/Metal backends) |
| **Data Serialization** | JSON (custom parsing) | JSON + Dart serialization |
| **Threading** | Python threading | Dart async/await |
| **Packaging** | PyInstaller | Flutter build system |

### Visual & UX Improvements
- Modern, polished Material 3 design
- Smooth transitions and animations
- Better mobile-responsive layouts (future tablet support)
- System tray integration (minimize to tray)
- Better keyboard navigation and accessibility

### Performance Gains
- Instant startup (vs. ~3-5s Python initialization)
- Smooth scrolling in large libraries (1000+ games)
- Responsive UI under heavy scraping operations
- Lower memory footprint

---

## 🌍 Cross-Platform Compatibility

VN Pathfinder 2.0 targets:

| Platform | Status | Notes |
|----------|--------|-------|
| **Windows** 10+ | 🎯 Primary | Tested on Windows 10/11 |
| **macOS** 11+ | 🔄 Planned | Intel & Apple Silicon support |
| **Linux** (GTK 3+) | 🔄 Planned | Ubuntu, Fedora, Debian, etc. |
| **iOS/Android** | ⏸️ Future (3.0+) | Out of scope for 2.0 launch, but codebase supports it |

The same binary codebase compiles to native executables for each platform with **zero code changes** — Flutter handles platform-specific details.

---

## 🚀 Development Roadmap

### Phase 1: Foundation (Current)
- [ ] Core library management (games, metadata, versioning)
- [ ] Archive detection and patch system
- [ ] Local data persistence and migration
- [ ] Multi-source scraping infrastructure
- [ ] Basic UI (dark mode, responsive layout)

### Phase 2: Feature Parity
- [ ] All metadata fields from 1.0
- [ ] Complete gallery and image management
- [ ] Orphan cleanup tool
- [ ] Settings and configuration panel
- [ ] Search, filter, sort (full-featured)
- [ ] RAR extraction support

### Phase 3: Polish & Stability
- [ ] Cross-platform testing (Windows, macOS, Linux)
- [ ] Performance optimization
- [ ] Accessibility improvements
- [ ] User documentation
- [ ] Beta release

### Phase 4+: New Features
- Playtime tracking and statistics
- Advanced filtering (by release date, rating, etc.)
- Mod manager integration (ModDB, Nexus)
- Community mod sharing
- Localization (Japanese, Russian, etc.)
- iOS/Android ports

---

## 💾 Currently Ready? Use Version 1.0

If you need a **production-ready** visual novel library manager **right now**, use **VN Pathfinder 1.0**:

🔗 **[VN Pathfinder 1.0 on GitHub](https://github.com/NikoCloud/VN-Pathfinder)**

Version 1.0 is feature-complete and stable. Grab the latest release and start managing your library today. We'll transition to 2.0 when it reaches parity — no rush.

---

## 🛠️ Building from Source

### Requirements
- Flutter 3.x SDK ([Install Flutter](https://flutter.dev/docs/get-started/install))
- Dart 3.x (included with Flutter)
- Git

### Setup
```bash
git clone https://github.com/mizua/vn-pathfinder-flutter.git
cd vn-pathfinder-flutter
flutter pub get
```

### Run (Development)
```bash
flutter run -d windows  # or -d macos, -d linux
```

### Build (Release)
```bash
flutter build windows --release  # Creates .exe in build/windows/runner/Release/
flutter build macos --release    # Creates .app
flutter build linux --release    # Creates executable
```

---

## 📁 Project Structure

```
vn-pathfinder-flutter/
├── lib/
│   ├── main.dart              # App entry point
│   ├── models/                # Data models (Game, Patch, UserData, etc.)
│   ├── screens/               # UI screens (LibraryScreen, ArchiveScreen, etc.)
│   ├── services/              # Business logic (scraping, file I/O, patch management)
│   ├── widgets/               # Reusable UI components
│   └── utils/                 # Helpers (parsing, formatting, platform detection)
├── test/                      # Unit and widget tests
├── pubspec.yaml              # Dependency manifest
└── README.md                 # This file
```

---

## 🔐 Privacy & Data

- **No accounts required** — use immediately, no sign-ups
- **All data stays local** — stored in your home directory (`~/.vn_pathfinder/`)
- **No telemetry** — we don't track usage, errors, or analytics
- **Open-source** — code is readable; audit if you like
- **Optional scraping** — disable internet features if you prefer

---

## 🤝 Contributing

This is a **solo project** (personal passion project), but feedback and testing help immensely:

- Found a bug? Have a feature idea? Open an issue
- Used 1.0 and miss something? Let us know — we want parity first
- Testing on macOS or Linux? Your feedback shapes the experience

---

## 📝 License

[Same license as VN Pathfinder 1.0 — check 1.0 repo for details]

---

## 🔗 Links

- **VN Pathfinder 1.0:** https://github.com/mizua/vn-pathfinder
- **Flutter Docs:** https://flutter.dev
- **Material 3 Design:** https://m3.material.io/

---

## 📞 Status & Roadmap Updates

For development updates and status, follow this repository's commit history and Issues tab.

---

**Made with ❤️ by NikoCloud** — Building the best VN library manager, one version at a time.
