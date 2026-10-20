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
            ],
            // The app's entry point, its icons and its String Catalog stay
            // out: `main.swift` is this tool's entry point.
            exclude: ["App/FichaApp.swift", "App/AppIcon.icon", "App/AppIcon-Dev.icon", "App/Localizable.xcstrings"],
            swiftSettings: [.define("FICHA_DEV"), .defaultIsolation(MainActor.self)]
        )
    ]
)
