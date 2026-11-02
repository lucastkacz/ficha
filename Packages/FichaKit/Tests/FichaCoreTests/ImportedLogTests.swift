import FichaCore
import Foundation
import Testing

/// Tests on the review log an import gives a way of a card that brings its
/// progress from Anki (#409), as `ImportedProgress.log(of:importedAt:with:newID:)`
/// writes it, with the IDs the import gives it, which the engine's tests,
/// whose IDs are random, can't compare.
struct ImportedLogTests {
    /// The `n`th ID an import gives, the same in every run.
    private func id(_ n: UInt8) -> UUID {
        UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    @Test("an import's log takes its IDs from the import, each review answering the entry before it")
    func anImportsLogTakesItsIDsFromTheImport() throws {
        let dueInAnki = start + 27 * day
        let progress = ImportedProgress(
            stage: .review(interval: .days(15), ease: 2.5, due: .on(dueInAnki..<dueInAnki + day)), isSuspended: false,
            start: ImportedStart(
                answeredAt: start, placement: Placement(interval: .days(5), due: start + 5 * day, ease: 2.3)),
            reviews: [
                ImportedReview(
                    answeredAt: start + 6 * day, rating: .good, interval: .days(4), graduated: true,
                    responseTime: .seconds(6)),
                ImportedReview(
                    answeredAt: start + 10 * day, rating: .good, interval: .days(15), graduated: true,
                    responseTime: nil),
            ])
        var given: UInt8 = 0

        let log = try progress.log(of: wayOne, importedAt: start + 20 * day, with: .standard) {
            given += 1
            return id(given)
        }

        #expect(
            log == [
                ReviewLogEntry(
                    placing: 1, on: Placement(interval: .days(5), due: start + 5 * day, ease: 2.3), at: start,
                    uuid: id(1)),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: start + 6 * day, responseTime: .seconds(6),
                    trigger: nil, uuid: id(2), answeredEntry: id(1), interval: .days(4)),
                ReviewLogEntry(
                    cardID: 1, kind: .review(.good), answeredAt: start + 10 * day, responseTime: nil, trigger: nil,
                    uuid: id(3), answeredEntry: id(2), interval: .days(15)),
                ReviewLogEntry(
                    placing: 1, on: Placement(interval: .days(15), due: dueInAnki, ease: 2.5), at: start + 20 * day,
                    uuid: id(4)),
            ])
    }
}
