// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FichaKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FichaCore", targets: ["FichaCore"]),
        .library(name: "FichaData", targets: ["FichaData"]),
    ],
    dependencies: [
        // SQLite through GRDB (ADR 0004).
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
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
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
