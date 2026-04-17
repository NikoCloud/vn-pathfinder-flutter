/* ═══════════════════════════════════════════════════════════════════
   VN Pathfinder 2.0 — Mockup Application Logic (v2)
   ═══════════════════════════════════════════════════════════════════ */

// ── GRADIENTS for no-art entries ─────────────────────────────────────
const GRADIENTS = [
  "linear-gradient(135deg, #1a2332, #2a3545)",
  "linear-gradient(135deg, #2d1f2f, #3a2545)",
  "linear-gradient(135deg, #1a2a1a, #2a3a2a)",
  "linear-gradient(135deg, #2a2215, #3a3225)",
  "linear-gradient(135deg, #1a2a33, #2a3a45)",
];

// ── ALL TAGS (for filter dropdowns) ──────────────────────────────────
const ALL_TAGS = [
  "Romance", "Comedy", "Drama", "Fantasy", "Mystery",
  "Slice of Life", "Horror", "Sci-Fi", "Action", "Thriller",
  "School Setting", "Harem", "NTR", "Corruption", "Incest",
  "Male Protagonist", "Female Protagonist", "Monster Girl",
  "Animated", "Sandbox", "Management", "Trainer"
];

// ── MOCK DATA ────────────────────────────────────────────────────────
const GAMES = [
  {
    id: 1,
    title: "Midnight Paradise",
    developer: "PixelBee Studio",
    engine: "renpy",
    status: "playing",
    version: "v0.18 Elite",
    versions: [
      { label: "v0.18 Elite", path: "D:\\Games\\VNs\\MidnightParadise-v0.18", modified: "2026-04-10", saves: 23 },
      { label: "v0.17", path: "D:\\Games\\VNs\\MidnightParadise-v0.17", modified: "2026-03-15", saves: 18 },
    ],
    cover: "assets/cover_1.png",
    banner: "assets/hero_banner.png",
    screenshots: ["assets/cover_1.png", "assets/cover_2.png", "assets/cover_3.png", "assets/cover_4.png"],
    tags: ["Romance", "Drama", "Harem", "Male Protagonist"],
    played: true,
    lastPlayed: "2 hours ago",
    playTime: "42h 15m",
    playCount: 8,
    diskSize: "2.4 GB",
    synopsis: "Step into the shoes of a young man who returns to his childhood home after years away. Rekindle old friendships, forge new bonds, and navigate the complex web of relationships in a sun-drenched coastal town. Every choice matters as secrets from the past surface and passions ignite.",
    path: "D:\\Games\\VNs\\MidnightParadise-v0.18",
    sources: [
      { name: "F95Zone Thread", url: "https://f95zone.to/threads/midnight-paradise.12345/" },
      { name: "itch.io", url: "https://example.itch.io/midnight-paradise" },
    ],
    patches: [
      { name: "UHD Texture Pack", type: "rpa", status: "active", version: "v0.18 Elite" },
      { name: "Translation - JP", type: "rpy", status: "active", version: "v0.18 Elite" },
      { name: "Old Walkthrough Mod", type: "rpy", status: "parked", version: "v0.17" },
    ],
    notes: "Incredible writing in Chapter 3. Need to check walkthrough for hidden scene in the lighthouse.",
  },
  {
    id: 2,
    title: "Ethereal Academy",
    developer: "StardustGames",
    engine: "renpy",
    status: "playing",
    version: "v0.9.1",
    versions: [
      { label: "v0.9.1", path: "D:\\Games\\VNs\\EtherealAcademy-v0.9.1", modified: "2026-04-08", saves: 14 },
    ],
    cover: "assets/cover_2.png",
    banner: "assets/cover_2.png",
    screenshots: ["assets/cover_2.png", "assets/cover_5.png"],
    tags: ["Romance", "Slice of Life", "School Setting", "Comedy"],
    played: true,
    lastPlayed: "Yesterday",
    playTime: "28h 40m",
    playCount: 4,
    diskSize: "1.8 GB",
    synopsis: "A slice-of-life visual novel set in a prestigious academy where students discover hidden talents. Navigate classes, clubs, and social dynamics while building meaningful connections. Features multiple branching storylines and diverse character interactions.",
    path: "D:\\Games\\VNs\\EtherealAcademy-v0.9.1",
    sources: [
      { name: "F95Zone Thread", url: "https://f95zone.to/threads/ethereal-academy.67890/" },
    ],
    patches: [],
    notes: "",
  },
  {
    id: 3,
    title: "Crimson Twilight",
    developer: "NovaForge",
    engine: "renpy",
    status: "on-hold",
    version: "v0.12",
    versions: [
      { label: "v0.12", path: "D:\\Games\\VNs\\CrimsonTwilight-v0.12", modified: "2026-03-20", saves: 7 },
    ],
    cover: "assets/cover_3.png",
    banner: "assets/cover_3.png",
    screenshots: ["assets/cover_3.png", "assets/cover_1.png", "assets/cover_4.png"],
    tags: ["Drama", "Mystery", "Thriller", "Horror"],
    played: true,
    lastPlayed: "3 days ago",
    playTime: "15h 22m",
    playCount: 3,
    diskSize: "3.1 GB",
    synopsis: "A dark, atmospheric narrative set in a mysterious coastal town. Strange events unfold as you investigate the disappearance of local residents. Uncover conspiracies, face moral dilemmas, and decide who to trust in a world where nothing is as it seems.",
    path: "D:\\Games\\VNs\\CrimsonTwilight-v0.12",
    sources: [],
    patches: [
      { name: "Uncensor Patch", type: "rpa", status: "active", version: "v0.12" },
    ],
    notes: "",
  },
  {
    id: 4,
    title: "Summer's Gone",
    developer: "GoldenBoy",
    engine: "renpy",
    status: "completed",
    version: "v0.5",
    versions: [
      { label: "v0.5", path: "D:\\Games\\VNs\\SummersGone-v0.5", modified: "2026-02-28", saves: 32 },
      { label: "v0.4", path: "D:\\Games\\VNs\\SummersGone-v0.4", modified: "2026-01-15", saves: 20 },
      { label: "v0.3", path: "D:\\Games\\VNs\\SummersGone-v0.3", modified: "2025-11-20", saves: 11 },
    ],
    cover: "assets/cover_4.png",
    banner: "assets/cover_4.png",
    screenshots: ["assets/cover_4.png", "assets/cover_2.png"],
    tags: ["Romance", "Slice of Life", "Comedy", "Male Protagonist"],
    played: true,
    lastPlayed: "4 days ago",
    playTime: "55h 03m",
    playCount: 12,
    diskSize: "1.2 GB",
    synopsis: "A heartfelt coming-of-age story. Navigate relationships, summer jobs, and personal growth during the most transformative summer of your life. Features rich character development and multiple endings based on your choices.",
    path: "D:\\Games\\VNs\\SummersGone-v0.5",
    sources: [
      { name: "F95Zone Thread", url: "https://f95zone.to/threads/summers-gone.11111/" },
      { name: "VNDB Page", url: "https://vndb.org/v99999" },
      { name: "itch.io", url: "https://example.itch.io/summers-gone" },
    ],
    patches: [],
    notes: "One of the best. Replayed multiple times for every route.",
  },
  {
    id: 5,
    title: "Starlight Carnival",
    developer: "LunarSoft",
    engine: "rpgm",
    status: "unplayed",
    version: "v1.2",
    versions: [
      { label: "v1.2", path: "D:\\Games\\VNs\\StarlightCarnival-v1.2", modified: "2026-04-01", saves: 0 },
    ],
    cover: "assets/cover_5.png",
    banner: "assets/cover_5.png",
    screenshots: ["assets/cover_5.png"],
    tags: ["Fantasy", "Comedy", "Animated", "Sandbox"],
    played: false,
    lastPlayed: "Never",
    playTime: "0h",
    playCount: 0,
    diskSize: "820 MB",
    synopsis: "A whimsical RPGM adventure set in a magical carnival. Explore themed worlds, meet colorful characters, and uncover the carnival's secret purpose.",
    path: "D:\\Games\\VNs\\StarlightCarnival-v1.2",
    sources: [
      { name: "F95Zone Thread", url: "https://f95zone.to/threads/starlight-carnival.22222/" },
    ],
    patches: [],
    notes: "",
  },
  {
    id: 6,
    title: "Neon Desire",
    developer: "CyberVoid",
    engine: "unity",
    status: "playing",
    version: "v0.3",
    versions: [
      { label: "v0.3", path: "D:\\Games\\VNs\\NeonDesire-v0.3", modified: "2026-04-05", saves: 5 },
    ],
    cover: null,
    banner: null,
    screenshots: [],
    tags: ["Sci-Fi", "Action", "Thriller"],
    played: true,
    lastPlayed: "5 days ago",
    playTime: "8h 15m",
    playCount: 2,
    diskSize: "4.2 GB",
    synopsis: "Cyberpunk visual novel set in a neon-lit megacity. Navigate corporate intrigue, underground markets, and dangerous alliances.",
    path: "D:\\Games\\VNs\\NeonDesire-v0.3",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 7,
    title: "Forgotten Shores",
    developer: "MistyIsle Dev",
    engine: "renpy",
    status: "unplayed",
    version: "v0.7",
    versions: [
      { label: "v0.7", path: "D:\\Games\\VNs\\ForgottenShores-v0.7", modified: "2026-03-28", saves: 0 },
    ],
    cover: null,
    banner: null,
    screenshots: [],
    tags: ["Mystery", "Drama", "Romance"],
    played: false,
    lastPlayed: "Never",
    playTime: "0h",
    playCount: 0,
    diskSize: "1.5 GB",
    synopsis: "Return to a remote island community where old wounds resurface. A mystery narrative with branching paths and multiple suspects.",
    path: "D:\\Games\\VNs\\ForgottenShores-v0.7",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 8,
    title: "Velvet Rose",
    developer: "Silk Studios",
    engine: "renpy",
    status: "completed",
    version: "v1.0",
    versions: [
      { label: "v1.0", path: "D:\\Games\\VNs\\VelvetRose-v1.0", modified: "2026-01-10", saves: 42 },
    ],
    cover: null,
    banner: null,
    screenshots: [],
    tags: ["Romance", "Drama", "Corruption", "Female Protagonist"],
    played: true,
    lastPlayed: "1 month ago",
    playTime: "18h 30m",
    playCount: 5,
    diskSize: "980 MB",
    synopsis: "A mature romance visual novel exploring complex relationships and power dynamics. Multiple paths lead to vastly different outcomes.",
    path: "D:\\Games\\VNs\\VelvetRose-v1.0",
    sources: [],
    patches: [],
    notes: "Finished all routes.",
  },
  {
    id: 9,
    title: "Project Snowfall",
    developer: "FrostByte Interactive",
    engine: "unreal",
    status: "abandoned",
    version: "v0.2a",
    versions: [
      { label: "v0.2a", path: "D:\\Games\\VNs\\ProjectSnowfall-v0.2a", modified: "2025-12-01", saves: 2 },
    ],
    cover: null,
    banner: null,
    screenshots: [],
    tags: ["Sci-Fi", "Thriller", "Horror"],
    played: true,
    lastPlayed: "2 months ago",
    playTime: "3h 10m",
    playCount: 1,
    diskSize: "6.8 GB",
    synopsis: "A sci-fi horror experience built on Unreal Engine. Atmospheric environments and branching narrative.",
    path: "D:\\Games\\VNs\\ProjectSnowfall-v0.2a",
    sources: [],
    patches: [],
    notes: "Dev abandoned. Too short to invest more time.",
  },
  {
    id: 10,
    title: "Heartstrings",
    developer: "Pixel Hearts",
    engine: "renpy",
    status: "playing",
    version: "v0.14",
    versions: [
      { label: "v0.14", path: "D:\\Games\\VNs\\Heartstrings-v0.14", modified: "2026-04-14", saves: 11 },
    ],
    cover: null,
    banner: null,
    screenshots: [],
    tags: ["Romance", "Comedy", "Slice of Life", "Harem"],
    played: true,
    lastPlayed: "6 days ago",
    playTime: "22h 45m",
    playCount: 3,
    diskSize: "1.1 GB",
    synopsis: "A lighthearted romantic comedy with an ensemble cast. Build relationships through meaningful choices and hilarious situations.",
    path: "D:\\Games\\VNs\\Heartstrings-v0.14",
    sources: [
      { name: "F95Zone Thread", url: "#" },
    ],
    patches: [],
    notes: "",
  },
  {
    id: 11,
    title: "Shadow Protocol",
    developer: "DarkOps",
    engine: "rpgm",
    status: "on-hold",
    version: "v0.6",
    versions: [
      { label: "v0.6", path: "D:\\Games\\VNs\\ShadowProtocol-v0.6", modified: "2026-02-20", saves: 4 },
    ],
    cover: null, banner: null, screenshots: [],
    tags: ["Action", "Thriller", "Mystery", "Sandbox"],
    played: true,
    lastPlayed: "1 week ago",
    playTime: "6h 30m",
    playCount: 1,
    diskSize: "740 MB",
    synopsis: "Spy thriller with RPG elements. Infiltrate facilities, hack systems, and make choices that affect the geopolitical landscape.",
    path: "D:\\Games\\VNs\\ShadowProtocol-v0.6",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 12,
    title: "Moonlit Echoes",
    developer: "EchoSoft",
    engine: "html",
    status: "unplayed",
    version: "v0.4",
    versions: [
      { label: "v0.4", path: "D:\\Games\\VNs\\MoonlitEchoes-v0.4", modified: "2026-03-05", saves: 0 },
    ],
    cover: null, banner: null, screenshots: [],
    tags: ["Fantasy", "Romance", "Mystery"],
    played: false,
    lastPlayed: "Never",
    playTime: "0h",
    playCount: 0,
    diskSize: "280 MB",
    synopsis: "An HTML-based interactive fiction set in a moonlit forest. Solve puzzles and forge alliances with mythical creatures.",
    path: "D:\\Games\\VNs\\MoonlitEchoes-v0.4",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 13,
    title: "Campus Dreams",
    developer: "UniquePixels",
    engine: "renpy",
    status: "playing",
    version: "v0.8",
    versions: [
      { label: "v0.8", path: "D:\\Games\\VNs\\CampusDreams-v0.8", modified: "2026-04-12", saves: 9 },
    ],
    cover: null, banner: null, screenshots: [],
    tags: ["Romance", "Comedy", "School Setting", "Male Protagonist"],
    played: true,
    lastPlayed: "3 weeks ago",
    playTime: "14h 20m",
    playCount: 2,
    diskSize: "1.3 GB",
    synopsis: "College life VN with a focus on character-driven storytelling. Balance academics, social life, and romantic pursuits.",
    path: "D:\\Games\\VNs\\CampusDreams-v0.8",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 14,
    title: "Arcane Legacy",
    developer: "RuneForge",
    engine: "renpy",
    status: "unplayed",
    version: "v0.3.2",
    versions: [
      { label: "v0.3.2", path: "D:\\Games\\VNs\\ArcaneLegacy-v0.3.2", modified: "2026-03-10", saves: 0 },
    ],
    cover: null, banner: null, screenshots: [],
    tags: ["Fantasy", "Action", "Harem", "Monster Girl"],
    played: false,
    lastPlayed: "Never",
    playTime: "0h",
    playCount: 0,
    diskSize: "2.0 GB",
    synopsis: "Fantasy VN with RPG elements. Explore dungeons, master arcane spells, and build a party of allies.",
    path: "D:\\Games\\VNs\\ArcaneLegacy-v0.3.2",
    sources: [],
    patches: [],
    notes: "",
  },
  {
    id: 15,
    title: "After Hours",
    developer: "NightOwl Games",
    engine: "renpy",
    status: "completed",
    version: "v1.0.2",
    versions: [
      { label: "v1.0.2", path: "D:\\Games\\VNs\\AfterHours-v1.0.2", modified: "2025-11-30", saves: 28 },
    ],
    cover: null, banner: null, screenshots: [],
    tags: ["Drama", "Romance", "Slice of Life", "NTR"],
    played: true,
    lastPlayed: "2 months ago",
    playTime: "31h 10m",
    playCount: 7,
    diskSize: "1.6 GB",
    synopsis: "Mature drama set in urban nightlife. Navigate complex relationships and moral grey areas.",
    path: "D:\\Games\\VNs\\AfterHours-v1.0.2",
    sources: [],
    patches: [],
    notes: "",
  }
];

