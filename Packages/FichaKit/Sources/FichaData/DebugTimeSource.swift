import FichaCore
import Foundation
import Synchronization

/// Ficha Dev's time: the system's, moved forward by its debug menu, so Lucas
/// and agents can try in minutes what takes hours or days. How far it moved is
/// kept in a file next to Ficha Dev's database, whose times depend on it, so
/// restarting the app doesn't take its time back, and Ficha Dev's CLI runs on
/// the same time. The real Ficha never opens one: it always runs on the
/// system's time.
public final class DebugTimeSource: TimeSource {
    private let base: any TimeSource
    private let file: URL
    /// How far ahead of `base` it is, in whole seconds.
    private let shiftInSeconds: Mutex<Int64>

    /// Ficha Dev's time in this data folder: `base`, the system's time except
    /// in tests, moved as far as the file there says, or not moved when
    /// there's no file yet.
    public init(savedIn folder: URL, base: any TimeSource = SystemTimeSource()) throws(DebugTimeError) {
        self.base = base
        file = folder.appending(path: fileName)
        shiftInSeconds = Mutex(try savedShift(in: file))
    }

    public var now: Date {
        base.now.addingTimeInterval(TimeInterval(shiftInSeconds.withLock { $0 }))
    }

    /// How far ahead of the system's time it is.
    public var shift: Duration {
        .seconds(shiftInSeconds.withLock { $0 })
    }

    /// Moves time forward by `step`, in whole seconds, and saves how far ahead
    /// it is. A step back, or one that would take it more than 100 years
    /// ahead, is refused.
    public func moveForward(by step: Duration) throws(DebugTimeError) {
        guard step >= .zero else {
            throw .outOfRange
        }
        try shiftInSeconds.withLock { shift throws(DebugTimeError) in
            let (moved, overflow) = shift.addingReportingOverflow(step.components.seconds)
            guard !overflow, validShifts.contains(moved) else {
                throw .outOfRange
            }
            try save(moved, in: file)
            shift = moved
        }
    }
}

/// What can go wrong with Ficha Dev's time. Each message says what happened
/// and what to do about it, in English and verbatim: like Ficha Dev's debug
/// menu, it isn't translated (ADR 0009).
public enum DebugTimeError: Error, Equatable {
    /// The file next to the database doesn't hold a shift the debug menu
    /// could have saved, so it isn't known what time it is.
    case unreadable
    /// A move would take the time back, or more than 100 years ahead.
    case outOfRange
    /// The file couldn't be read or saved. FichaData logs why.
    case storage
}

extension DebugTimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable:
            """
            The file “\(fileName)” in Ficha Dev's folder doesn't say how far its time moved forward, so Ficha Dev \
            doesn't know what time it is. \(startingOver)
            """
        case .outOfRange:
            "Ficha Dev's time only moves forward, and up to 100 years: it can't go any further. \(startingOver)"
        case .storage:
            "Ficha Dev couldn't read or save how far its time moved forward. Try again, and if it keeps happening, report it."
        }
    }
}

/// The file in Ficha Dev's data folder that keeps how far its time moved.
private let fileName = "Time shift.json"

/// What to do when Ficha Dev's time can't go on, as docs/development.md says:
/// start over, with no cards and on the system's time. Only taking the file away
/// would leave what Ficha Dev saved ahead of its time.
private let startingOver = """
    To start over, quit Ficha Dev and move its folder, ~/Library/Application Support/Ficha Dev/, to the Trash.
    """

/// How far ahead Ficha Dev's time can be, in seconds: up to 100 years, far
/// beyond any test. A file with a shift outside them wasn't saved by the
/// debug menu.
private let validShifts: ClosedRange<Int64> = 0...(100 * 365 * 24 * 60 * 60)

/// The file's contents, like `{"seconds":90000}`.
private struct SavedShift: Codable {
    let seconds: Int64
}

/// The shift saved in `file`, in seconds, or 0 when there's no file yet,
/// since the time was never moved.
private func savedShift(in file: URL) throws(DebugTimeError) -> Int64 {
    let contents: Data
    do {
        contents = try Data(contentsOf: file)
    } catch CocoaError.fileReadNoSuchFile {
        return 0
    } catch {
        logger.error("Couldn't read Ficha Dev's time shift: \(String(describing: error))")
        throw .storage
    }
    let saved: SavedShift
    do {
        saved = try JSONDecoder().decode(SavedShift.self, from: contents)
    } catch {
        logger.error("Refused Ficha Dev's time shift, which isn't a number of seconds: \(String(describing: error))")
        throw .unreadable
    }
    guard validShifts.contains(saved.seconds) else {
        logger.error("Refused Ficha Dev's time shift of \(saved.seconds) seconds, which the debug menu can't save")
        throw .unreadable
    }
    return saved.seconds
}

/// Saves `shift` in `file`, replacing it whole, so the CLI never reads half
/// of it.
private func save(_ shift: Int64, in file: URL) throws(DebugTimeError) {
    do {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(SavedShift(seconds: shift)).write(to: file, options: .atomic)
    } catch {
        logger.error("Couldn't save Ficha Dev's time shift: \(String(describing: error))")
        throw .storage
    }
}
