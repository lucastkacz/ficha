import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Ficha Dev's time, which its debug menu moves forward and keeps
/// next to its database, in a data folder of the test's own.
final class DebugTimeTests {
    let base = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDataTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("Ficha Dev's time keeps running with the system's, ahead by every move")
    func timeRunsAheadByEveryMove() throws {
        let time = try DebugTimeSource(savedIn: folder, base: base)
        #expect(time.now == base.now)

        try time.moveForward(by: .seconds(86_400))
        try time.moveForward(by: .seconds(3_600))
        base.advance(by: 60)

        #expect(time.shift == .seconds(90_000))
        #expect(time.now == Date(timeIntervalSince1970: 1_760_000_000 + 60 + 90_000))
    }

    // `make run` restarts Ficha Dev, and its CLI opens the data folder again
    // on every command: both must stamp what they save with the moved time.
    @Test("Ficha Dev's time stays ahead for whoever opens its data folder next, and the engine follows it")
    func timeStaysAheadForTheNextOpening() throws {
        try DebugTimeSource(savedIn: folder, base: base).moveForward(by: .seconds(86_400))

        let cliTime = try DebugTimeSource(savedIn: folder, base: base)
        let cli = try Engine(location: .folder(folder), time: cliTime)
        let capture = try cli.newCapture("serendipia")

        #expect(cliTime.shift == .seconds(86_400))
        #expect(capture.createdAt == Date(timeIntervalSince1970: 1_760_000_000 + 86_400))
    }

    // Without knowing how far ahead it was, Ficha Dev could stamp what it
    // saves behind what its database already holds.
    @Test(
        "a saved time shift the debug menu couldn't have saved is refused",
        arguments: [
            "", "mañana", #"{}"#, #"{"seconds": "mañana"}"#, #"{"seconds": 1.5}"#, #"{"seconds": -60}"#,
            #"{"seconds": 9223372036854775807}"#,
        ]
    )
    func unknownShiftIsRefused(savedFile: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(savedFile.utf8).write(to: folder.appending(path: "Time shift.json"))

        #expect(throws: DebugTimeError.unreadable) {
            try DebugTimeSource(savedIn: self.folder, base: self.base)
        }
    }

    // Going back would stamp what Ficha Dev saves behind what it already
    // saved, and going too far would save a shift the next opening refuses.
    @Test("moving Ficha Dev's time back, or more than 100 years ahead, is refused, and leaves it where it was")
    func movingBackOrTooFarIsRefused() throws {
        let time = try DebugTimeSource(savedIn: folder, base: base)
        try time.moveForward(by: .seconds(100 * 365 * 86_400))

        #expect(throws: DebugTimeError.outOfRange) {
            try time.moveForward(by: .seconds(-60))
        }
        #expect(throws: DebugTimeError.outOfRange) {
            try time.moveForward(by: .seconds(1))
        }
        #expect(time.shift == .seconds(100 * 365 * 86_400))
        #expect(try DebugTimeSource(savedIn: folder, base: base).shift == .seconds(100 * 365 * 86_400))
    }
}