// ── STATE ────────────────────────────────────────────────────────────
let selectedGameId = 1;
let currentView = "library";
let isGridView = false;
let lockdownActive = true;
let currentCarouselIndex = 0;
let carouselInterval = null;

// Filter state
let filterText = "";
let filterSearchMode = "title"; // "title" or "creator"
let filterTags = [];
let filterExcludeTags = [];
let filterTagMode = "or"; // "or" or "and"
let filterEngines = new Set(["renpy", "rpgm", "unity", "html", "unreal", "other"]);
let filterStatuses = new Set(["playing", "completed", "on-hold", "unplayed", "abandoned"]);

// ── INIT ─────────────────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  populateFilterDropdowns();
  renderSidebar();
  selectGame(1);
  bindNavTabs();
  bindViewToggle();
  bindSettingsTabs();
  bindPropertiesTabs();
  bindModalSystem();
  bindContextMenu();
  bindLightbox();
  bindToggles();
  bindSearch();
  bindSort();
  bindFilterPanel();
  updateLockdownUI();
});

// ── FILTER LOGIC ─────────────────────────────────────────────────────
function populateFilterDropdowns() {
  const tagMenu = document.getElementById("tag-filter-menu");
  const excludeMenu = document.getElementById("exclude-filter-menu");
  const gridTagMenu = document.getElementById("grid-tag-menu");
  const gridExcludeMenu = document.getElementById("grid-exclude-menu");

  // Count tag occurrences
  const tagCounts = {};
  ALL_TAGS.forEach(t => { tagCounts[t] = GAMES.filter(g => g.tags.includes(t)).length; });

  const makeOptions = (menu, type) => {
    menu.innerHTML = "";
    ALL_TAGS.forEach(tag => {
      const opt = document.createElement("div");
      opt.className = "filter-dropdown-option";
      opt.dataset.tag = tag;
      opt.dataset.type = type;
      opt.innerHTML = `<span>${tag}</span><span class="count">${tagCounts[tag]}</span>`;
      opt.addEventListener("click", (e) => {
        e.stopPropagation();
        toggleFilterTag(tag, type);
      });
      menu.appendChild(opt);
    });
  };

  makeOptions(tagMenu, "include");
  makeOptions(excludeMenu, "exclude");
  makeOptions(gridTagMenu, "include");
  makeOptions(gridExcludeMenu, "exclude");
}

