// swift-tools-version: 6.2

import PackageDescription

// zstd 1.5.7's module map lists as configuration macros some that its own
// headers define when nothing else does, so as Xcode imports it clang warns
// that each definition has no effect, and asks for them on the command line
// (facebook/zstd#3892). So every target that loads libzstd passes them, and
// FichaData's clients too, since Swift loads a module's internal imports for
// its clients: empty, as they only mark the declarations' visibility, and the
// compression level at zstd's own default. zstd fixed its module map after
// 1.5.7 (facebook/zstd#4531): the release that ships the fix takes these out,
// and `project.yml`'s too (ADR 0015).
let zstdConfigurationMacros: [CSetting] =
    [
        "ZSTDLIB_VISIBLE", "ZSTDLIB_HIDDEN", "ZDICTLIB_VISIBLE", "ZDICTLIB_HIDDEN", "ZSTDERRORLIB_VISIBLE",
        "ZSTDERRORLIB_HIDDEN",
    ].map { .define($0, to: "") } + [.define("ZSTD_CLEVEL_DEFAULT", to: "3")]

let package = Package(
    name: "FichaKit",
    // The iPhone app links FichaCore and FichaData. The CLI is the Mac's only,
    // as is the SVG drawer's XPC service, which links FichaSVG alone.
    // FichaICloud, the only one that imports CloudKit, is linked by the Mac
    // app alone, so that neither the CLI, `swift test` nor `make render`
    // loads CloudKit (ADR 0017).
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FichaCore", targets: ["FichaCore"]),
        .library(name: "FichaData", targets: ["FichaData"]),
        .library(name: "FichaSVG", targets: ["FichaSVG"]),
        .library(name: "FichaICloud", targets: ["FichaICloud"]),
        .library(name: "FichaCLI", targets: ["FichaCLI"]),
    ],
    dependencies: [
        // SQLite through GRDB (ADR 0004).
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        // The `ficha` CLI's commands (ADR 0008).
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        // Zips, for cards exported and imported with their images and sounds (ADR 0014).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        // zstd, which current Anki's packages are compressed with (ADR 0015).
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
    ],
    targets: [
        .target(
            name: "FichaCore",
            dependencies: ["FichaFSRS"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // fsrs-rs, Anki's FSRS library, through our crate in `Rust/`, which
        // `make fsrs` builds from source into this XCFramework of static
        // libraries, for the Mac, the iPhone and its simulator, never committed
        // (ADR 0026).
        .binaryTarget(
            name: "CFichaFSRS",
            path: "Frameworks/CFichaFSRS.xcframework"
        ),
        // The crate's C interface in Swift's types and FichaCore's names,
        // which FichaCore schedules with.
        .target(
            name: "FichaFSRS",
            dependencies: ["CFichaFSRS"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The SVG drawer, which draws the SVGs an import brings in with WebKit,
        // in the app's XPC service or in the process (ADR 0018).
        .target(
            name: "FichaSVG",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "FichaData",
            dependencies: [
                "FichaCore",
                "FichaSVG",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "libzstd", package: "zstd"),
            ],
            cSettings: zstdConfigurationMacros,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Sync through the user's iCloud: a thin adapter over CloudKit's
        // `CKSyncEngine`, which implements FichaData's `ICloudSyncEngine`. No
        // test target depends on it.
        .target(
            name: "FichaICloud",
            dependencies: ["FichaData"],
            cSettings: zstdConfigurationMacros,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The `ficha` CLI's commands. The executable that runs them is a target
        // of the Xcode project, built with each app (`project.yml`).
        .target(
            name: "FichaCLI",
            dependencies: [
                "FichaCore",
                "FichaData",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            cSettings: zstdConfigurationMacros,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "FichaCoreTests",
            dependencies: ["FichaCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The tests that call fsrs-rs through FichaFSRS: against fsrs-rs's own
        // expected values, and with parameters it can't work with.
        .testTarget(
            name: "FichaFSRSTests",
            dependencies: ["FichaFSRS"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "FichaDataTests",
            dependencies: [
                "FichaCore",
                "FichaData",
                "FichaSVG",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "libzstd", package: "zstd"),
            ],
            cSettings: zstdConfigurationMacros,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // What the `ficha` CLI reads from a refine session, as the engine then
        // takes it.
        .testTarget(
            name: "FichaCLITests",
            dependencies: ["FichaCLI", "FichaCore", "FichaData"],
            cSettings: zstdConfigurationMacros,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
