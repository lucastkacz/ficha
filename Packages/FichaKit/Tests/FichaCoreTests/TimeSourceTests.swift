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
}
