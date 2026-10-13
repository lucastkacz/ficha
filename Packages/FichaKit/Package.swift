// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FichaKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FichaCore", targets: ["FichaCore"])
    ],
    targets: [
        .target(
            name: "FichaCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "FichaCoreTests",
            dependencies: ["FichaCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
