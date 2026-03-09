.PHONY: web desktop-dev desktop-build desktop-release desktop-swift test setup clean

# Start Phoenix dev server (SQLite)
web:
	mix phx.server

# Desktop development: starts Phoenix and opens default browser
desktop-dev:
	@echo "Starting Work Tree in desktop development mode..."
	@PORT=$${PORT:-4949}; \
	export PORT=$$PORT WORK_TREE_DESKTOP=true PHX_SERVER=true; \
	echo "Starting Phoenix on port $$PORT..."; \
	mix phx.server &  PHOENIX_PID=$$!; \
	for i in $$(seq 1 60); do \
	  curl -s -o /dev/null "http://localhost:$$PORT" 2>/dev/null && break; \
	  sleep 0.5; \
	done; \
	open "http://localhost:$$PORT"; \
	wait $$PHOENIX_PID

# Compile the Swift menu bar app
desktop-swift:
	@echo "Compiling WorkTreeMenuBar..."
	swiftc native/app-bundle/WorkTreeMenuBar.swift \
		-parse-as-library \
		-framework AppKit \
		-target arm64-apple-macos12.0 \
		-O \
		-o native/app-bundle/WorkTreeMenuBar

# Build desktop .app bundle: compile Phoenix release + Swift binary, assemble macOS app
desktop-build: desktop-release desktop-swift
	@echo "Assembling Work Tree.app bundle..."
	rm -rf "Work Tree.app"
	mkdir -p "Work Tree.app/Contents/MacOS"
	mkdir -p "Work Tree.app/Contents/Resources"
	cp native/app-bundle/Info.plist "Work Tree.app/Contents/"
	cp native/app-bundle/PkgInfo "Work Tree.app/Contents/"
	cp native/app-bundle/WorkTreeMenuBar "Work Tree.app/Contents/MacOS/"
	chmod +x "Work Tree.app/Contents/MacOS/WorkTreeMenuBar"
	cp native/app-bundle/icon.icns "Work Tree.app/Contents/Resources/"
	cp -r _build/prod/rel/desktop "Work Tree.app/Contents/Resources/sidecar"
	@echo "Built: Work Tree.app"
	@echo "Install with: cp -r \"Work Tree.app\" /Applications/"

# Build the Phoenix release for desktop (sidecar binary)
desktop-release:
	@echo "Building Phoenix release for desktop..."
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix deps.get --only prod
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix compile
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix assets.deploy
	MIX_ENV=prod WORK_TREE_DESKTOP=true mix release desktop --overwrite

# Run tests
test:
	mix test

# Install all dependencies
setup:
	mix deps.get

# Clean build artifacts
clean:
	mix clean
	rm -rf _build
	rm -rf "Work Tree.app"
	rm -f native/app-bundle/WorkTreeMenuBar
