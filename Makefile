# Ficha's commands. `make check` must pass before every pull request; CI runs it too.

.DEFAULT_GOAL := check

PACKAGE := Packages/FichaKit
DERIVED := .build/DerivedData
RENDER := scripts/render
# The render tool's own files: its `Sources/Render/App` is a link to `App/`.
SWIFT_SOURCES := App CLI iPhone $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests \
	$(RENDER)/Package.swift $(RENDER)/Sources/Render/main.swift
# The shell scripts, for shellcheck. actionlint finds the workflows on its own,
# in .github/workflows, and runs shellcheck on each step's `run:` script too.
SHELL_SCRIPTS := .claude/hooks/*.sh scripts/*.sh
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
# The iPhones paired with the Mac, the connected ones first, as devicectl lists
# them: a JSON file is the only output it supports for scripts. A paired iPhone
# is reachable on the cable or the Mac's Wi-Fi even before devicectl connects.
IPHONES := .build/iphones.json
PAIRED_IPHONE := hardwareProperties.deviceType == 'iPhone' AND hardwareProperties.reality == 'physical' \
	AND connectionProperties.pairingState == 'paired'
# The String Catalogs, one for each app, which the builds compile but never
# fill. Xcode's export fills them all from the code: it adds the UI's new
# texts, and drops the ones the code no longer has, or marks them stale when
# they have plural variations. Whatever the scheme, it builds both apps on the
# way, the iPhone's for an iPhone and unsigned, so it takes the build's derived
# data and build number, and writes its own copy of the texts to a scratch
# folder.
CATALOGS := App/Localizable.xcstrings iPhone/Localizable.xcstrings
STRINGS := .build/strings
EXPORT_STRINGS = $(XCODEBUILD) -exportLocalizations -localizationPath $(STRINGS) -exportLanguage en
# Where the check keeps the shell's `$catalog` as it was, named after its app's
# folder: `.build/strings/App.xcstrings` for `App/Localizable.xcstrings`.
BEFORE = $(STRINGS)/$${catalog%%/*}.xcstrings

.PHONY: bootstrap xcode-check project build build-iphone strings strings-check test lint fmt hooks-test render-build \
	check run render install install-iphone

bootstrap: ## Install the tools the build and the lint need.
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v shellcheck >/dev/null || brew install shellcheck
	@command -v actionlint >/dev/null || brew install actionlint

xcode-check: ## Fail when this Mac's Xcode isn't the one CI runs, which .xcode-version names.
	@output=$$(xcodebuild -version) || exit 1; \
	mac=$$(echo "$$output" | sed -n 's/^Xcode //p'); ci=$$(cat .xcode-version); \
	[ "$$mac" = "$$ci" ] || { \
		echo "This Mac runs Xcode $$mac and CI runs $$ci, the one .xcode-version names: update the Mac's Xcode to $$ci, or the file to $$mac, which moves CI too." >&2; \
		exit 1; }

project: ## Generate Ficha.xcodeproj from project.yml (never edit it by hand).
	xcodegen generate --quiet

build: project ## Build the app; warnings are errors.
	$(XCODEBUILD) -configuration Debug build

build-iphone: project ## Build the iPhone app for the simulator, unsigned, as CI does; warnings are errors.
	$(XCODEBUILD_IPHONE) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

strings: project ## Sync the String Catalogs with the code's UI texts.
	$(EXPORT_STRINGS)

strings-check: project ## Fail when a String Catalog is out of date, showing how, and leave each as it was.
	@mkdir -p $(STRINGS)
	@for catalog in $(CATALOGS); do cp $$catalog $(BEFORE); done
	$(EXPORT_STRINGS) || { for catalog in $(CATALOGS); do cp $(BEFORE) $$catalog; done; exit 1; }
	@stale=0; for catalog in $(CATALOGS); do cmp -s $(BEFORE) $$catalog || { diff -u $(BEFORE) $$catalog; \
		cp $(BEFORE) $$catalog; stale=1; \
		echo "$$catalog is out of date with the code's UI texts: run make strings and commit the catalog." >&2; }; \
		done; exit $$stale

test: ## Run the package tests.
	swift test --package-path $(PACKAGE) --quiet

lint: ## Check the Swift code's formatting and style, and lint the shell scripts and the workflows.
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)
	shellcheck $(SHELL_SCRIPTS)
	actionlint

fmt: ## Format the Swift code in place.
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

hooks-test: ## Test the Claude Code hooks.
	scripts/test-hooks.sh

render-build: ## Build the render tool, so a change to the app's views can't break it unnoticed.
	swift build --package-path $(RENDER) --quiet -Xswiftc -warnings-as-errors

check: xcode-check lint test build build-iphone strings-check hooks-test render-build ## Everything CI runs, on CI's Xcode.

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
	@xcrun devicectl list devices --quiet --json-output $(IPHONES) --sort-by connectionProperties.tunnelState \
		--filter "$(PAIRED_IPHONE)"
	@udid=$$(plutil -extract result.devices.0.hardwareProperties.udid raw -o - $(IPHONES) 2>/dev/null) || { \
		echo "No iPhone paired with this Mac: connect it with a cable, unlock it and trust this Mac." >&2; exit 1; } && \
	$(XCODEBUILD_IPHONE) -destination "id=$$udid" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		build && \
	xcrun devicectl device install app --device "$$udid" "$(DERIVED)/Build/Products/Debug-iphoneos/Ficha Dev.app"
