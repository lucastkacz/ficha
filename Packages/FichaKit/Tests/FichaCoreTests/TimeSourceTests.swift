import FichaCore
import Foundation
import Testing

struct TimeSourceTests {
    @Test("a manual time source only moves when advanced")
    func manualTimeSourceMovesOnlyWhenAdvanced() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let time = ManualTimeSource(now: start)

        #expect(time.now == start)
        #expect(time.now == start)

        time.advance(by: 3_600)
        #expect(time.now == start.addingTimeInterval(3_600))
    }
}
