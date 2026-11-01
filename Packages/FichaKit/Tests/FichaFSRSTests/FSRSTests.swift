import FichaFSRS
import Testing

// fsrs-rs's own expected values, at the version Ficha pins, so an upgrade that
// changes them fails here (ADR 0026). Each test cites where fsrs-rs states
// them, in https://github.com/open-spaced-repetition/fsrs-rs/blob/v6.6.2/src/inference.rs.
struct FSRSTests {
    @Test("the default parameters are FSRS-6's, as fsrs-rs ships them")
    func defaultParameters() throws {
        // `DEFAULT_PARAMETERS`, with `FSRS6_DEFAULT_DECAY` last.
        #expect(
            try FSRS.defaultParameters() == [
                0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835,
                0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
            ])
    }

    @Test("a new card's interval for good at 90% is 2.3065 days, with each rating's memory state")
    func newCardsNextStates() throws {
        let fsrs = try FSRS(parameters: FSRS.defaultParameters())

        let next = try fsrs.nextStates(from: nil, desiredRetention: 0.9, daysElapsed: 0)

        // `FSRS::next_states`'s example, for a new card with the default
        // parameters at 90%.
        #expect(next.good.interval == 2.3065)
        #expect(
            next
                == NextStates(
                    again: NextState(memoryState: MemoryState(stability: 0.212, difficulty: 6.4133), interval: 0.212),
                    hard: NextState(
                        memoryState: MemoryState(stability: 1.2931, difficulty: 5.1121707), interval: 1.2931),
                    good: NextState(
                        memoryState: MemoryState(stability: 2.3065, difficulty: 2.118104), interval: 2.3065),
                    easy: NextState(memoryState: MemoryState(stability: 8.2956, difficulty: 1.0), interval: 8.2956)
                ))
    }

    @Test("a card without reviews starts from its SM-2 interval and ease")
    func memoryStateFromSM2() throws {
        let fsrs = try FSRS(parameters: FSRS.defaultParameters())

        let memoryState = try fsrs.memoryState(sm2Interval: 10, ease: 2.5, sm2Retention: 0.9)

        // `test_memory_from_sm2`'s first case, within its tolerance.
        #expect(abs(memoryState.stability - 10) < 1e-4)
        #expect(abs(memoryState.difficulty - 6.9140563) < 1e-4)
    }

    @Test("retrievability falls with the days since the last review, by the parameters' decay")
    func retrievability() throws {
        // `test_current_retrievability`, which takes a decay of 0.2: FSRS-6's
        // last parameter.
        var parameters = try FSRS.defaultParameters()
        parameters[20] = 0.2
        let fsrs = try FSRS(parameters: parameters)
        let memoryState = MemoryState(stability: 1, difficulty: 5)

        #expect(try fsrs.retrievability(of: memoryState, daysElapsed: 1) == 0.9)
        #expect(try fsrs.retrievability(of: memoryState, daysElapsed: 2) == 0.84028935)
        #expect(try fsrs.retrievability(of: memoryState, daysElapsed: 3) == 0.7985001)
    }

    @Test("parameters that aren't finite numbers come back from fsrs-rs as an error")
    func parametersThatArentFinite() throws {
        var parameters = try FSRS.defaultParameters()
        parameters[3] = .nan
        let fsrs = try FSRS(parameters: parameters)

        #expect(throws: FSRSError.invalidParameters) {
            try fsrs.nextStates(from: nil, desiredRetention: 0.9, daysElapsed: 0)
        }
    }
}
