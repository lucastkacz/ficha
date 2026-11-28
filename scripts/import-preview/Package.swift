// swift-tools-version: 6.2

import PackageDescription

// Reads a deck's `.ficha` as Open Deck… does, in an engine in memory, and
// says what it took, or writes down the cards it brings in (`make
// preview-import`). It reaches FichaKit by path, so `scripts/preview-import.sh`
// can build it against FichaKit as it is at another commit, in a scratch folder
// with the same layout.
let package = Package(
    name: "ImportPreview",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../Packages/FichaKit")
    ],
    targets: [
        .executableTarget(
            name: "ImportPreview",
            dependencies: [
                .product(name: "FichaCore", package: "FichaKit"),
                .product(name: "FichaData", package: "FichaKit"),
                .product(name: "FichaSVG", package: "FichaKit"),
            ]
        )
    ]
)
