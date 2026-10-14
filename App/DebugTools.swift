import FichaCore
import FichaData
import Foundation
import Observation

/// What Ficha Dev's debug menu does: it loads sample cards and moves Ficha
/// Dev's time forward. Ficha Dev's engine runs on that time, so everything the
/// app saves follows it.
@Observable
final class DebugTools {
    /// Ficha Dev's engine, on the time the debug menu moves.
    let engine: Engine
    private let time: DebugTimeSource
    /// How far ahead of the system's time Ficha Dev's time is.
    private(set) var timeShift: Duration

    /// Opens the database in Ficha Dev's data folder on Ficha Dev's time, as
    /// far ahead as the debug menu left it, so the engine and the menu share
    /// one time.
    init(dataFolder: URL) throws {
        time = try DebugTimeSource(savedIn: dataFolder, base: SystemTimeSource())
        engine = try Engine(location: .folder(dataFolder), time: time)
        timeShift = time.shift
    }

    /// Loads the sample cards into Ficha Dev's database, as new cards.
    func loadSampleCards() throws {
        try SampleCards.load(into: engine)
    }

    /// Moves Ficha Dev's time forward by `step`, for the app and its CLI.
    func moveTimeForward(by step: Duration) throws(DebugTimeError) {
        try time.moveForward(by: step)
        timeShift = time.shift
    }
}
