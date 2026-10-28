# Ficha's commands. CI runs `make check` on every pull request whose files
# aren't all Markdown, which none of its steps reads, and CLAUDE.md says when
# it runs on the Mac before one opens.
#
# A new or changed check is seen failing once, on purpose, before its pull
# request, and the pull request says how: a check nobody saw fail may pass
# whatever it checks.
#
# Each target has its .PHONY line right above it, as the GNU Make manual shows
# it, and its variables next to it. A check joins `make check` through a
# `CHECKS +=` line beside it, and runs in the order of those lines. So two
# branches that each add a target change different lines. The `CHECKS +=`
# lines are our own.

.DEFAULT_GOAL := check

# The paths several targets share, and the checks, which each check adds
# itself to.
PACKAGE := Packages/FichaKit
DERIVED := .build/DerivedData
RENDER := scripts/render
CHECKS :=

.PHONY: bootstrap
bootstrap: ## Install the tools the build and the lint need.
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v shellcheck >/dev/null || brew install shellcheck
	@command -v actionlint >/dev/null || brew install actionlint

.PHONY: xcode-check
CHECKS += xcode-check
xcode-check: ## Fail when this Mac's Xcode isn't the one CI runs, which .xcode-version names.
	@output=$$(xcodebuild -version) || exit 1; \
	mac=$$(echo "$$output" | sed -n 's/^Xcode //p'); ci=$$(cat .xcode-version); \
	[ "$$mac" = "$$ci" ] || { \
		echo "This Mac runs Xcode $$mac and CI runs $$ci, the one .xcode-version names: update the Mac's Xcode to $$ci, or the file to $$mac, which moves CI too." >&2; \
		exit 1; }

# The render tool's own files: its `Sources/Render/App` is a link to `App/`.
SWIFT_SOURCES := App CLI SVGDrawer iPhone $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests \
	$(RENDER)/Package.swift $(RENDER)/Sources/Render/main.swift
