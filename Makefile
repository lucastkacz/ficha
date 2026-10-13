# Ficha's commands. `make check` must pass before every pull request; CI runs it too.

.DEFAULT_GOAL := check

PACKAGE := Packages/FichaKit
DERIVED := .build/DerivedData
SWIFT_SOURCES := App $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests
XCODEBUILD := xcodebuild -project Ficha.xcodeproj -scheme Ficha -destination 'platform=macOS,arch=arm64' \
	-derivedDataPath $(DERIVED) -quiet

.PHONY: bootstrap project build test lint fmt hooks-test check run install

bootstrap: ## Install the tools the build needs.
	@command -v xcodegen >/dev/null || brew install xcodegen

project: ## Generate Ficha.xcodeproj from project.yml (never edit it by hand).
	xcodegen generate --quiet

build: project ## Build the app; warnings are errors.
	$(XCODEBUILD) -configuration Debug build

test: ## Run the package tests.
	swift test --package-path $(PACKAGE) --quiet

lint: ## Check formatting and style.
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

fmt: ## Format the Swift code in place.
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

hooks-test: ## Test the Claude Code hooks.
	scripts/test-hooks.sh

check: lint test build hooks-test ## Everything CI runs.

run: build ## Build and open the app.
	@pkill -x Ficha || true
	open $(DERIVED)/Build/Products/Debug/Ficha.app

install: project ## Build a Release copy into /Applications, replacing the running app.
	$(XCODEBUILD) -configuration Release build
	@pkill -x Ficha || true
	rm -rf /Applications/Ficha.app
	cp -R $(DERIVED)/Build/Products/Release/Ficha.app /Applications/
