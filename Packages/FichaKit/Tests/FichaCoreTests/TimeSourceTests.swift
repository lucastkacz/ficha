import FichaCore
import Foundation
import Testing

struct TimeSourceTests {
    // Tests hand one ManualTimeSource to the code under test and move time from
    // outside, so every holder must see the same time.
    @Test("advancing a manual time source moves it for everyone who holds it")
    func advancingMovesItForEveryHolder() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let time = ManualTimeSource(now: start)
        let heldByCodeUnderTest: any TimeSource = time

        time.advance(by: 3_600)

        #expect(heldByCodeUnderTest.now == start.addingTimeInterval(3_600))
    }

    // Ficha Dev's debug menu moves its time forward while that time keeps
    // running with the system's, and the engine, which holds the same time
    // source, must see both.
    @Test("a shifted time source keeps running with its base, ahead by every advance")
    func shiftedTimeRunsAheadOfItsBase() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let base = ManualTimeSource(now: start)
        let time = ShiftedTimeSource(base: base, shift: 600)
        let heldByCodeUnderTest: any TimeSource = time

        time.advance(by: 3_600)
        base.advance(by: 60)

        #expect(heldByCodeUnderTest.now == start.addingTimeInterval(600 + 3_600 + 60))
        #expect(time.shift == 4_200)
    }
}
