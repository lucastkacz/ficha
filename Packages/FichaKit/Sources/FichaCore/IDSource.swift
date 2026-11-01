import Foundation
import Synchronization

/// Where the engine gets the IDs unique across devices it gives the review
/// log's entries from.
///
/// An entry's ID seeds the fuzz of its way's graduated intervals (#404), so
/// the engine never makes one with `UUID()`: it asks an `IDSource`, as it
/// asks a `TimeSource` for the time, so that tests and `make render`'s
/// pictures get the same IDs, and the same intervals, on every run.
public protocol IDSource: Sendable {
    /// An ID no other entry has.
    func newID() -> UUID
}

/// Random IDs, as Foundation's `UUID()` makes them, which no other device
/// gives: the app's, the CLI's and the iPhone's.
public struct RandomIDSource: IDSource {
    public init() {}

    public func newID() -> UUID {
        UUID()
    }
}

/// IDs that only count up, the same on every run: for tests and the render
/// tool. Each holds `device` in its first four bytes and its count, from 1,
/// in its last six, so that two sources of different devices, as two
/// devices syncing in a test, never give the same ID. Two sources of the
/// same device give the same IDs, so engines that write one database, or
/// sync, each take a device of their own.
public final class CountingIDSource: IDSource {
    private let device: UInt32
    private let given: Mutex<UInt64>

    public init(device: UInt32 = 0) {
        self.device = device
        given = Mutex(0)
    }

    public func newID() -> UUID {
        let count = given.withLock { given in
            given += 1
            return given
        }
        let deviceBytes = withUnsafeBytes(of: device.bigEndian) { Array($0) }
        let countBytes = withUnsafeBytes(of: count.bigEndian) { Array($0) }
        // Version 4 and RFC 9562's variant, in the bytes UUID keeps them,
        // as Foundation's random UUIDs have them.
        return UUID(
            uuid: (
                deviceBytes[0], deviceBytes[1], deviceBytes[2], deviceBytes[3], 0, 0, 0x40, 0, 0x80, 0,
                countBytes[2], countBytes[3], countBytes[4], countBytes[5], countBytes[6], countBytes[7]
            ))
    }
}
