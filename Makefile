.PHONY: web desktop-dev desktop-build desktop-release desktop-swift test setup clean

# Start Phoenix dev server (SQLite)
web:
	mix phx.server

# Desktop development: starts Phoenix and opens default browser
desktop-dev:
	@echo "Starting Rio in desktop development mode..."
	@PORT=$${PORT:-4949}; \
	export PORT=$$PORT RIO_DESKTOP=true PHX_SERVER=true; \
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
	@echo "Compiling RioMenuBar..."
	swiftc native/app-bundle/RioMenuBar.swift \
		-parse-as-library \
		-framework AppKit \
		-target arm64-apple-macos12.0 \
		-O \
		-o native/app-bundle/RioMenuBar

# Build desktop .app bundle: compile Phoenix release + Swift binary, assemble macOS app
desktop-build: desktop-release desktop-swift
	@echo "Assembling Rio.app bundle..."
	rm -rf "Rio.app"
	mkdir -p "Rio.app/Contents/MacOS"
	mkdir -p "Rio.app/Contents/Resources"
	cp native/app-bundle/Info.plist "Rio.app/Contents/"
	cp native/app-bundle/PkgInfo "Rio.app/Contents/"
	cp native/app-bundle/RioMenuBar "Rio.app/Contents/MacOS/"
	chmod +x "Rio.app/Contents/MacOS/RioMenuBar"
	cp native/app-bundle/icon.icns "Rio.app/Contents/Resources/"
	cp -r _build/prod/rel/desktop "Rio.app/Contents/Resources/sidecar"
	@echo "Built: Rio.app"
	@echo "Install with: cp -r \"Rio.app\" /Applications/"

# Build the Phoenix release for desktop (sidecar binary)
desktop-release:
	@echo "Building Phoenix release for desktop..."
	MIX_ENV=prod RIO_DESKTOP=true mix deps.get --only prod
	MIX_ENV=prod RIO_DESKTOP=true mix compile
	MIX_ENV=prod RIO_DESKTOP=true mix assets.deploy
	MIX_ENV=prod RIO_DESKTOP=true mix release desktop --overwrite

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
	rm -rf "Rio.app"
	rm -f native/app-bundle/RioMenuBar
