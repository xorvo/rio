# Work Tree

A real-time mind mapping application built with Phoenix LiveView and SQLite. Runs as a web app or a native macOS desktop app (Electron).

## Features

- **Interactive canvas** - Pan, zoom, and navigate your mind maps
- **Keyboard navigation** - Arrow keys to move between nodes
- **Inline editing** - Edit node titles directly on the canvas
- **Todo support** - Mark nodes as tasks with completion tracking
- **Priority levels** - P0-P3 priorities with visual badges
- **Due dates** - Set deadlines with auto-archiving of completed todos
- **Link attachments** - Attach URLs to nodes
- **Full-text search** - FTS5 indexed search with Jaro-Winkler fuzzy matching
- **Context menu** - Right-click for quick actions
- **Undo delete** - Soft delete with batch restore
- **Subtree focus** - Drill down into any branch
- **Theme picker** - Multiple UI themes via DaisyUI
- **Desktop app** - Native macOS app via Electron

## Architecture

Work Tree is a single Phoenix LiveView + SQLite codebase. The native macOS app wraps the Phoenix server in an Electron shell.

```mermaid
graph TB
    subgraph "Native macOS App (.app bundle)"
        Electron["Electron Shell<br/>(Node.js, Chromium)"]
        Sidecar["Phoenix Release<br/>(Bundled ERTS + BEAM)"]
        SQLiteD[(SQLite DB<br/>~/Library/Application Support/WorkTree/)]

        Electron -->|"spawns on random port"| Sidecar
        Sidecar -->|"Ecto.Adapters.SQLite3"| SQLiteD
        Electron -->|"BrowserWindow loads<br/>http://localhost:{port}"| Sidecar
    end

    subgraph "Web Mode"
        Browser["Browser"]
        Phoenix["Phoenix Server"]
        SQLiteW[(SQLite DB)]

        Browser -->|"WebSocket (LiveView)"| Phoenix
        Phoenix -->|"Ecto.Adapters.SQLite3"| SQLiteW
    end

    subgraph "Shared Elixir Codebase"
        direction TB
        LiveView["Phoenix LiveView UI<br/>Templates, Components, Handlers"]
        Context["MindMaps Context<br/>CRUD, Tree Ops, Search, Events"]
        Repo["WorkTree.Repo<br/>(SQLite3 adapter)"]

        LiveView --> Context
        Context --> Repo
    end

    Phoenix --> LiveView
    Sidecar --> LiveView
```

### Key layers

| Layer | What | Key files |
|-------|------|-----------|
| **UI** | LiveView pages, components, handlers | `lib/work_tree_web/live/` |
| **Context** | Business logic, CRUD, tree operations | `lib/work_tree/mind_maps/` |
| **Search** | FTS5 full-text search + Jaro-Winkler fuzzy matching | `lib/work_tree/mind_maps/search.ex`, `lib/work_tree/fuzzy_search.ex` |
| **Events** | PubSub event tracking | `lib/work_tree/events/` |
| **Repo** | SQLite3 adapter with materialized paths | `lib/work_tree/repo.ex`, `lib/work_tree/ecto/path_type.ex` |
| **Config** | Base config + env-specific overlays | `config/` |

### What differs between web and desktop

| Concern | Web | Desktop |
|---------|-----|---------|
| **Binding** | `127.0.0.1` (dev), configurable (prod) | `127.0.0.1` only |
| **DB location** | Local file (`work_tree_dev.db`) | `~/Library/Application Support/WorkTree/` |
| **Shell** | None (browser) | Electron (Chromium) |
| **Env flag** | Default | `WORK_TREE_DESKTOP=true` |

## Project structure

