// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FichaKit",
    // The iPhone app links FichaCore and FichaData. The CLI is the Mac's only.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "FichaCore", targets: ["FichaCore"]),
        .library(name: "FichaData", targets: ["FichaData"]),
        .library(name: "FichaCLI", targets: ["FichaCLI"]),
    ],
    dependencies: [
        // SQLite through GRDB (ADR 0004).
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        // The `ficha` CLI's commands (ADR 0008).
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        // Zips, for cards exported and imported with their images (ADR 0014).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "FichaCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "FichaData",
            dependencies: [
                "FichaCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
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
        .testTarget(
            name: "FichaDataTests",
            dependencies: [
                "FichaCore",
                "FichaData",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
