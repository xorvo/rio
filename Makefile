.PHONY: web desktop-dev desktop-build clean

# Start Phoenix dev server (SQLite)
web:
	mix phx.server

# Desktop development: starts Phoenix via Electron
desktop-dev:
	@echo "Starting Work Tree in desktop development mode..."
	cd native/electron && npm start

# Build desktop release: compile Phoenix release, package with Electron
desktop-build: desktop-release
	@echo "Building Electron desktop app..."
	cd native/electron && npm run build

# Build the Phoenix release for desktop (sidecar binary)
desktop-release:
	@echo "Building Phoenix release for desktop..."
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix deps.get --only prod
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix compile
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix assets.deploy
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix release desktop --overwrite
	@echo "Copying release to Electron sidecar directory..."
	rm -rf native/electron/sidecar
	cp -r _build/prod/rel/desktop native/electron/sidecar

# Run tests
test:
	mix test

# Install all dependencies
setup:
	mix deps.get
	cd native/electron && npm install

# Clean build artifacts
clean:
	mix clean
	rm -rf _build
	rm -rf native/electron/sidecar
	rm -rf native/electron/dist
	rm -rf native/electron/node_modules
