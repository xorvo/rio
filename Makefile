.PHONY: web desktop-dev desktop-build desktop-release test setup clean

# Start Phoenix dev server (SQLite)
web:
	mix phx.server

# Desktop development: starts Phoenix and opens Chrome in app mode
desktop-dev:
	@echo "Starting Work Tree in desktop development mode..."
	@PORT=$$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()'); \
	export PORT=$$PORT WORK_TREE_DESKTOP=true PHX_SERVER=true; \
	echo "Starting Phoenix on port $$PORT..."; \
	mix phx.server &  PHOENIX_PID=$$!; \
	for i in $$(seq 1 60); do \
	  curl -s -o /dev/null "http://localhost:$$PORT" 2>/dev/null && break; \
	  sleep 0.5; \
	done; \
	CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; \
	if [ -x "$$CHROME" ]; then \
	  "$$CHROME" --app="http://localhost:$$PORT" --user-data-dir="$$HOME/Library/Application Support/WorkTree/chrome-profile"; \
	else \
	  open "http://localhost:$$PORT"; \
	fi; \
	kill $$PHOENIX_PID 2>/dev/null; \
	wait $$PHOENIX_PID 2>/dev/null

# Build desktop .app bundle: compile Phoenix release, assemble macOS app
desktop-build: desktop-release
	@echo "Assembling Work Tree.app bundle..."
	rm -rf "Work Tree.app"
	mkdir -p "Work Tree.app/Contents/MacOS"
	mkdir -p "Work Tree.app/Contents/Resources"
	cp native/app-bundle/Info.plist "Work Tree.app/Contents/"
	cp native/app-bundle/PkgInfo "Work Tree.app/Contents/"
	cp native/app-bundle/launcher "Work Tree.app/Contents/MacOS/"
	chmod +x "Work Tree.app/Contents/MacOS/launcher"
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