function toggleFilterTag(tag, type) {
  const arr = type === "include" ? filterTags : filterExcludeTags;
  const idx = arr.indexOf(tag);
  if (idx >= 0) {
    arr.splice(idx, 1);
  } else {
    if (arr.length >= 10) {
      showToast("Maximum 10 filter tags", "warning");
      return;
    }
    arr.push(tag);
  }
  updateFilterChips();
  applyFilters();
}

function updateFilterChips() {
  // Include chips
  const chipContainer = document.getElementById("tag-filter-chips");
  chipContainer.innerHTML = "";
  filterTags.forEach(tag => {
    const chip = document.createElement("span");
    chip.className = "filter-chip";
    chip.innerHTML = `${tag} <span class="remove" data-tag="${tag}" data-type="include">✕</span>`;
    chip.querySelector(".remove").addEventListener("click", (e) => {
      e.stopPropagation();
      toggleFilterTag(tag, "include");
    });
    chipContainer.appendChild(chip);
  });

  // Exclude chips
  const exContainer = document.getElementById("exclude-filter-chips");
  exContainer.innerHTML = "";
  filterExcludeTags.forEach(tag => {
    const chip = document.createElement("span");
    chip.className = "filter-chip exclude";
    chip.innerHTML = `−${tag} <span class="remove" data-tag="${tag}" data-type="exclude">✕</span>`;
    chip.querySelector(".remove").addEventListener("click", (e) => {
      e.stopPropagation();
      toggleFilterTag(tag, "exclude");
    });
    exContainer.appendChild(chip);
  });

  // Update dropdown selection indicators
  document.querySelectorAll(".filter-dropdown-option").forEach(opt => {
    const tag = opt.dataset.tag;
    const type = opt.dataset.type;
    if (type === "include") {
      opt.classList.toggle("selected", filterTags.includes(tag));
    } else {
      opt.classList.toggle("selected", filterExcludeTags.includes(tag));
    }
  });
}

function getFilteredGames() {
  return GAMES.filter(game => {
    // Text filter
    if (filterText) {
      const target = filterSearchMode === "title" ? game.title : game.developer;
      if (!target.toLowerCase().includes(filterText.toLowerCase())) return false;
    }

    // Tag include filter
    if (filterTags.length > 0) {
      if (filterTagMode === "and") {
        if (!filterTags.every(t => game.tags.includes(t))) return false;
      } else {
        if (!filterTags.some(t => game.tags.includes(t))) return false;
      }
    }

    // Tag exclude filter
    if (filterExcludeTags.length > 0) {
      if (filterExcludeTags.some(t => game.tags.includes(t))) return false;
    }

    // Engine filter
    if (!filterEngines.has(game.engine)) return false;

    // Status filter
    if (!filterStatuses.has(game.status)) return false;

    return true;
  });
}

function applyFilters() {
  renderSidebar();
  if (isGridView) renderGridView();
}

// ── SIDEBAR RENDERING ────────────────────────────────────────────────
function renderSidebar() {
  const gameList = document.getElementById("game-list");
  gameList.innerHTML = "";

  const filtered = getFilteredGames();

  // Update result counts
  document.getElementById("filter-result-count").textContent = `${filtered.length} Result${filtered.length !== 1 ? "s" : ""}`;
  document.getElementById("grid-result-count").textContent = `${filtered.length} Result${filtered.length !== 1 ? "s" : ""}`;

  filtered.forEach(game => {
    const entry = document.createElement("div");
    entry.className = `game-entry ${game.id === selectedGameId ? "selected" : ""}`;
    entry.dataset.gameId = game.id;

    const thumbClass = game.cover ? "" : "no-art";
    const gradientIdx = (game.id - 1) % GRADIENTS.length;

    entry.innerHTML = `
      <div class="game-entry-thumb ${thumbClass}" ${!game.cover ? `style="background:${GRADIENTS[gradientIdx]}"` : ""}>
        ${game.cover ? `<img src="${game.cover}" alt="${game.title}">` : ""}
      </div>
      <div class="game-entry-info">
        <div class="game-entry-title">${game.title}</div>
        <div class="game-entry-meta">${game.developer} · ${game.version}</div>
      </div>
      <div class="game-entry-status ${game.played ? "played" : "unplayed"}"></div>
    `;

    entry.addEventListener("click", () => selectGame(game.id));
    entry.addEventListener("contextmenu", (e) => showContextMenu(e, game.id));
    gameList.appendChild(entry);
  });
}

