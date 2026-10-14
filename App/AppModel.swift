import FichaData
import Observation
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "inbox")

/// The app's way into Lucas's cards: it goes through the engine and keeps what
/// the menu shows up to date.
@Observable
final class AppModel {
    private let engine: Engine
    /// How many captures wait in the inbox, or nil when they couldn't be counted.
    private(set) var inboxCount: Int?

    init(engine: Engine) {
        self.engine = engine
        countInbox()
    }

    /// Saves a capture in the inbox, as the capture window's fields hold it.
    func capture(text: String, note: String, source: String) throws(EngineError) {
        try engine.capture(text: text, note: note, source: source)
        countInbox()
    }

    private func countInbox() {
        do {
            inboxCount = try engine.inbox().count
        } catch {
            logger.error("Couldn't count the inbox: \(error.localizedDescription)")
            inboxCount = nil
        }
    }
}
