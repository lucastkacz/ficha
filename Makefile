# Ficha's commands. `make check` must pass before every pull request; CI runs it too.

.DEFAULT_GOAL := check

PACKAGE := Packages/FichaKit
DERIVED := .build/DerivedData
RENDER := scripts/render
# The render tool's own files: its `Sources/Render/App` is a link to `App/`.
SWIFT_SOURCES := App CLI $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests \
	$(RENDER)/Package.swift $(RENDER)/Sources/Render/main.swift
# The build number, the app's CFBundleVersion: how many commits the built
# commit's history has, so each build after a merge shows a larger one. It's
# passed to xcodebuild as a build setting, which overrides project.yml's.
# Both are expanded only by the targets that build, which stop without it.
BUILD_NUMBER = $(or $(shell git rev-list --count HEAD),$(error No build number: git couldn't count this checkout's commits))
XCODEBUILD = xcodebuild -project Ficha.xcodeproj -scheme Ficha -destination 'platform=macOS,arch=arm64' \
	-derivedDataPath $(DERIVED) -quiet CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)
# The String Catalog, which `make build` compiles but never fills. Xcode's
# export fills it from the code: it adds the UI's new texts, and drops the ones
# the code no longer has, or marks them stale when they have plural
# variations. It builds the app on the way, so it takes the build's derived
# data and build number, and writes its own copy of the texts to a scratch
# folder.
CATALOG := App/Localizable.xcstrings
STRINGS := .build/strings
EXPORT_STRINGS = $(XCODEBUILD) -exportLocalizations -localizationPath $(STRINGS) -exportLanguage en

.PHONY: bootstrap project build strings strings-check test lint fmt hooks-test render-build check run render install

bootstrap: ## Install the tools the build needs.
	@command -v xcodegen >/dev/null || brew install xcodegen

project: ## Generate Ficha.xcodeproj from project.yml (never edit it by hand).
	xcodegen generate --quiet

build: project ## Build the app; warnings are errors.
	$(XCODEBUILD) -configuration Debug build

strings: project ## Sync the String Catalog with the code's UI texts.
	$(EXPORT_STRINGS)

strings-check: project ## Fail when the String Catalog is out of date, leaving it as it was.
	@mkdir -p $(STRINGS)
	@cp $(CATALOG) $(STRINGS)/before.xcstrings
	$(EXPORT_STRINGS) || { cp $(STRINGS)/before.xcstrings $(CATALOG); exit 1; }
	@cmp -s $(CATALOG) $(STRINGS)/before.xcstrings || { cp $(STRINGS)/before.xcstrings $(CATALOG); \
		echo "$(CATALOG) is out of date with the code's UI texts: run make strings and commit the catalog." >&2; \
		exit 1; }

test: ## Run the package tests.
	swift test --package-path $(PACKAGE) --quiet

lint: ## Check formatting and style.
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

fmt: ## Format the Swift code in place.
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

hooks-test: ## Test the Claude Code hooks.
	scripts/test-hooks.sh

render-build: ## Build the render tool, so a change to the app's views can't break it unnoticed.
	swift build --package-path $(RENDER) --quiet -Xswiftc -warnings-as-errors

check: lint test build strings-check hooks-test render-build ## Everything CI runs.

run: build ## Build and open Ficha Dev, restarting it; the real Ficha keeps running.
	@pkill -x "Ficha Dev" || true
	open "$(DERIVED)/Build/Products/Debug/Ficha Dev.app"

render: ## Draw an app window as a PNG, offscreen: make render ARGS="cards --dark".
	CFFIXED_USER_HOME=$(CURDIR)/.build/render/home swift run --package-path $(RENDER) --quiet Render $(ARGS)

install: project ## Build the real Ficha into /Applications, replacing the running one.
	$(XCODEBUILD) -configuration Release build
	@pkill -x Ficha || true
	rm -rf /Applications/Ficha.app
	cp -R $(DERIVED)/Build/Products/Release/Ficha.app /Applications/
