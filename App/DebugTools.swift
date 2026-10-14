import FichaCore
import FichaData
import Foundation
import Observation

/// What Ficha Dev's debug menu does: it loads sample cards and moves Ficha
/// Dev's time forward, which the engine runs on too. How far time was moved
/// stays in Ficha Dev's preferences, so restarting the app, as `make run` does,
/// doesn't take its time back behind what its database already holds.
@Observable
final class DebugTools {
    /// Where Ficha Dev's preferences keep how far ahead its time is.
    private static let timeShiftKey = "timeShift"

    private let engine: Engine
    private let time: ShiftedTimeSource
    /// How far ahead of the system's time Ficha Dev's time is.
    private(set) var timeShift: TimeInterval

    /// Ficha Dev's time: the system's, as far ahead as the debug menu left it.
    static func savedTime() -> ShiftedTimeSource {
        ShiftedTimeSource(base: SystemTimeSource(), shift: UserDefaults.standard.double(forKey: timeShiftKey))
    }

    /// The tools for an engine that runs on `time`, Ficha Dev's.
    init(engine: Engine, time: ShiftedTimeSource) {
        self.engine = engine
        self.time = time
        timeShift = time.shift
    }

    /// Loads the sample cards into Ficha Dev's database, as new cards.
    func loadSampleCards() throws {
        try SampleCards.load(into: engine)
    }

    /// Moves Ficha Dev's time forward, and saves how far ahead it is.
    func moveTimeForward(by interval: TimeInterval) {
        time.advance(by: interval)
        timeShift = time.shift
        UserDefaults.standard.set(timeShift, forKey: Self.timeShiftKey)
    }
}
