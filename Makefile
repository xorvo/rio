.PHONY: web desktop-dev desktop-build clean

# Start Phoenix dev server (SQLite)
web:
	mix phx.server

# Desktop development: starts Phoenix with SQLite, then Tauri dev mode
desktop-dev:
	@echo "Starting Work Tree in desktop development mode..."
	cd native/src-tauri && cargo build
	cd native/src-tauri && WORK_TREE_DESKTOP=true cargo tauri dev

# Build desktop release: compile Phoenix release, package with Tauri
desktop-build: desktop-release
	@echo "Building Tauri desktop app..."
	cd native/src-tauri && cargo tauri build

# Build the Phoenix release for desktop (sidecar binary)
desktop-release:
	@echo "Building Phoenix release for desktop..."
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix deps.get --only prod
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix assets.deploy
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix release work_tree_desktop --overwrite
	@echo "Copying release to Tauri sidecar directory..."
	mkdir -p native/src-tauri/sidecar
	cp -r _build/prod/rel/work_tree_desktop/bin/work_tree_desktop native/src-tauri/sidecar/work_tree_server

# Run tests
test:
	mix test

# Install all dependencies
setup:
	mix deps.get
	cd native/src-tauri && cargo fetch

# Clean build artifacts
clean:
	mix clean
	rm -rf _build
	rm -rf native/src-tauri/target
	rm -rf native/src-tauri/sidecar
