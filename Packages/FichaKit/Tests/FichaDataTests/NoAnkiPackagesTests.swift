import Foundation
import Testing

/// Tests that Anki's packages neither come in nor go out (ADR 0041, #542),
/// read from the repo this file is in: nothing takes zstd, which only they
/// needed (ADR 0015), and no source opens or reads one. The engine still
/// imports Ficha's decks with their pictures: `FichaDecksTests`, #458's,
/// holds it.
struct NoAnkiPackagesTests {
    // The word: zstd, in any case, as its package, its product, libzstd, and
    // its configuration macros, such as ZSTDLIB_VISIBLE, name it. The files:
    // FichaKit's Package.swift, which takes zstd for Anki's packages alone;
    // its Package.resolved, which pins it; and project.yml, which passes
    // zstd's configuration macros to each target that links FichaData, for
    // zstd alone, as Package.swift says. None is exempt.
    @Test(
        "FichaKit's Package.swift, its Package.resolved and project.yml name no zstd, which only Anki's packages needed",
        .bug(id: 542))
    func nothingTakesZstd() throws {
        let files = ["Packages/FichaKit/Package.swift", "Packages/FichaKit/Package.resolved", "project.yml"]

        let found = try RepoText.lines(holding: ["zstd"], in: files)

        #expect(
            found == [],
            """
            These lines take zstd, which only Anki's packages needed, and they no longer come in (#542): \
            \(found.joined(separator: ", ")). Take zstd out of them, with its configuration macros, and run the \
            test again.
            """)
    }

    // The words: apkg and colpkg, in any case, the extensions of an Anki
    // package and of an Anki collection package, which a source names to
    // open, read or tell one, or to say a deck came from one. The sources are
    // every Swift file outside FichaKit's tests (`RepoText.swiftSources()`);
    // the tests are exempt, since they name such files as what Open Deck…
    // refuses (`OpenDeckTests`).
    @Test("no Swift source names an Anki package, .apkg or .colpkg, so none opens or reads one", .bug(id: 542))
    func noSourceReadsAnkiPackages() throws {
        let found = try RepoText.lines(holding: ["apkg", "colpkg"], in: RepoText.swiftSources())

        #expect(
            found == [],
            """
            These lines name Anki's packages, which no longer come in or go out (#542): \
            \(found.joined(separator: ", ")). Take out what opens, reads or names them, and run the test again.
            """)
    }
}
