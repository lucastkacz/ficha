import CoreGraphics
import Foundation
import Synchronization
import os

// The SVG drawer (#229, ADR 0018): what draws the SVG images an import brings
// in, which ImageIO can't read. In the app it's an XPC service of its own, a
// small process inside the app and the only part of Ficha that holds the
// network entitlement, which WebKit needs in the sandbox; the app holds none.
// In `swift test`, the same drawing runs in the process. Either way, WebKit
// draws, and loads nothing from the network.

/// The SVG drawer's log.
let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "svg")

/// Draws one import's SVGs, one after another, and lets go of what it opened
/// for them once it's gone.
public protocol SVGDrawer: Sendable {
    /// The SVG `svg` drawn `longestSide` pixels on its long side, on white,
    /// in sRGB, or nil when it can't be drawn as an SVG, or once the drawer
    /// stopped answering, for this SVG or one before it.
    func image(of svg: Data, longestSide: Int) -> CGImage?
}

/// A drawing that another thread waits for.
final class PendingDrawing: Sendable {
    /// How a drawing ended, for the thread that waits for it.
    enum Outcome {
        case drawn(CGImage)
        /// It couldn't be drawn as an SVG.
        case notDrawn
        /// It didn't end in the time the thread waited.
        case unanswered
    }

    /// How it ended, once it did.
    private let outcome = Mutex<Outcome?>(nil)
    private let done = DispatchSemaphore(value: 0)

    /// Ends the drawing with `image`, or nil when it couldn't be drawn,
    /// unless it ended already: an XPC connection that breaks after its
    /// reply still tells.
    func finish(with image: CGImage?) {
        let isFirst = outcome.withLock { outcome in
            guard outcome == nil else { return false }
            outcome = image.map(Outcome.drawn) ?? .notDrawn
            return true
        }
        if isFirst {
            done.signal()
        }
    }

    /// How the drawing ended, waiting `seconds` at most for it to end.
    func wait(seconds: Int) -> Outcome {
        guard done.wait(timeout: .now() + .seconds(seconds)) == .success else {
            return .unanswered
        }
        return outcome.withLock { $0 } ?? .unanswered
    }
}
