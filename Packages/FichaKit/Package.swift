// swift-tools-version: 6.2

import PackageDescription

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
        // Zips, for a deck's `.ficha`, with its cards' images and sounds (ADR 0014, ADR 0044).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
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
        // The SVG drawer, which draws the SVGs a deck's file brings in with WebKit,
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
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Sync through the user's iCloud: a thin adapter over CloudKit's
        // `CKSyncEngine`, which implements FichaData's `ICloudSyncEngine`. No
        // test target depends on it.
        .target(
            name: "FichaICloud",
            dependencies: ["FichaData"],
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
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // What the `ficha` CLI reads from an agent, as the engine then takes
        // it.
        .testTarget(
            name: "FichaCLITests",
            dependencies: ["FichaCLI", "FichaCore", "FichaData"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