# The shell scripts, for shellcheck. actionlint finds the workflows on its own,
# in .github/workflows, and runs shellcheck on each step's `run:` script too.
SHELL_SCRIPTS := .claude/hooks/*.sh scripts/*.sh

.PHONY: lint
CHECKS += lint
lint: ## Check the Swift code's formatting and style, and lint the shell scripts and the workflows.
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)
	shellcheck $(SHELL_SCRIPTS)
	actionlint

.PHONY: fmt
fmt: ## Format the Swift code in place.
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

.PHONY: test
CHECKS += test
test: ## Run the package tests.
	swift test --package-path $(PACKAGE) --quiet

.PHONY: project
project: ## Generate Ficha.xcodeproj from project.yml (never edit it by hand).
	xcodegen generate --quiet

# The build number, the app's CFBundleVersion: how many commits the built
# commit's history has, so each build after a merge shows a larger one. It's
# passed to xcodebuild as a build setting, which overrides project.yml's.
# Both are expanded only by the targets that build, which stop without it.
BUILD_NUMBER = $(or $(shell git rev-list --count HEAD),$(error No build number: git couldn't count this checkout's commits))
XCODEBUILD = xcodebuild -project Ficha.xcodeproj -scheme Ficha -destination 'platform=macOS,arch=arm64' \
	-derivedDataPath $(DERIVED) -quiet CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

# Ficha Dev, and the real Ficha that `make install` builds, sign with Lucas's
# paid team, whose ID git ignores, in iPhone/Local.xcconfig, which
# Signing.xcconfig includes. Ficha Dev's iCloud and push entitlements need a
# provisioning profile, which Xcode makes and keeps through the account in its
# settings, registering the Mac with the team the first time. Without the
# team's ID, as in CI and in a new worktree, Ficha Dev's builds go unsigned:
# they check the code, but don't run in their sandbox or sync. Building
# unsigned without it is our own. The real Ficha needs it, to reach its App
# Group's folder, so `make install` stops without it.
TEAM := $(shell grep -qs '^DEVELOPMENT_TEAM *= *[A-Z0-9]' iPhone/Local.xcconfig && echo yes)
SIGNING := $(if $(TEAM),-allowProvisioningUpdates -allowProvisioningDeviceRegistration,CODE_SIGNING_ALLOWED=NO)

.PHONY: team
team: ## Fail unless iPhone/Local.xcconfig has the team's ID, which signs Ficha Dev and the real Ficha.
	@[ -n "$(TEAM)" ] || { \
		echo "No team: write your team's ID in iPhone/Local.xcconfig, or copy that file into this worktree from the main folder, as docs/development.md explains." >&2; \
		exit 1; }

.PHONY: build
CHECKS += build
build: project ## Build the app, signed when the team's ID is there; warnings are errors.
	$(XCODEBUILD) -configuration Debug build $(SIGNING)

# The iPhone app, which stage 1 builds only as Ficha Dev, in the Debug
# configuration (#97).
XCODEBUILD_IPHONE = xcodebuild -project Ficha.xcodeproj -scheme iPhone -configuration Debug \
	-derivedDataPath $(DERIVED) -quiet CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

.PHONY: build-iphone
CHECKS += build-iphone
build-iphone: project ## Build the iPhone app for the simulator, unsigned, as CI does; warnings are errors.
	$(XCODEBUILD_IPHONE) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# The String Catalogs, one for each app, which the builds compile but never
# fill. Xcode's export fills them all from the code: it adds the UI's new
# texts, and drops the ones the code no longer has, or marks them stale when
# they have plural variations. Whatever the scheme, it builds both apps on the
# way, the iPhone's for an iPhone and unsigned, so it takes the build's derived
# data, build number and signing, and writes its own copy of the texts to a
# scratch folder. It builds the Mac's for Intel too, and Xcode then processes
# Ficha Dev's CLI's Info.plist for Apple silicon alone, so its link for Intel
# can't find it: the export, which only reads the code, leaves it out.
CATALOGS := App/Localizable.xcstrings iPhone/Localizable.xcstrings
STRINGS := .build/strings
EXPORT_STRINGS = $(XCODEBUILD) -exportLocalizations -localizationPath $(STRINGS) -exportLanguage en \
	$(SIGNING) CREATE_INFOPLIST_SECTION_IN_BINARY=NO

.PHONY: strings
strings: project ## Sync the String Catalogs with the code's UI texts.
	$(EXPORT_STRINGS)

# Where the check keeps the shell's `$catalog` as it was, named after its app's
# folder: `.build/strings/App.xcstrings` for `App/Localizable.xcstrings`.
BEFORE = $(STRINGS)/$${catalog%%/*}.xcstrings

.PHONY: strings-check
CHECKS += strings-check
strings-check: project ## Fail when a String Catalog is out of date, showing how, and leave each as it was.
	@mkdir -p $(STRINGS)
	@for catalog in $(CATALOGS); do cp $$catalog $(BEFORE); done
	$(EXPORT_STRINGS) || { for catalog in $(CATALOGS); do cp $(BEFORE) $$catalog; done; exit 1; }
	@stale=0; for catalog in $(CATALOGS); do cmp -s $(BEFORE) $$catalog || { diff -u $(BEFORE) $$catalog; \
		cp $(BEFORE) $$catalog; stale=1; \
		echo "$$catalog is out of date with the code's UI texts: run make strings and commit the catalog." >&2; }; \
		done; exit $$stale

.PHONY: hooks-test
CHECKS += hooks-test
hooks-test: ## Test the Claude Code hooks.
	scripts/test-hooks.sh

.PHONY: clean-merged-test
CHECKS += clean-merged-test
clean-merged-test: ## Test make clean-merged on a scratch repo, with a fake gh.
	scripts/test-clean-merged.sh

.PHONY: render-build
CHECKS += render-build
render-build: ## Build the render tool, so a change to the app's views can't break it unnoticed.
	swift build --package-path $(RENDER) --quiet -Xswiftc -warnings-as-errors

.PHONY: run
run: team build ## Build and open Ficha Dev, in its sandbox, restarting it; the real Ficha keeps running.
	@pkill -x "Ficha Dev" || true
	open "$(DERIVED)/Build/Products/Debug/Ficha Dev.app"

.PHONY: render
render: ## Draw an app window as a PNG, offscreen: make render ARGS="cards --dark".
	CFFIXED_USER_HOME=$(CURDIR)/.build/render/home swift run --package-path $(RENDER) --quiet Render $(ARGS)

.PHONY: render-iphone
render-iphone: build-iphone ## Take the iPhone app's pictures, light and dark, in a simulator of its own: make render-iphone ARGS="--out <path>".
	scripts/render-iphone.sh "$(DERIVED)/Build/Products/Debug-iphonesimulator/Ficha Dev.app" $(ARGS)

.PHONY: install
install: team project ## Build the real Ficha, signed with your team, into /Applications, replacing the running one.
	$(XCODEBUILD) -configuration Release build $(SIGNING)
	@pkill -x Ficha || true
	rm -rf /Applications/Ficha.app
	cp -R $(DERIVED)/Build/Products/Release/Ficha.app /Applications/

# The iPhones paired with the Mac, the connected ones first, as devicectl lists
# them: a JSON file is the only output it supports for scripts. A paired iPhone
# is reachable on the cable or the Mac's Wi-Fi even before devicectl connects.
IPHONES := .build/iphones.json
PAIRED_IPHONE := hardwareProperties.deviceType == 'iPhone' AND hardwareProperties.reality == 'physical' \
	AND connectionProperties.pairingState == 'paired'

.PHONY: install-iphone
install-iphone: team project ## Build Ficha Dev for the connected iPhone, signed with your team, and install it.
	@mkdir -p .build
	@xcrun devicectl list devices --quiet --json-output $(IPHONES) --sort-by connectionProperties.tunnelState \
		--filter "$(PAIRED_IPHONE)"
	@udid=$$(plutil -extract result.devices.0.hardwareProperties.udid raw -o - $(IPHONES) 2>/dev/null) || { \
		echo "No iPhone paired with this Mac: connect it with a cable, unlock it and trust this Mac." >&2; exit 1; } && \
	$(XCODEBUILD_IPHONE) -destination "id=$$udid" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		build && \
	xcrun devicectl device install app --device "$$udid" "$(DERIVED)/Build/Products/Debug-iphoneos/Ficha Dev.app"

.PHONY: clean-merged
clean-merged: ## From the main folder, on main: remove the worktrees whose work merged, with their branches, list the others, and update main.
	@scripts/clean-merged.sh

# Every check above, in the order of their `CHECKS +=` lines. It comes last:
# make expands a rule's prerequisites when it reads the rule, and here CHECKS
# holds them all.
.PHONY: check
check: $(CHECKS) ## Everything CI runs, on CI's Xcode.
