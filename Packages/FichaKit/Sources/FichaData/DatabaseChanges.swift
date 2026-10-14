import Foundation
import notify
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "engine")

/// How the engines on one database tell each other that it changed, even from
/// another process, as the app and the `ficha` CLI are: a Darwin notification
/// named after the database. SQLite doesn't tell one process about another's
/// writes, and GRDB's guide to sharing a database suggests this instead.
struct DatabaseChanges: Sendable {
    private let name: String

    /// The notifications for `database`: its file's path, or a name of its own
    /// for an in-memory database.
    init(database: String) {
        name = "com.lucastkacz.ficha.database-changed: \(database)"
    }

    /// Tells every engine on the database, in this process or another, that it
    /// changed.
    func post() {
        let status = notify_post(name)
        if status != NOTIFY_STATUS_OK {
            logger.error("Couldn't tell the other engines that the database changed: notify status \(status)")
        }
    }

    /// Every change from now on, until the stream is dropped. Changes that come
    /// while one waits to be handled are merged into it.
    func stream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .global()) { _ in
                continuation.yield()
            }
            guard status == NOTIFY_STATUS_OK else {
                logger.error("Couldn't listen for changes to the database: notify status \(status)")
                continuation.finish()
                return
            }
            continuation.onTermination = { [token] _ in
                notify_cancel(token)
            }
        }
    }
}
