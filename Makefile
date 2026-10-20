# Ficha's commands. `make check` must pass before every pull request; CI runs it too.

.DEFAULT_GOAL := check

PACKAGE := Packages/FichaKit
DERIVED := .build/DerivedData
RENDER := scripts/render
# The render tool's own files: its `Sources/Render/App` is a link to `App/`.
SWIFT_SOURCES := App CLI iPhone $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests \
	$(RENDER)/Package.swift $(RENDER)/Sources/Render/main.swift
# The build number, the app's CFBundleVersion: how many commits the built
# commit's history has, so each build after a merge shows a larger one. It's
# passed to xcodebuild as a build setting, which overrides project.yml's.
# Both are expanded only by the targets that build, which stop without it.
BUILD_NUMBER = $(or $(shell git rev-list --count HEAD),$(error No build number: git couldn't count this checkout's commits))
XCODEBUILD = xcodebuild -project Ficha.xcodeproj -scheme Ficha -destination 'platform=macOS,arch=arm64' \
	-derivedDataPath $(DERIVED) -quiet CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)
# The iPhone app, which stage 1 builds only as Ficha Dev, in the Debug
# configuration (#97).
XCODEBUILD_IPHONE = xcodebuild -project Ficha.xcodeproj -scheme iPhone -configuration Debug \
	-derivedDataPath $(DERIVED) -quiet CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)
# The iPhones connected to the Mac, as devicectl lists them: a JSON file is the
# only output it supports for scripts.
IPHONES := .build/iphones.json

.PHONY: bootstrap project build build-iphone test lint fmt hooks-test render-build check run render install \
	install-iphone

bootstrap: ## Install the tools the build needs.
	@command -v xcodegen >/dev/null || brew install xcodegen

project: ## Generate Ficha.xcodeproj from project.yml (never edit it by hand).
	xcodegen generate --quiet

build: project ## Build the app; warnings are errors.
	$(XCODEBUILD) -configuration Debug build

build-iphone: project ## Build the iPhone app for the simulator, unsigned, as CI does; warnings are errors.
	$(XCODEBUILD_IPHONE) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

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

check: lint test build build-iphone hooks-test render-build ## Everything CI runs.

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

install-iphone: project ## Build Ficha Dev for the connected iPhone, signed with your Personal Team, and install it.
	@grep -qs '^DEVELOPMENT_TEAM *= *[A-Z0-9]' iPhone/Local.xcconfig || { \
		echo "No team: write your Personal Team's ID in iPhone/Local.xcconfig, as docs/development.md explains." >&2; exit 1; }
	@mkdir -p .build
	@xcrun devicectl list devices --quiet --json-output $(IPHONES) \
		--filter "hardwareProperties.deviceType == 'iPhone' AND connectionProperties.tunnelState == 'connected'"
	@udid=$$(plutil -extract result.devices.0.hardwareProperties.udid raw -o - $(IPHONES) 2>/dev/null) || { \
		echo "No iPhone connected: connect it with a cable, unlock it and trust this Mac." >&2; exit 1; } && \
	$(XCODEBUILD_IPHONE) -destination "id=$$udid" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		build && \
	xcrun devicectl device install app --device "$$udid" "$(DERIVED)/Build/Products/Debug-iphoneos/Ficha Dev.app"