// ── SELECT GAME ──────────────────────────────────────────────────────
function selectGame(id) {
  selectedGameId = id;

  // Update sidebar selection
  document.querySelectorAll(".game-entry").forEach(e => {
    e.classList.toggle("selected", parseInt(e.dataset.gameId) === id);
  });

  const game = GAMES.find(g => g.id === id);
  if (!game) return;

  // Hero banner
  const heroBg = document.getElementById("hero-bg");
  if (game.banner) {
    heroBg.style.backgroundImage = `url('${game.banner}')`;
  } else {
    const idx = (game.id - 1) % GRADIENTS.length;
    heroBg.style.backgroundImage = "none";
    heroBg.style.background = GRADIENTS[idx];
  }

  document.getElementById("hero-title").textContent = game.title;
  document.getElementById("hero-developer").textContent = game.developer;

  // Version selector
  const versionSelect = document.getElementById("version-selector");
  versionSelect.innerHTML = "";
  game.versions.forEach((v, i) => {
    const opt = document.createElement("option");
    opt.value = v.label;
    opt.textContent = v.label;
    if (i === 0) opt.selected = true;
    versionSelect.appendChild(opt);
  });

  // Metadata bar
  document.getElementById("meta-size").textContent = game.diskSize;
  document.getElementById("meta-played").textContent = game.lastPlayed;
  document.getElementById("meta-playtime").textContent = game.playTime;
  document.getElementById("meta-count").textContent = game.playCount;
  document.getElementById("meta-version").textContent = game.version;

  // Synopsis
  document.getElementById("detail-synopsis").textContent = game.synopsis;

  // Tags
  const tagsContainer = document.getElementById("detail-tags");
  tagsContainer.innerHTML = "";

  const tagTypeMap = {
    "Romance": "genre", "Comedy": "genre", "Drama": "genre", "Fantasy": "genre",
    "Mystery": "genre", "Slice of Life": "genre", "Horror": "genre", "Sci-Fi": "genre",
    "Action": "genre", "Thriller": "genre",
    "School Setting": "custom", "Male Protagonist": "custom", "Female Protagonist": "custom",
    "Monster Girl": "custom", "Animated": "custom", "Sandbox": "custom",
    "Management": "custom", "Trainer": "custom",
    "Harem": "status", "NTR": "warning-tag", "Corruption": "warning-tag", "Incest": "warning-tag",
  };

  // Add tag button FIRST — fixed position for consistent UX regardless of tag count
  const addBtn = document.createElement("button");
  addBtn.className = "btn-square small";
  addBtn.textContent = "＋";
  addBtn.dataset.tooltip = "Add or manage tags";
  addBtn.addEventListener("click", () => showToast("Tag picker dialog would open", "info"));
  tagsContainer.appendChild(addBtn);

  game.tags.forEach(tag => {
    const chip = document.createElement("span");
    chip.className = `tag-chip ${tagTypeMap[tag] || "custom"}`;
    chip.textContent = tag;
    tagsContainer.appendChild(chip);
  });

  // Source Pages dropdown
  const sourceMenu = document.getElementById("source-dropdown-menu");
  sourceMenu.innerHTML = "";
  if (game.sources.length > 0) {
    game.sources.forEach(s => {
      const item = document.createElement("div");
      item.className = "source-dropdown-item";
      item.innerHTML = `🔗 ${s.name}`;
      item.addEventListener("click", () => {
        showToast(`Opening: ${s.url}`, "info");
        sourceMenu.classList.remove("open");
      });
      sourceMenu.appendChild(item);
    });
  } else {
    sourceMenu.innerHTML = `<div class="source-dropdown-empty">No linked sources. Use Fetch Metadata to add.</div>`;
  }

  // Notes
  document.getElementById("detail-notes").value = game.notes || "";

  // Carousel
  renderCarousel(game);

  // Properties modal population
  document.getElementById("properties-title").textContent = `⚙ ${game.title} — Properties`;
  document.getElementById("prop-name").value = game.title;
  document.getElementById("prop-dev").value = game.developer;
  document.getElementById("prop-path").textContent = game.versions[0].path;
  document.getElementById("prop-notes").value = game.notes || "";

  // Versions table
  const tbody = document.querySelector("#prop-version-table tbody");
  tbody.innerHTML = "";
  game.versions.forEach((v, i) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="${i === 0 ? "version-active" : ""}">${v.label}${i === 0 ? " ✓" : ""}</td>
      <td class="path-cell" data-tooltip="${v.path}">${v.path}</td>
      <td>${v.modified}</td>
      <td>${v.saves}</td>
    `;
    tbody.appendChild(tr);
  });

  // Patches tab version dropdown
  const patchVersionSelect = document.getElementById("prop-patch-version");
  patchVersionSelect.innerHTML = "";
  game.versions.forEach((v, i) => {
    const opt = document.createElement("option");
    opt.value = v.label;
    opt.textContent = v.label;
    if (i === 0) opt.selected = true;
    patchVersionSelect.appendChild(opt);
  });

  // Patches list
  renderPatches(game);
}

function renderPatches(game) {
  const patchList = document.getElementById("prop-patch-list");
  patchList.innerHTML = "";

  const selectedVersion = document.getElementById("prop-patch-version").value;
  const patches = game.patches.filter(p => p.version === selectedVersion);

  if (patches.length === 0) {
    patchList.innerHTML = `<p class="text-sm text-muted" style="padding: 12px;">No patches assigned to this version.</p>`;
    return;
  }

  patches.forEach(p => {
    const item = document.createElement("div");
    item.className = "patch-item";
    item.innerHTML = `
      <span class="patch-name">${p.name}</span>
      <span class="patch-type ${p.type}">.${p.type}</span>
      <span class="patch-badge ${p.status}">${p.status === "active" ? "Active" : "Parked"}</span>
      <button class="btn-action secondary" style="padding: 4px 10px; font-size: 10px;"
              data-tooltip="${p.status === "active" ? "Deactivate patch" : "Activate patch"}">
        ${p.status === "active" ? "Disable" : "Enable"}
      </button>
    `;
    patchList.appendChild(item);
  });
}

// ── CAROUSEL ─────────────────────────────────────────────────────────
function renderCarousel(game) {
  clearInterval(carouselInterval);
  currentCarouselIndex = 0;

  const track = document.getElementById("carousel-track");
  const dots = document.getElementById("carousel-dots");
  const carousel = document.getElementById("hero-carousel");

  track.innerHTML = "";
  dots.innerHTML = "";

  if (!game.screenshots || game.screenshots.length === 0) {
    carousel.style.display = "none";
    return;
  }

  carousel.style.display = "flex";

  game.screenshots.forEach((src, i) => {
    // Slide
    const slide = document.createElement("div");
    slide.className = "hero-carousel-slide";
    slide.innerHTML = `<img src="${src}" alt="Screenshot ${i + 1}">`;
    slide.addEventListener("click", () => openLightbox(i));
    track.appendChild(slide);

    // Dot
    const dot = document.createElement("div");
    dot.className = "hero-carousel-dot";
    dot.addEventListener("click", () => goToSlide(i));
    dots.appendChild(dot);
  });

  updateCarouselSlides();
  startCarouselAutoAdvance();
}

function updateCarouselSlides() {
  const slides = document.querySelectorAll(".hero-carousel-slide");
  const dots = document.querySelectorAll(".hero-carousel-dot");

  slides.forEach((slide, i) => {
    slide.className = "hero-carousel-slide";
    if (i === currentCarouselIndex) {
      slide.classList.add("active");
    } else if (i === getPrevIndex(slides.length)) {
      slide.classList.add("peek-prev");
    } else if (i === getNextIndex(slides.length)) {
      slide.classList.add("peek-next");
    }
  });

  dots.forEach((dot, i) => {
    dot.classList.toggle("active", i === currentCarouselIndex);
  });
}

function getPrevIndex(total) {
  return (currentCarouselIndex - 1 + total) % total;
}

function getNextIndex(total) {
  return (currentCarouselIndex + 1) % total;
}

function goToSlide(index) {
  const slides = document.querySelectorAll(".hero-carousel-slide");
  if (slides.length === 0) return;
  currentCarouselIndex = index;
  updateCarouselSlides();
  restartCarouselTimer();
}

function startCarouselAutoAdvance() {
  carouselInterval = setInterval(() => {
    const slides = document.querySelectorAll(".hero-carousel-slide");
    if (slides.length <= 1) return;
    currentCarouselIndex = getNextIndex(slides.length);
    updateCarouselSlides();
  }, 5000);
}

function restartCarouselTimer() {
  clearInterval(carouselInterval);
  startCarouselAutoAdvance();
}

// ── GRID VIEW ────────────────────────────────────────────────────────
function renderGridView() {
  const grid = document.getElementById("grid-container");
  grid.innerHTML = "";

  const filtered = getFilteredGames();

  filtered.forEach(game => {
    const card = document.createElement("div");
    card.className = `grid-card ${!game.cover ? "no-art" : ""}`;
    card.dataset.gameId = game.id;

    if (game.cover) {
      card.innerHTML = `
        <img src="${game.cover}" alt="${game.title}">
        <div class="grid-card-overlay">
          <div class="grid-card-title">${game.title}</div>
          <div class="grid-card-dev">${game.developer}</div>
        </div>
      `;
    } else {
      const gradientIdx = (game.id - 1) % GRADIENTS.length;
      card.style.background = GRADIENTS[gradientIdx];
      card.innerHTML = `
        <div class="grid-card-placeholder">🎮</div>
        <div class="grid-card-overlay" style="opacity:1; background: linear-gradient(to top, rgba(0,0,0,0.85) 0%, transparent 70%);">
          <div class="grid-card-title">${game.title}</div>
          <div class="grid-card-dev">${game.developer}</div>
        </div>
      `;
    }

    card.addEventListener("click", () => {
      selectGame(game.id);
      toggleGridView(false);
    });
    card.addEventListener("contextmenu", (e) => showContextMenu(e, game.id));
    grid.appendChild(card);
  });
}

// ── VIEW SWITCHING ───────────────────────────────────────────────────
function switchView(view) {
  currentView = view;

  document.querySelectorAll(".nav-tab").forEach(tab => {
    tab.classList.toggle("active", tab.dataset.view === view);
  });

  document.getElementById("library-view").classList.toggle("active", view === "library" && !isGridView);
  document.getElementById("grid-view-container").classList.toggle("active", view === "library" && isGridView);
  document.getElementById("archive-view-container").classList.toggle("active", view === "archive");

  const sidebar = document.getElementById("sidebar");
  if (view === "library") {
    sidebar.style.display = isGridView ? "none" : "flex";
  } else {
    sidebar.style.display = "none";
  }

  if (view === "archive") {
    renderArchiveList();
  }
}

function toggleGridView(toGrid) {
  isGridView = toGrid;
  document.getElementById("list-view-btn").classList.toggle("active", !toGrid);
  document.getElementById("grid-view-btn").classList.toggle("active", toGrid);

  if (toGrid) {
    // Sync grid search
    document.getElementById("grid-search-input").value = document.getElementById("search-input").value;
    renderGridView();
  }

  switchView("library");
}

// ── BINDINGS ─────────────────────────────────────────────────────────
function bindNavTabs() {
  document.querySelectorAll(".nav-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      isGridView = false;
      document.getElementById("list-view-btn").classList.add("active");
      document.getElementById("grid-view-btn").classList.remove("active");
      switchView(tab.dataset.view);
    });
  });
}

function bindSettingsTabs() {
  document.querySelectorAll("[data-settings-tab]").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("[data-settings-tab]").forEach(t => t.classList.remove("active"));
      document.querySelectorAll("#settings-modal .settings-panel").forEach(p => p.classList.remove("active"));
      tab.classList.add("active");
      document.getElementById(`settings-${tab.dataset.settingsTab}`).classList.add("active");
    });
  });
}

function bindPropertiesTabs() {
  document.querySelectorAll("[data-props-tab]").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("[data-props-tab]").forEach(t => t.classList.remove("active"));
      document.querySelectorAll("#properties-modal .settings-panel").forEach(p => p.classList.remove("active"));
      tab.classList.add("active");
      document.getElementById(tab.dataset.propsTab).classList.add("active");
    });
  });

  // Patch version dropdown change
  document.getElementById("prop-patch-version").addEventListener("change", () => {
    const game = GAMES.find(g => g.id === selectedGameId);
    if (game) renderPatches(game);
  });
}

function bindViewToggle() {
  document.getElementById("list-view-btn").addEventListener("click", () => toggleGridView(false));
  document.getElementById("grid-view-btn").addEventListener("click", () => toggleGridView(true));
  // Grid-to-list toggle in grid filter bar
  document.getElementById("grid-to-list-btn").addEventListener("click", () => toggleGridView(false));
}

// ── FILTER PANEL BINDINGS ────────────────────────────────────────────
function bindFilterPanel() {
  // Search mode toggle (TITLE / CREATOR)
  const searchModeBtn = document.getElementById("search-mode-toggle");
  searchModeBtn.addEventListener("click", () => {
    filterSearchMode = filterSearchMode === "title" ? "creator" : "title";
    searchModeBtn.textContent = filterSearchMode.toUpperCase();
    document.getElementById("search-input").placeholder = `Search ${filterSearchMode}s...`;
    applyFilters();
  });

  // Tag mode toggle (OR / AND)
  const tagModeBtn = document.getElementById("tag-mode-toggle");
  tagModeBtn.addEventListener("click", () => {
    filterTagMode = filterTagMode === "or" ? "and" : "or";
    tagModeBtn.textContent = filterTagMode.toUpperCase();
    applyFilters();
  });

  // Dropdown triggers
  const bindDropdown = (triggerId, menuId) => {
    const trigger = document.getElementById(triggerId);
    const menu = document.getElementById(menuId);
    trigger.addEventListener("click", (e) => {
      e.stopPropagation();
      // Close other dropdowns
      document.querySelectorAll(".filter-dropdown-menu.open").forEach(m => {
        if (m.id !== menuId) m.classList.remove("open");
      });
      menu.classList.toggle("open");
    });
  };

  bindDropdown("tag-filter-trigger", "tag-filter-menu");
  bindDropdown("exclude-filter-trigger", "exclude-filter-menu");
  bindDropdown("grid-tag-trigger", "grid-tag-menu");
  bindDropdown("grid-exclude-trigger", "grid-exclude-menu");

  // Close dropdowns on outside click
  document.addEventListener("click", () => {
    document.querySelectorAll(".filter-dropdown-menu.open").forEach(m => m.classList.remove("open"));
    document.querySelectorAll(".source-dropdown-menu.open").forEach(m => m.classList.remove("open"));
  });

  // Collapsible sections
  const bindCollapsible = (headerId, bodyId) => {
    const header = document.getElementById(headerId);
    const body = document.getElementById(bodyId);
    header.addEventListener("click", () => {
      header.classList.toggle("collapsed");
      body.classList.toggle("hidden");
    });
  };

  bindCollapsible("engine-filter-header", "engine-filter-body");
  bindCollapsible("status-filter-header", "status-filter-body");

  // Engine checkboxes
  document.querySelectorAll("#engine-filter-body input[type='checkbox']").forEach(cb => {
    cb.addEventListener("change", () => {
      if (cb.checked) {
        filterEngines.add(cb.value);
      } else {
        filterEngines.delete(cb.value);
      }
      applyFilters();
    });
  });

  // Status checkboxes
  document.querySelectorAll("#status-filter-body input[type='checkbox']").forEach(cb => {
    cb.addEventListener("change", () => {
      if (cb.checked) {
        filterStatuses.add(cb.value);
      } else {
        filterStatuses.delete(cb.value);
      }
      applyFilters();
    });
  });

  // Source pages dropdown
  document.getElementById("source-dropdown-btn").addEventListener("click", (e) => {
    e.stopPropagation();
    document.getElementById("source-dropdown-menu").classList.toggle("open");
  });

  // Grid search sync
  document.getElementById("grid-search-input").addEventListener("input", (e) => {
    filterText = e.target.value;
    document.getElementById("search-input").value = filterText;
    applyFilters();
  });
}

// ── MODAL SYSTEM ─────────────────────────────────────────────────────
function bindModalSystem() {
  document.getElementById("settings-btn").addEventListener("click", () => openModal("settings-modal"));

  // Secondary modal from inside settings
  document.getElementById("trigger-orphan-modal-btn").addEventListener("click", () => {
    openModal("orphan-modal");
  });

  document.getElementById("fetch-metadata-btn").addEventListener("click", () => {
    if (lockdownActive) {
      showToast("Network is locked down. Disable Lockdown Mode in Settings first.", "error");
      return;
    }
    openModal("fetch-modal");
  });

  document.getElementById("properties-btn").addEventListener("click", () => openModal("properties-modal"));

  document.querySelectorAll("[data-close-modal]").forEach(btn => {
    btn.addEventListener("click", () => closeModal(btn.dataset.closeModal));
  });

  document.querySelectorAll(".modal-overlay").forEach(overlay => {
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) closeModal(overlay.id);
    });
  });

  // Lockdown badge opens settings network tab
  document.getElementById("lockdown-badge").addEventListener("click", () => {
    openModal("settings-modal");
    document.querySelectorAll("[data-settings-tab]").forEach(t => t.classList.remove("active"));
    document.querySelectorAll("#settings-modal .settings-panel").forEach(p => p.classList.remove("active"));
    document.querySelector("[data-settings-tab='network']").classList.add("active");
    document.getElementById("settings-network").classList.add("active");
  });

  document.getElementById("status-lockdown").addEventListener("click", () => {
    openModal("settings-modal");
    document.querySelectorAll("[data-settings-tab]").forEach(t => t.classList.remove("active"));
    document.querySelectorAll("#settings-modal .settings-panel").forEach(p => p.classList.remove("active"));
    document.querySelector("[data-settings-tab='network']").classList.add("active");
    document.getElementById("settings-network").classList.add("active");
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      const lightbox = document.getElementById("lightbox");
      if (lightbox.classList.contains("visible")) {
        lightbox.classList.remove("visible");
        return;
      }
      const openMdl = document.querySelector(".modal-overlay.visible");
      if (openMdl) closeModal(openMdl.id);
    }
  });
}

function openModal(id) {
  const overlay = document.getElementById(id);
  overlay.style.display = "flex";
  requestAnimationFrame(() => overlay.classList.add("visible"));
}

function closeModal(id) {
  const overlay = document.getElementById(id);
  overlay.classList.remove("visible");
  setTimeout(() => overlay.style.display = "none", 300);
}

// ── CONTEXT MENU ─────────────────────────────────────────────────────
function bindContextMenu() {
  document.addEventListener("click", () => {
    document.getElementById("context-menu").classList.remove("visible");
  });

  document.querySelectorAll(".context-menu-item").forEach(item => {
    item.addEventListener("click", () => {
      const action = item.dataset.action;
      const game = GAMES.find(g => g.id === selectedGameId);
      if (!game) return;

      switch (action) {
        case "launch":
          showToast(`Launching ${game.title}...`, "success");
          break;
        case "folder":
          showToast(`Opening ${game.path}`, "info");
          break;
        case "copy-path":
          navigator.clipboard?.writeText(game.path);
          showToast("Path copied to clipboard", "info");
          break;
        case "properties":
          openModal("properties-modal");
          break;
        case "fetch":
          if (lockdownActive) {
            showToast("Network locked. Disable Lockdown first.", "error");
          } else {
            openModal("fetch-modal");
          }
          break;
        case "remove":
          showToast(`${game.title} removed from library`, "warning");
          break;
      }
    });
  });
}

function showContextMenu(e, gameId) {
  e.preventDefault();
  selectGame(gameId);
  const menu = document.getElementById("context-menu");
  menu.style.left = `${e.clientX}px`;
  menu.style.top = `${e.clientY}px`;
  menu.classList.add("visible");
}

// ── LIGHTBOX ─────────────────────────────────────────────────────────
function openLightbox(index) {
  const game = GAMES.find(g => g.id === selectedGameId);
  if (!game || game.screenshots.length === 0) return;
  currentCarouselIndex = index;
  const lightbox = document.getElementById("lightbox");
  document.getElementById("lightbox-img").src = game.screenshots[index];
  lightbox.classList.add("visible");
}

function bindLightbox() {
  document.getElementById("lightbox").addEventListener("click", (e) => {
    if (e.target === document.getElementById("lightbox") || e.target === document.getElementById("lightbox-img")) {
      document.getElementById("lightbox").classList.remove("visible");
    }
  });

  document.getElementById("lightbox-close").addEventListener("click", () => {
    document.getElementById("lightbox").classList.remove("visible");
  });

  document.getElementById("lightbox-prev").addEventListener("click", (e) => {
    e.stopPropagation();
    const game = GAMES.find(g => g.id === selectedGameId);
    if (!game || game.screenshots.length === 0) return;
    currentCarouselIndex = (currentCarouselIndex - 1 + game.screenshots.length) % game.screenshots.length;
    document.getElementById("lightbox-img").src = game.screenshots[currentCarouselIndex];
  });

  document.getElementById("lightbox-next").addEventListener("click", (e) => {
    e.stopPropagation();
    const game = GAMES.find(g => g.id === selectedGameId);
    if (!game || game.screenshots.length === 0) return;
    currentCarouselIndex = (currentCarouselIndex + 1) % game.screenshots.length;
    document.getElementById("lightbox-img").src = game.screenshots[currentCarouselIndex];
  });
}

// ── CAROUSEL NAV BUTTONS ─────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("carousel-prev").addEventListener("click", () => {
    const slides = document.querySelectorAll(".hero-carousel-slide");
    if (slides.length <= 1) return;
    currentCarouselIndex = getPrevIndex(slides.length);
    updateCarouselSlides();
    restartCarouselTimer();
  });

  document.getElementById("carousel-next").addEventListener("click", () => {
    const slides = document.querySelectorAll(".hero-carousel-slide");
    if (slides.length <= 1) return;
    currentCarouselIndex = getNextIndex(slides.length);
    updateCarouselSlides();
    restartCarouselTimer();
  });
});

// ── TOGGLES ──────────────────────────────────────────────────────────
function bindToggles() {
  document.querySelectorAll(".toggle-switch:not(.lockdown-toggle)").forEach(toggle => {
    toggle.addEventListener("click", () => {
      toggle.classList.toggle("active");
    });
  });

  // Lockdown master toggle
  const lockdownToggle = document.getElementById("lockdown-master-toggle");
  lockdownToggle?.addEventListener("click", () => {
    lockdownActive = !lockdownActive;
    lockdownToggle.classList.toggle("active", !lockdownActive);
    updateLockdownUI();
    showToast(
      lockdownActive ? "Lockdown ENABLED — all network access blocked" : "Lockdown DISABLED — network access allowed",
      lockdownActive ? "warning" : "success"
    );
  });

  // Play button
  document.getElementById("play-btn").addEventListener("click", () => {
    const game = GAMES.find(g => g.id === selectedGameId);
    if (game) showToast(`Launching ${game.title}...`, "success");
  });

  // Add game buttons
  document.getElementById("add-game-btn").addEventListener("click", () => {
    showToast("File picker would open here — select a game folder", "info");
  });
  document.getElementById("status-add-game").addEventListener("click", () => {
    showToast("File picker would open here — select a game folder", "info");
  });

  // Properties modal buttons
  document.getElementById("prop-open-folder")?.addEventListener("click", () => {
    const game = GAMES.find(g => g.id === selectedGameId);
    if (game) showToast(`Opening ${game.path}`, "info");
  });

  document.getElementById("prop-open-saves")?.addEventListener("click", () => {
    const game = GAMES.find(g => g.id === selectedGameId);
    if (game) showToast(`Opening saves for ${game.title}`, "info");
  });

  document.getElementById("prop-copy-path")?.addEventListener("click", () => {
    const game = GAMES.find(g => g.id === selectedGameId);
    if (game) {
      navigator.clipboard?.writeText(game.versions[0].path);
      showToast("Path copied to clipboard", "info");
    }
  });

  // Fetch result selection
  document.querySelectorAll(".fetch-result-item").forEach(item => {
    item.addEventListener("click", () => {
      document.querySelectorAll(".fetch-result-item").forEach(i => i.classList.remove("selected"));
      item.classList.add("selected");
    });
  });

  // Slider labels
  document.querySelectorAll(".setting-slider").forEach(slider => {
    const label = slider.nextElementSibling;
    slider.addEventListener("input", () => {
      if (slider.max === "30") label.textContent = `${parseFloat(slider.value).toFixed(1)}s`;
      else label.textContent = `${slider.value}px`;
    });
  });
}

function updateLockdownUI() {
  const badge = document.getElementById("lockdown-badge");
  const statusBadge = document.getElementById("status-lockdown");

  if (lockdownActive) {
    badge.className = "lockdown-indicator locked";
    badge.innerHTML = "🔒 <span>LOCKDOWN</span>";
    badge.setAttribute("data-tooltip", "Network access is disabled. Click to open Settings.");
    statusBadge.className = "lockdown-indicator locked";
    statusBadge.innerHTML = "🔒 Lockdown";
  } else {
    badge.className = "lockdown-indicator unlocked";
    badge.innerHTML = "🔓 <span>ONLINE</span>";
    badge.setAttribute("data-tooltip", "Network access is enabled. Click to manage.");
    statusBadge.className = "lockdown-indicator unlocked";
    statusBadge.innerHTML = "🔓 Online";
  }
}

// ── SEARCH ───────────────────────────────────────────────────────────
function bindSearch() {
  const input = document.getElementById("search-input");
  let timeout;
  input.addEventListener("input", () => {
    clearTimeout(timeout);
    timeout = setTimeout(() => {
      filterText = input.value;
      applyFilters();
    }, 150);
  });
}

// ── SORT ─────────────────────────────────────────────────────────────
function bindSort() {
  // Sidebar sorts
  document.querySelectorAll(".sort-btn:not([data-grid-sort])").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".sort-btn:not([data-grid-sort])").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      applySortAndRender(btn.dataset.sort);
    });
  });

  // Grid sorts
  document.querySelectorAll(".sort-btn[data-grid-sort]").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".sort-btn[data-grid-sort]").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      applySortAndRender(btn.dataset.sort);
    });
  });
}

function applySortAndRender(sortType) {
  switch (sortType) {
    case "alpha":
      GAMES.sort((a, b) => a.title.localeCompare(b.title));
      break;
    case "recent":
      GAMES.sort((a, b) => {
        const order = { "2 hours ago": 0, "Yesterday": 1, "3 days ago": 2, "4 days ago": 3, "5 days ago": 4, "6 days ago": 5, "1 week ago": 6, "2 weeks ago": 7, "3 weeks ago": 8, "1 month ago": 9, "2 months ago": 10, "Never": 11 };
        return (order[a.lastPlayed] ?? 99) - (order[b.lastPlayed] ?? 99);
      });
      break;
    case "added":
      GAMES.sort((a, b) => a.id - b.id);
      break;
  }
  renderSidebar();
  if (isGridView) renderGridView();
  showToast(`Sorted by ${sortType}`, "info");
}

// ── TOAST ────────────────────────────────────────────────────────────
function showToast(message, type = "info") {
  const container = document.getElementById("toast-container");
  const toast = document.createElement("div");
  toast.className = `toast ${type}`;
  const icons = { success: "✓", error: "✕", info: "ℹ", warning: "⚠" };
  toast.innerHTML = `<span class="toast-icon">${icons[type]}</span> ${message}`;
  container.appendChild(toast);
  setTimeout(() => {
    toast.classList.add("leaving");
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

// ── KEYBOARD SHORTCUTS ───────────────────────────────────────────────
document.addEventListener("keydown", (e) => {
  if (e.ctrlKey && e.key === ",") {
    e.preventDefault();
    openModal("settings-modal");
  }
  if (e.ctrlKey && e.key === "f") {
    e.preventDefault();
    document.getElementById("search-input").focus();
  }
  if (document.activeElement.tagName !== "INPUT" && document.activeElement.tagName !== "TEXTAREA") {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const filtered = getFilteredGames();
      const currentIdx = filtered.findIndex(g => g.id === selectedGameId);
      const newIdx = e.key === "ArrowDown"
        ? Math.min(currentIdx + 1, filtered.length - 1)
        : Math.max(currentIdx - 1, 0);
      if (filtered[newIdx]) {
        selectGame(filtered[newIdx].id);
        const entry = document.querySelector(`.game-entry[data-game-id="${filtered[newIdx].id}"]`);
        entry?.scrollIntoView({ behavior: "smooth", block: "nearest" });
      }
    }
  }
});

// ═══════════════════════════════════════════════════════════════════════
//  ARCHIVE TAB
// ═══════════════════════════════════════════════════════════════════════

const ARCHIVES = [
  { id: 1,  name: "Alternate_Existence_S2_v2.6.0-pc", sizeBytes: 5046586573, type: "zip", modified: "2026-03-08", extracted: false, path: "D:\\Downloads\\VN\\Alternate_Existence_S2_v2.6.0-pc.zip" },
  { id: 2,  name: "BBUltimate v0.7",                  sizeBytes: 1288490189, type: "zip", modified: "2026-03-25", extracted: true,  path: "D:\\Downloads\\VN\\BBUltimate v0.7.zip" },
  { id: 3,  name: "cest_patch_0.1.98RP",              sizeBytes: 245760,     type: "rpa", modified: "2026-04-01", extracted: false, path: "D:\\Downloads\\VN\\cest_patch_0.1.98RP.rpa" },
  { id: 4,  name: "FTV-0.2-win",                      sizeBytes: 417333658,  type: "zip", modified: "2026-03-06", extracted: false, path: "D:\\Downloads\\VN\\FTV-0.2-win.zip" },
  { id: 5,  name: "Harem_Corruption_v10.0_Pc_Official_Ultra_Compressed", sizeBytes: 783286681, type: "zip", modified: "2026-03-23", extracted: true, path: "D:\\Downloads\\VN\\Harem_Corruption_v10.0.zip" },
  { id: 6,  name: "HaremxFamily-Chapter_2_part1-pc",   sizeBytes: 383778816, type: "zip", modified: "2026-04-01", extracted: false, path: "D:\\Downloads\\VN\\HaremxFamily-Chapter_2_part1-pc.zip" },
  { id: 7,  name: "inHerService-0.91.02-pc",           sizeBytes: 2040109466, type: "zip", modified: "2026-04-01", extracted: false, path: "D:\\Downloads\\VN\\inHerService-0.91.02-pc.zip" },
  { id: 8,  name: "Kamogawa_Island-0.2-pc",            sizeBytes: 3328599654, type: "zip", modified: "2026-03-01", extracted: true,  path: "D:\\Downloads\\VN\\Kamogawa_Island-0.2-pc.zip" },
  { id: 9,  name: "[Glass Atelier] LoliPhoto v1.1.0",  sizeBytes: 81788928,  type: "zip", modified: "2026-02-28", extracted: false, path: "D:\\Downloads\\VN\\[Glass Atelier] LoliPhoto v1.1.0.zip" },
  { id: 10, name: "LostLife_1.52_dev",                 sizeBytes: 176160768, type: "rar", modified: "2026-02-28", extracted: false, path: "D:\\Downloads\\VN\\LostLife_1.52_dev.rar" },
  { id: 11, name: "LoveandEvilThings-0.2.6-pc",        sizeBytes: 1717986918, type: "zip", modified: "2026-03-06", extracted: false, path: "D:\\Downloads\\VN\\LoveandEvilThings-0.2.6-pc.zip" },
  { id: 12, name: "MBD-Flowchart-v4.5",                sizeBytes: 2097152,   type: "zip", modified: "2026-03-08", extracted: true,  path: "D:\\Downloads\\VN\\MBD-Flowchart-v4.5.zip" },
  { id: 13, name: "My_New_Daughters_Lover_Reboot-Ch2-1.01.1-win", sizeBytes: 169869312, type: "zip", modified: "2026-03-03", extracted: false, path: "D:\\Downloads\\VN\\My_New_Daughters_Lover_Reboot.zip" },
  { id: 14, name: "Nazaris-0.13-pc",                   sizeBytes: 737148928, type: "rar", modified: "2026-04-12", extracted: false, path: "D:\\Downloads\\VN\\Nazaris-0.13-pc.rar" },
  { id: 15, name: "YourHaremWillBeMine-0.2-pc",        sizeBytes: 5368709120, type: "zip", modified: "2026-04-01", extracted: false, path: "D:\\Downloads\\VN\\YourHaremWillBeMine-0.2-pc.zip" },
];

let selectedArchiveId = null;
let archiveSortKey = "name";
let archiveSortDir = "asc";

function formatBytes(bytes) {
  if (bytes === 0) return "0 B";
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(i > 1 ? 1 : 0) + " " + sizes[i];
}

function sortArchives(arr) {
  return [...arr].sort((a, b) => {
    let cmp = 0;
    switch (archiveSortKey) {
      case "name":     cmp = a.name.localeCompare(b.name); break;
      case "size":     cmp = a.sizeBytes - b.sizeBytes; break;
      case "type":     cmp = a.type.localeCompare(b.type); break;
      case "modified": cmp = a.modified.localeCompare(b.modified); break;
      case "status":   cmp = (a.extracted === b.extracted) ? 0 : a.extracted ? -1 : 1; break;
    }
    return archiveSortDir === "asc" ? cmp : -cmp;
  });
}

function renderArchiveList() {
  const tbody = document.getElementById("archive-tbody");
  tbody.innerHTML = "";
  const sorted = sortArchives(ARCHIVES);

  sorted.forEach(arc => {
    const tr = document.createElement("tr");
    tr.className = `archive-row ${arc.extracted ? "extracted" : ""} ${arc.id === selectedArchiveId ? "selected" : ""}`;
    tr.dataset.archiveId = arc.id;

    const typeClass = arc.type === "7z" ? "z7" : arc.type;
    const statusDotClass = arc.extracted ? "extracted" : "not-extracted";
    const statusText = arc.extracted ? "Extracted ✓" : "Not extracted";

    tr.innerHTML = `
      <td>${arc.name}</td>
      <td>${formatBytes(arc.sizeBytes)}</td>
      <td><span class="archive-type-badge ${typeClass}">${arc.type.toUpperCase()}</span></td>
      <td>${arc.modified}</td>
      <td>
        <span class="archive-status">
          <span class="archive-status-dot ${statusDotClass}"></span>
          <span class="archive-status-text ${statusDotClass}">${statusText}</span>
        </span>
      </td>
    `;

    tr.addEventListener("click", () => selectArchive(arc.id));
    tr.addEventListener("contextmenu", (e) => showArchiveContextMenu(e, arc.id));
    tbody.appendChild(tr);
  });

  updateArchiveStats();
  updateArchiveSortHeaders();
}

function selectArchive(id) {
  selectedArchiveId = id;
  
  document.querySelectorAll(".archive-row").forEach(r => {
    r.classList.toggle("selected", parseInt(r.dataset.archiveId) === id);
  });

  const arc = ARCHIVES.find(a => a.id === id);
  const extractBtn = document.getElementById("archive-extract-btn");
  const deleteBtn = document.getElementById("archive-delete-btn");
  const openBtn = document.getElementById("archive-open-folder-btn");
  const assignBtn = document.getElementById("archive-assign-patch-btn");
  const deleteExBtn = document.getElementById("archive-delete-extracted-btn");

  extractBtn.disabled = false;
  deleteBtn.disabled = false;
  openBtn.disabled = false;
  assignBtn.disabled = false;
  deleteExBtn.disabled = !arc?.extracted;
}

function updateArchiveStats() {
  const total = ARCHIVES.length;
  const totalSize = ARCHIVES.reduce((sum, a) => sum + a.sizeBytes, 0);
  const extractedCount = ARCHIVES.filter(a => a.extracted).length;

  document.getElementById("archive-summary").textContent =
    `${total} archives · ${formatBytes(totalSize)} total · ${extractedCount} extracted (safe to delete)`;
  document.getElementById("extracted-count").textContent = extractedCount;
}

function updateArchiveSortHeaders() {
  document.querySelectorAll(".archive-th.sortable").forEach(th => {
    const key = th.dataset.sortKey;
    const isActive = key === archiveSortKey;
    th.classList.toggle("active", isActive);
    th.querySelector(".sort-indicator").textContent = isActive ? (archiveSortDir === "asc" ? "↑" : "↓") : "";
  });
}

// ── COLUMN SORT ──────────────────────────────────────────────────────
function bindArchiveSortHeaders() {
  document.querySelectorAll(".archive-th.sortable").forEach(th => {
    th.addEventListener("click", () => {
      const key = th.dataset.sortKey;
      if (archiveSortKey === key) {
        archiveSortDir = archiveSortDir === "asc" ? "desc" : "asc";
      } else {
        archiveSortKey = key;
        archiveSortDir = "asc";
      }
      renderArchiveList();
    });
  });
}

// ── EXTRACTION HERO (Steam-style progress) ──────────────────────────
let extractionQueue = [];
let completedExtractions = [];
let currentExtraction = null;
let extractionInterval = null;
let isPaused = false;

function bindQueueToggle() {
  document.getElementById("extraction-queue-header").addEventListener("click", () => {
    document.getElementById("extraction-queue").classList.toggle("collapsed");
  });
}

function startExtraction(archive) {
  currentExtraction = {
    archiveId: archive.id,
    name: archive.name,
    sizeBytes: archive.sizeBytes,
    progress: 0,
    state: "extracting",
  };
  isPaused = false;

  // Show active hero, hide idle
  document.getElementById("extraction-idle").style.display = "none";
  document.getElementById("extraction-active").style.display = "block";

  // Set file name
  document.getElementById("extract-file-name").textContent = archive.name;
  document.getElementById("extract-progress-fill").style.width = "0%";
  document.getElementById("extract-progress-pct").textContent = "0%";
  document.getElementById("extract-progress-bytes").textContent = `0 MB / ${formatBytes(archive.sizeBytes)}`;
  document.getElementById("extract-status-1").textContent = "Extracting data...";
  document.getElementById("extract-status-2").textContent = "Decompressing files...";
  document.getElementById("extract-status-3").textContent = "Estimated time: calculating...";
  document.getElementById("extract-pause-btn").textContent = "\u23F8 Pause";

  // Simulate extraction progress
  extractionInterval = setInterval(() => {
    if (isPaused || !currentExtraction) return;

    const increment = Math.random() * 8 + 2;
    currentExtraction.progress = Math.min(currentExtraction.progress + increment, 100);
    const pct = currentExtraction.progress;
    const processed = (pct / 100) * currentExtraction.sizeBytes;

    // Update progress bar
    document.getElementById("extract-progress-fill").style.width = `${pct}%`;
    document.getElementById("extract-progress-pct").textContent = `${Math.round(pct)}%`;
    document.getElementById("extract-progress-bytes").textContent =
      `${formatBytes(processed)} / ${formatBytes(currentExtraction.sizeBytes)}`;

    // Simulate speed stats
    const readSpeed = (Math.random() * 80 + 20).toFixed(1);
    const writeSpeed = (Math.random() * 60 + 15).toFixed(1);
    const diskUse = (Math.random() * 40 + 5).toFixed(1);
    document.getElementById("extract-read-speed").textContent = `${readSpeed} MB/s`;
    document.getElementById("extract-write-speed").textContent = `${writeSpeed} MB/s`;
    document.getElementById("extract-disk-usage").textContent = `${diskUse} MB/s`;

    // Update status lines
    const remaining = ((100 - pct) / increment * 0.6).toFixed(0);
    if (pct < 30) {
      document.getElementById("extract-status-1").textContent = "Extracting data...";
      document.getElementById("extract-status-2").textContent = "Reading archive headers...";
    } else if (pct < 70) {
      document.getElementById("extract-status-1").textContent = "Extracting data...";
      document.getElementById("extract-status-2").textContent = "Decompressing files...";
    } else {
      document.getElementById("extract-status-1").textContent = "Finalizing...";
      document.getElementById("extract-status-2").textContent = "Writing extracted files...";
    }
    document.getElementById("extract-status-3").textContent =
      `Estimated time remaining: ${remaining}s`;

    // Completed
    if (pct >= 100) {
      clearInterval(extractionInterval);
      extractionInterval = null;

      // Mark archive as extracted
      const arc = ARCHIVES.find(a => a.id === currentExtraction.archiveId);
      if (arc) arc.extracted = true;
      renderArchiveList();

      document.getElementById("extract-status-1").textContent = "Extraction complete!";
      document.getElementById("extract-status-2").textContent = "All files extracted successfully.";
      document.getElementById("extract-status-3").textContent = "";
      document.getElementById("extract-read-speed").textContent = "0 MB/s";
      document.getElementById("extract-write-speed").textContent = "0 MB/s";
      document.getElementById("extract-disk-usage").textContent = "0 B/s";

      showToast(`Extraction complete: ${currentExtraction.name}`, "success");

      // After 3 seconds, auto-dismiss and process queue
      setTimeout(() => {
        // Add to completed before clearing
        completedExtractions.unshift({ ...currentExtraction, completionTime: new Date().toLocaleTimeString() });
        document.getElementById("completed-queue").style.display = "block";
        document.getElementById("completed-queue").classList.remove("collapsed");
        renderCompletedQueue();

        currentExtraction = null;
        processQueue();
      }, 3000);
    }
  }, 500);
}

function processQueue() {
  if (extractionQueue.length > 0) {
    const next = extractionQueue.shift();
    renderQueue();
    startExtraction(next);
  } else {
    // Return to idle
    document.getElementById("extraction-idle").style.display = "flex";
    document.getElementById("extraction-active").style.display = "none";
    renderQueue();
  }
}

function addToExtractionQueue(archive) {
  // If nothing is running, start immediately
  if (!currentExtraction) {
    startExtraction(archive);
    renderQueue();
    return;
  }
  // Otherwise add to queue
  if (!extractionQueue.some(a => a.id === archive.id) && currentExtraction.archiveId !== archive.id) {
    extractionQueue.push(archive);
    renderQueue();
    // Auto-expand queue
    document.getElementById("extraction-queue").classList.remove("collapsed");
  }
}

function renderQueue() {
  const list = document.getElementById("extraction-queue-list");
  const empty = document.getElementById("queue-empty");
  const count = document.getElementById("queue-count");

  count.textContent = `(${extractionQueue.length})`;

  if (extractionQueue.length === 0) {
    empty.style.display = "block";
    list.innerHTML = "";
    return;
  }

  empty.style.display = "none";
  list.innerHTML = "";

  extractionQueue.forEach((arc, idx) => {
    const item = document.createElement("div");
    item.className = "queue-item";
    item.innerHTML = `
      <span class="queue-item-icon">📦</span>
      <div class="queue-item-info">
        <div class="queue-item-name">${arc.name}</div>
        <div class="queue-item-size">${formatBytes(arc.sizeBytes)} · ${arc.type.toUpperCase()}</div>
      </div>
      <span style="font-size:10px;color:var(--text-muted);">NEXT</span>
      <button class="queue-item-remove" data-idx="${idx}">✕</button>
    `;
    item.querySelector(".queue-item-remove").addEventListener("click", (e) => {
      e.stopPropagation();
      extractionQueue.splice(idx, 1);
      renderQueue();
      showToast(`Removed from queue: ${arc.name}`, "info");
    });
    list.appendChild(item);
  });
}

function bindExtractionHeroControls() {
  document.getElementById("extract-pause-btn").addEventListener("click", () => {
    isPaused = !isPaused;
    document.getElementById("extract-pause-btn").textContent = isPaused ? "\u25B6 Resume" : "\u23F8 Pause";
    if (isPaused) {
      document.getElementById("extract-status-1").textContent = "Paused";
      document.getElementById("extract-status-2").textContent = "Extraction paused by user";
      document.getElementById("extract-status-3").textContent = "";
    } else {
      document.getElementById("extract-status-1").textContent = "Extracting data...";
      document.getElementById("extract-status-2").textContent = "Resuming...";
    }
  });

  document.getElementById("extract-cancel-btn").addEventListener("click", () => {
    if (extractionInterval) {
      clearInterval(extractionInterval);
      extractionInterval = null;
    }
    if (currentExtraction) {
      showToast(`Cancelled extraction: ${currentExtraction.name}`, "warning");
      currentExtraction = null;
    }
    isPaused = false;
    processQueue();
  });
}

// ── ARCHIVE CONTEXT MENU ─────────────────────────────────────────────
function showArchiveContextMenu(e, archiveId) {
  e.preventDefault();
  selectArchive(archiveId);

  const menu = document.getElementById("archive-context-menu");
  menu.style.display = "block";
  menu.style.left = `${e.clientX}px`;
  menu.style.top = `${e.clientY}px`;

  const arc = ARCHIVES.find(a => a.id === archiveId);
  // Disable "Delete Extracted" if not extracted
  const delExItem = menu.querySelector('[data-action="delete-extracted"]');
  delExItem.style.opacity = arc?.extracted ? "1" : "0.35";
  delExItem.style.pointerEvents = arc?.extracted ? "auto" : "none";
}

function bindArchiveContextMenu() {
  const menu = document.getElementById("archive-context-menu");

  document.addEventListener("click", () => {
    menu.style.display = "none";
  });

  menu.querySelectorAll(".context-menu-item").forEach(item => {
    item.addEventListener("click", () => {
      const action = item.dataset.action;
      const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
      if (!arc) return;

      switch (action) {
        case "extract":
          addToExtractionQueue(arc);
          showToast(`Extracting ${arc.name}...`, "info");
          break;
        case "delete-archive":
          showToast(`Deleted archive: ${arc.name}`, "warning");
          break;
        case "open-folder":
          showToast(`Opening folder for: ${arc.name}`, "info");
          break;
        case "assign-patch":
          showToast(`Assign patch dialog would open for: ${arc.name}`, "info");
          break;
        case "delete-extracted":
          if (arc.extracted) {
            arc.extracted = false;
            renderArchiveList();
            showToast(`Deleted extracted folder for: ${arc.name}`, "success");
          }
          break;
        case "copy-path":
          navigator.clipboard?.writeText(arc.path);
          showToast("Path copied to clipboard", "success");
          break;
      }
      menu.style.display = "none";
    });
  });
}

// ── ARCHIVE ACTION BAR BINDINGS ──────────────────────────────────────
function bindArchiveActions() {
  document.getElementById("archive-extract-btn").addEventListener("click", () => {
    const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
    if (arc) {
      addToExtractionQueue(arc);
      showToast(`Extracting ${arc.name}...`, "info");
    }
  });

  document.getElementById("archive-delete-btn").addEventListener("click", () => {
    const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
    if (arc) showToast(`Deleted archive: ${arc.name}`, "warning");
  });

  document.getElementById("archive-open-folder-btn").addEventListener("click", () => {
    const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
    if (arc) showToast(`Opening folder for: ${arc.name}`, "info");
  });

  document.getElementById("archive-assign-patch-btn").addEventListener("click", () => {
    const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
    if (arc) showToast(`Assign patch dialog for: ${arc.name}`, "info");
  });

  document.getElementById("archive-delete-extracted-btn").addEventListener("click", () => {
    const arc = ARCHIVES.find(a => a.id === selectedArchiveId);
    if (arc && arc.extracted) {
      arc.extracted = false;
      renderArchiveList();
      showToast(`Deleted extracted folder for: ${arc.name}`, "success");
    }
  });

  document.getElementById("batch-delete-extracted-btn").addEventListener("click", () => {
    const extracted = ARCHIVES.filter(a => a.extracted);
    if (extracted.length === 0) {
      showToast("No extracted folders to delete", "info");
      return;
    }
    extracted.forEach(a => a.extracted = false);
    renderArchiveList();
    showToast(`Deleted ${extracted.length} extracted folders`, "success");
  });

  document.getElementById("archive-refresh-btn").addEventListener("click", () => {
    renderArchiveList();
    showToast("Archive list refreshed", "info");
  });
}

// ── COMPLETED EXTRACTIONS ──────────────────────────────────────────
function renderCompletedQueue() {
  const list = document.getElementById("completed-queue-list");
  const count = document.getElementById("completed-count");
  const container = document.getElementById("completed-queue");

  count.textContent = `(${completedExtractions.length})`;

  if (completedExtractions.length === 0) {
    container.style.display = "none";
    list.innerHTML = "";
    return;
  }
  
  container.style.display = "block";
  list.innerHTML = "";

  completedExtractions.forEach((arc, idx) => {
    const item = document.createElement("div");
    item.className = "queue-item";
    item.innerHTML = `
      <span class="queue-item-icon success-icon">✓</span>
      <div class="queue-item-info">
        <div class="queue-item-name">${arc.name}</div>
        <div class="queue-item-size">Finished at ${arc.completionTime} · ${formatBytes(arc.sizeBytes)}</div>
      </div>
      <div class="queue-item-actions">
        <button class="completed-action-btn" data-action="clear" data-idx="${idx}">Clear</button>
        <button class="completed-action-btn delete-action" data-action="delete" data-idx="${idx}">Clear & Delete Archive</button>
      </div>
    `;

    item.querySelector('[data-action="clear"]').addEventListener("click", (e) => {
      e.stopPropagation();
      completedExtractions.splice(idx, 1);
      renderCompletedQueue();
      showToast(`Cleared completed task: ${arc.name}`, "info");
    });

    item.querySelector('[data-action="delete"]').addEventListener("click", (e) => {
      e.stopPropagation();
      // Remove from completed
      completedExtractions.splice(idx, 1);
      // Remove from archives completely
      const arcIdx = ARCHIVES.findIndex(a => a.id === arc.archiveId);
      if (arcIdx > -1) {
        ARCHIVES.splice(arcIdx, 1);
        renderArchiveList();
      }
      renderCompletedQueue();
      showToast(`Cleared and deleted archive: ${arc.name}`, "warning");
    });

    list.appendChild(item);
  });
}

function bindCompletedQueueControls() {
  document.getElementById("completed-queue-header").addEventListener("click", (e) => {
    // Prevent toggle if clicking buttons
    if (e.target.tagName === 'BUTTON') return;
    document.getElementById("completed-queue").classList.toggle("collapsed");
  });

  document.getElementById("clear-all-completed-btn").addEventListener("click", (e) => {
    e.stopPropagation();
    if (completedExtractions.length === 0) return;
    const count = completedExtractions.length;
    completedExtractions = [];
    renderCompletedQueue();
    showToast(`Cleared ${count} completed tasks`, "info");
  });

  document.getElementById("clear-delete-all-completed-btn").addEventListener("click", (e) => {
    e.stopPropagation();
    if (completedExtractions.length === 0) return;
    const count = completedExtractions.length;
    
    // Remove all from ARCHIVES
    completedExtractions.forEach(c => {
      const arcIdx = ARCHIVES.findIndex(a => a.id === c.archiveId);
      if (arcIdx > -1) ARCHIVES.splice(arcIdx, 1);
    });
    
    completedExtractions = [];
    renderArchiveList();
    renderCompletedQueue();
    showToast(`Cleared and deleted ${count} archives`, "warning");
  });
}

// ── ARCHIVE INIT ─────────────────────────────────────────────────────
function initArchive() {
  bindArchiveSortHeaders();
  bindQueueToggle();
  bindCompletedQueueControls();
  bindExtractionHeroControls();
  bindArchiveContextMenu();
  bindArchiveActions();
  // Start queue collapsed since empty
  document.getElementById("extraction-queue").classList.add("collapsed");
  document.getElementById("completed-queue").classList.add("collapsed");
}

// Add to init
document.addEventListener("DOMContentLoaded", () => {
  initArchive();
});

