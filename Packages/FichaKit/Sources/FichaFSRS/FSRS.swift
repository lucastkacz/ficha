internal import CFichaFSRS

/// FSRS-6 with a set of parameters, whose arithmetic fsrs-rs, Anki's FSRS
/// library, works out: our crate's C interface in Swift's types (ADR 0026).
/// Its numbers are fsrs-rs's own, `Float`s, so they come back exactly as
/// fsrs-rs gave them.
public struct FSRS: Sendable, Equatable {
    /// FSRS-6's 21 parameters, in fsrs-rs's order.
    public let parameters: [Float]

    /// FSRS-6 with these parameters, which are 21. Each call checks that
    /// they're finite numbers, as fsrs-rs does.
    public init(parameters: [Float]) throws(FSRSError) {
        guard parameters.count == Int(FICHA_FSRS_PARAMETER_COUNT) else {
            throw .invalidParameters
        }
        self.parameters = parameters
    }

    /// FSRS-6's default parameters, fsrs-rs's `DEFAULT_PARAMETERS`.
    public static func defaultParameters() throws(FSRSError) -> [Float] {
        var parameters = FichaFsrsParameters()
        try check(ficha_fsrs_default_parameters(&parameters))
        return withUnsafeBytes(of: parameters.values) { values in
            (0..<Int(FICHA_FSRS_PARAMETER_COUNT)).map {
                values.load(fromByteOffset: $0 * MemoryLayout<Float>.stride, as: Float.self)
            }
        }
    }

    /// The memory state and interval each rating would give a card, fsrs-rs's
    /// `next_states`: from its memory state, or from none for a new card,
    /// for the desired retention, after the whole days since its last
    /// review.
    public func nextStates(
        from memoryState: MemoryState?, desiredRetention: Float, daysElapsed: Int
    ) throws(FSRSError) -> NextStates {
        guard let days = UInt32(exactly: daysElapsed) else {
            throw .invalidInput
        }
        var next = FichaFsrsNextStates()
        try check(
            ficha_fsrs_next_states(
                crateParameters, memoryState != nil, FichaFsrsMemoryState(memoryState ?? .newCardPlaceholder),
                desiredRetention, days, &next))
        return NextStates(
            again: NextState(next.again), hard: NextState(next.hard), good: NextState(next.good),
            easy: NextState(next.easy))
    }

    /// A memory state started from SM-2's interval, in days, and ease, such
    /// as 2.5, for a card whose reviews aren't known, at the retention SM-2
    /// spaced it for: fsrs-rs's `memory_state_from_sm2`.
    public func memoryState(sm2Interval: Float, ease: Float, sm2Retention: Float) throws(FSRSError) -> MemoryState {
        var memoryState = FichaFsrsMemoryState()
        try check(ficha_fsrs_memory_state_from_sm2(crateParameters, ease, sm2Interval, sm2Retention, &memoryState))
        return MemoryState(memoryState)
    }

    /// How likely the user is to remember a card with this memory state
    /// after a number of days, which can be a fraction of one, with the
    /// decay that's FSRS-6's last parameter, as Anki reads it: fsrs-rs's
    /// `current_retrievability`.
    public func retrievability(of memoryState: MemoryState, daysElapsed: Float) throws(FSRSError) -> Float {
        var retrievability: Float = 0
        try check(
            ficha_fsrs_current_retrievability(
                crateParameters, FichaFsrsMemoryState(memoryState), daysElapsed, &retrievability))
        return retrievability
    }

    /// The parameters as the crate takes them.
    private var crateParameters: FichaFsrsParameters {
        var crateParameters = FichaFsrsParameters()
        withUnsafeMutableBytes(of: &crateParameters.values) { values in
            parameters.withUnsafeBytes { values.copyMemory(from: $0) }
        }
        return crateParameters
    }
}

/// A card's memory, as FSRS estimates it from its reviews.
public struct MemoryState: Sendable, Equatable {
    /// How long the memory lasts: the days it takes the chance of remembering
    /// the card to fall to 90%.
    public var stability: Float
    /// How hard the card is, from 1 to 10.
    public var difficulty: Float

    public init(stability: Float, difficulty: Float) {
        self.stability = stability
        self.difficulty = difficulty
    }

    /// What a call passes in place of a new card's memory state, which it
    /// doesn't have: the crate ignores it, as it's told there's none.
    fileprivate static let newCardPlaceholder = MemoryState(stability: 0, difficulty: 0)
}

/// A card's memory after a rating, and the interval FSRS gives it then.
public struct NextState: Sendable, Equatable {
    public var memoryState: MemoryState
    /// In days, unrounded, for the desired retention.
    public var interval: Float

    public init(memoryState: MemoryState, interval: Float) {
        self.memoryState = memoryState
        self.interval = interval
    }
}

/// The next state for each of the four ratings.
public struct NextStates: Sendable, Equatable {
    public var again: NextState
    public var hard: NextState
    public var good: NextState
    public var easy: NextState

    public init(again: NextState, hard: NextState, good: NextState, easy: NextState) {
        self.again = again
        self.hard = hard
        self.good = good
        self.easy = easy
    }
}

/// Why fsrs-rs couldn't work something out.
public enum FSRSError: Error, Equatable, CustomStringConvertible {
    /// The parameters aren't 21 finite numbers.
    case invalidParameters
    /// A memory state, retention or number of days that fsrs-rs can't work
    /// with: a negative number of days, or numbers that gave a result that
    /// isn't a finite number.
    case invalidInput
    /// fsrs-rs failed in a way Ficha doesn't expect, or panicked, which our
    /// crate caught before it reached Swift: a bug in fsrs-rs or in the crate.
    case unexpected

    public var description: String {
        switch self {
        case .invalidParameters:
            """
            fsrs-rs can't schedule with these parameters, which aren't the 21 finite numbers FSRS-6 takes: schedule \
            with FSRS-6's default parameters, FSRS.defaultParameters(), instead.
            """
        case .invalidInput:
            """
            fsrs-rs can't work with the numbers it was given, a memory state, an SM-2 interval and ease, a retention \
            or a number of days: the days are negative, or the numbers give a result that isn't a finite number. \
            Check where they came from, the card's reviews or the settings.
            """
        case .unexpected:
            """
            fsrs-rs failed in a way Ficha doesn't expect, or panicked, which Ficha's crate caught before it reached \
            Swift: a bug in fsrs-rs or in the crate, in Packages/FichaKit/Rust. Report it with the numbers the call \
            was given.
            """
        }
    }
}

/// Throws the error for a call's status, unless the call worked.
private func check(_ status: FichaFsrsStatus) throws(FSRSError) {
    switch status {
    case FICHA_FSRS_STATUS_OK: return
    case FICHA_FSRS_STATUS_INVALID_PARAMETERS: throw .invalidParameters
    case FICHA_FSRS_STATUS_INVALID_INPUT: throw .invalidInput
    default: throw .unexpected
    }
}

extension FichaFsrsMemoryState {
    fileprivate init(_ memoryState: MemoryState) {
        self.init(stability: memoryState.stability, difficulty: memoryState.difficulty)
    }
}

extension MemoryState {
    fileprivate init(_ memoryState: FichaFsrsMemoryState) {
        self.init(stability: memoryState.stability, difficulty: memoryState.difficulty)
    }
}

extension NextState {
    fileprivate init(_ nextState: FichaFsrsNextState) {
        self.init(memoryState: MemoryState(nextState.memory_state), interval: nextState.interval)
    }
}
