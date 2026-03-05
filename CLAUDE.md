# CLAUDE.md

Project-specific instructions for Claude Code.

## Project overview

Work Tree is a mind mapping app built with Phoenix LiveView + SQLite. It runs as a web app (`mix phx.server`) or a native macOS desktop app via Electron.

## Tech stack

- **Backend**: Elixir, Phoenix LiveView 1.1, Ecto with SQLite3 adapter
- **Frontend**: Phoenix LiveView (server-rendered), Tailwind CSS 4, DaisyUI 5, vanilla JS hooks
- **Desktop**: Electron (Chromium), bundles the Phoenix release as a sidecar
- **Database**: SQLite with FTS5 full-text search, WAL mode, materialized paths for tree structure

## Key directories

- `lib/work_tree/mind_maps/` — core context: CRUD, tree operations, search, layout
- `lib/work_tree_web/live/mind_map_live/` — main LiveView and handler modules
- `lib/work_tree/exchange/` — export/import system (`.wtx` format)
- `native/electron/` — Electron shell (Node.js)
- `config/runtime.exs` — runtime config, desktop mode detection, DB path

## Building and running

### Web (development)

```bash
mix setup
mix phx.server
# Visit http://localhost:4000
```

### Desktop app

Prerequisites: Node.js 20+

```bash
# Install Electron deps
cd native/electron && npm install

# Dev mode (starts Phoenix + Electron on a random port)
make desktop-dev

# Production build (.app + .dmg)
make desktop-build

# Install to /Applications
cp -r native/electron/dist/mac-arm64/Work\ Tree.app /Applications/
```

### Common build issues

- **`phoenix-colocated` not found during `mix assets.deploy`**: Run `MIX_ENV=prod WORK_TREE_DESKTOP=true mix compile` first to generate colocated hooks in the prod build path.
- **`sidecar not found`**: The sidecar directory is created by `make desktop-release`. For dev mode, the Electron main process falls back to `native/scripts/run-phoenix.sh`.
- **`pg_dump` version mismatch**: Use `/opt/homebrew/opt/postgresql@15/bin/pg_dump` if the system `pg_dump` is outdated.
- **SQLite `database is locked`**: Kill lingering BEAM processes (`pkill -f beam.smp`) before starting a new server.
- **FTS5 rebuild errors (`no such column: T.body_text`)**: The FTS index uses `content=` sync. Use `INSERT INTO nodes_fts(nodes_fts) VALUES('delete-all')` to clear it, not `DELETE FROM nodes_fts`.

## Database

### Location

| Mode | Database path |
|------|--------------|
| Dev | `work_tree_dev.db` (project root) |
| Test | `work_tree_test.db` (project root) |
| Desktop | `~/Library/Application Support/WorkTree/work_tree.db` |
| Prod (web) | `DATABASE_PATH` env var or `~/work_tree_prod.db` |

Desktop path can be overridden with `WORK_TREE_DATA_DIR` env var.

### Data is preserved across app updates

The database lives in `~/Library/Application Support/WorkTree/`, outside the `.app` bundle. Installing a new version replaces only the application binary.

### Export/import

```bash
# Export to portable .wtx file
mix work_tree.export --output backup.wtx

# Import (full replace)
mix work_tree.import backup.wtx --mode full

# Import (merge, local wins on conflict)
mix work_tree.import backup.wtx --mode merge
```

## Conventions

- UUIDs for all primary keys (Ecto.UUID)
- Materialized paths stored as `/uuid1/uuid2/` strings (custom `PathType`)
- Node events (event log) store snapshots as JSON — all IDs in snapshots must be UUIDs
- FTS5 index kept in sync via SQLite triggers (see `priv/repo/migrations/20260222100000_add_fts5.exs`)
- Desktop mode detected via `WORK_TREE_DESKTOP=true` env var in `config/runtime.exs`

## Release workflow

1. Update version in `native/electron/package.json` and `mix.exs`
2. `make desktop-build`
3. `cp -r native/electron/dist/mac-arm64/Work\ Tree.app /Applications/`

The `.dmg` at `native/electron/dist/` can be used for distribution.