```
work_tree/
├── lib/
│   ├── work_tree/                  # Core application
│   │   ├── mind_maps/              # MindMaps context (CRUD, tree, search, layout)
│   │   ├── events/                 # Event pub/sub system
│   │   ├── ecto/                   # Custom Ecto types (PathType)
│   │   ├── repo.ex                 # Ecto repo (SQLite3)
│   │   ├── application.ex          # OTP supervisor, auto-migration
│   │   ├── auto_archiver.ex        # Auto-archive completed todos
│   │   └── fuzzy_search.ex         # Jaro-Winkler fuzzy search
│   └── work_tree_web/              # Web layer
│       ├── live/                   # LiveView pages & components
│       │   ├── mind_map_live/      # Main mind map view + handler modules
│       │   └── components/         # Reusable UI components
│       ├── router.ex               # Routes
│       └── endpoint.ex             # HTTP endpoint config
├── config/
│   ├── config.exs                  # Base config (shared)
│   ├── dev.exs                     # Dev (SQLite, live reload)
│   ├── prod.exs                    # Production
│   ├── runtime.exs                 # Runtime config (env vars)
│   └── test.exs                    # Test config
├── native/                         # Electron desktop shell
│   ├── electron/
│   │   ├── main.js                 # Main process: port pick, spawn, window, cleanup
│   │   ├── preload.js              # Minimal preload (context isolation)
│   │   ├── loading.html            # Splash screen while Phoenix boots
│   │   ├── package.json            # Electron + electron-builder config
│   │   ├── icons/                  # App icons (all sizes + .icns)
│   │   └── build/                  # macOS entitlements
│   └── scripts/run-phoenix.sh      # Dev mode launcher
├── priv/
│   ├── repo/migrations/            # SQLite migrations
│   └── static/                     # Compiled assets, icons, images
├── assets/                         # Frontend source (CSS, JS, vendor)
├── Makefile                        # Build targets (web, desktop-dev, desktop-build)
└── mix.exs                         # Project config, deps, releases
```

## Getting started

### Web

```bash
mix setup
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

### Desktop (macOS)

**Prerequisites:** Node.js 20+

**Dev mode** (starts Phoenix + Electron):

```bash
make setup
make desktop-dev
```

**Build standalone .app:**

```bash
make desktop-build
```

The built app is at `native/electron/dist/mac-arm64/Work Tree.app`.

To install:

```bash
cp -r native/electron/dist/mac-arm64/Work\ Tree.app /Applications/
```

### Build targets

| Command | Description |
|---------|-------------|
| `make web` | Start Phoenix dev server (SQLite) |
| `make desktop-dev` | Run Electron dev mode |
| `make desktop-build` | Build .app + .dmg (bundles Phoenix release as sidecar) |
| `make desktop-release` | Build just the Phoenix release for desktop |
| `make test` | Run tests |
| `make setup` | Install all dependencies |
| `make clean` | Remove build artifacts |

## Releasing and updating the desktop app

### Data location

The SQLite database lives at `~/Library/Application Support/WorkTree/work_tree.db`. This directory is outside the `.app` bundle and is never touched by installs or updates. The app auto-creates it on first launch if it doesn't exist.

To override: set the `WORK_TREE_DATA_DIR` environment variable.

### Building a new release

```bash
# 1. Build the production app (compiles Phoenix release + Electron bundle)
make desktop-build

# Output:
#   native/electron/dist/mac-arm64/Work Tree.app
#   native/electron/dist/Work Tree-0.1.0-arm64.dmg
```

### Installing / updating

```bash
# Install or update (replaces the app binary, data is preserved)
cp -r native/electron/dist/mac-arm64/Work\ Tree.app /Applications/
```

The `.dmg` can also be used for distribution — mount it and drag to Applications.

### Version bumps

Update the version in these files before building:

- `native/electron/package.json` — `"version"` field (controls DMG filename and app metadata)
- `mix.exs` — `version` field (Elixir release version)

### Data migration between machines

Export your data to a portable `.wtx` file:

```bash
mix work_tree.export --output backup.wtx
```

On the new machine:

```bash
mix work_tree.import backup.wtx --mode full
```

Or simply copy `~/Library/Application Support/WorkTree/` to the new machine.
