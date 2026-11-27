// swift-tools-version: 6.2

import PackageDescription

// Draws the app's windows offscreen as PNGs (`make render`). The target
// compiles the app's own files through `Sources/Render/App`, a link to `App/`,
// with the app's settings: Ficha Dev's flag and the main actor by default.
let package = Package(
    name: "Render",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/FichaKit")
    ],
    targets: [
        .executableTarget(
            name: "Render",
            dependencies: [
                .product(name: "FichaCore", package: "FichaKit"),
                .product(name: "FichaData", package: "FichaKit"),
                .product(name: "FichaSVG", package: "FichaKit"),
            ],
            // The app's entry point and its delegate, its icons, its String
            // Catalogs, its Info.plist, its entitlements and Ficha's decks
            // stay out: `main.swift` is this tool's entry point, which
            // compiles the texts' catalog itself, as it starts, into the
            // folder SwiftUI looks in, since SwiftPM would put it in a bundle
            // of its own; the App Shortcut's phrases, `AppShortcuts.xcstrings`,
            // which only Siri, Spotlight and the Shortcuts app read, the tool
            // never draws; the zips of Ficha's decks, `FichaDecks/`, which the
            // app bundles, the tool reads where they are in the repo, as the
            // tests do; and the tool runs outside the sandbox. So do the delegate, Ficha
            // Dev's second device and the app's `main.swift`, the only files
            // that load CloudKit, which the tool never loads (ADR 0017): the
            // App Intents reach a delegate of the tool's own,
            // `AppDelegateStandIn.swift`.
            exclude: [
                "App/main.swift", "App/FichaApp.swift", "App/AppDelegate.swift", "App/SecondDevice.swift",
                "App/AppIcon.icon", "App/AppIcon-Dev.icon", "App/Localizable.xcstrings", "App/AppShortcuts.xcstrings",
                "App/Info.plist", "App/Ficha.entitlements", "App/FichaDecks",
            ],
            swiftSettings: [.define("FICHA_DEV"), .defaultIsolation(MainActor.self)]
        )
    ]
)
