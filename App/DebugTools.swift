import FichaData
import FichaSVG
import Foundation
import Observation

/// Ficha Dev's engine and time, and what its debug menu does with them: it
/// loads sample cards and moves the time forward. The engine runs on that
/// time, so everything Ficha Dev saves follows it.
@Observable
final class DebugTools {
    /// Ficha Dev's engine, on the time the debug menu moves.
    let engine: Engine
    private let time: DebugTimeSource
    /// How far ahead of the system's time Ficha Dev's time is.
    private(set) var timeShift: Duration

    /// Opens the database in Ficha Dev's data folder on Ficha Dev's time, as
    /// far ahead as the debug menu left it, so the engine and the menu share
    /// one time. Its imports draw SVGs through Ficha Dev's SVG drawer.
    init(dataFolder: URL) throws {
        time = try DebugTimeSource(savedIn: dataFolder)
        engine = try Engine(location: .folder(dataFolder), time: time, drawingSVGsWith: { ServiceSVGDrawer() })
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
