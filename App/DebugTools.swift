import FichaData
import FichaSVG
import Foundation
import Observation

/// Ficha Dev's engine and time, and what its debug menu does with them: it
/// loads sample cards, moves the time forward and opens the second device.
/// The engine runs on that time, so everything Ficha Dev saves follows it.
@Observable
final class DebugTools {
    /// Ficha Dev's engine, on the time the debug menu moves.
    let engine: Engine
    private let time: DebugTimeSource
    /// Where the second device keeps its cards: a folder of its own beside
    /// Ficha Dev's data folder, named after it, so a scratch folder's second
    /// device is a scratch folder too, which `FICHA_DEV_SCRATCH` reaches.
    private let secondDeviceFolder: URL
    /// How far ahead of the system's time Ficha Dev's time is.
    private(set) var timeShift: Duration

    /// Opens the database in Ficha Dev's data folder on Ficha Dev's time, as
    /// far ahead as the debug menu left it, so the engine and the menu share
    /// one time. Its imports draw SVGs through Ficha Dev's SVG drawer.
    init(dataFolder: URL) throws {
        time = try DebugTimeSource(savedIn: dataFolder)
        let svgDrawer = AppVariant.dev.svgDrawerIdentifier
        engine = try Engine(
            location: .folder(dataFolder), time: time, drawingSVGsWith: { ServiceSVGDrawer(serviceName: svgDrawer) })
        secondDeviceFolder = dataFolder.deletingLastPathComponent()
            .appending(path: "\(dataFolder.lastPathComponent)-second-device", directoryHint: .isDirectory)
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

    /// Opens the second device's database, in its own folder, on Ficha Dev's
    /// time, so both devices' changes are timed alike, as on two devices
    /// whose clocks agree.
    func openSecondDevice() throws(EngineError) -> Engine {
        try Engine(location: .folder(secondDeviceFolder), time: time)
    }
}
