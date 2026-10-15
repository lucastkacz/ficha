import Foundation

/// What can go wrong in the engine. Each message says what happened and what
/// to do about it, in Spanish, since Lucas reads it in the app.
public enum EngineError: Error, Equatable {
    /// The database has migrations this version doesn't know: a newer version
    /// of Ficha migrated it, so this one refuses to open it.
    case migratedByNewerVersion
    /// A capture's text was empty, so there was nothing to save.
    case emptyCapture
    /// The capture with this id isn't in the inbox, so it can't be approved or
    /// discarded: it already was, or it doesn't exist.
    case captureNotInInbox(Int64)
    /// A capture was approved into no cards. One that becomes no cards is
    /// discarded instead.
    case noCards
    /// There's no card with this id.
    case cardNotFound(Int64)
    /// The card with this id already had its first view, so it can't have
    /// another.
    case cardNotNew(Int64)
    /// The card with this id is new, so it can't be reviewed before its first
    /// view.
    case cardIsNew(Int64)
    /// The card with this id isn't due yet, so it can't be reviewed.
    case cardNotDue(Int64)
    /// SQLite couldn't open, read or write the database. The engine logs why.
    case storage
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .migratedByNewerVersion:
            """
            Una versión más nueva de Ficha modificó la base de datos, y esta versión no la abre para no dañar \
            tus fichas. Abrila con la versión que la modificó o con una más nueva.
            """
        case .emptyCapture:
            "La captura está vacía: escribí lo que querés recordar."
        case .captureNotInInbox(let id):
            "La captura \(id) no está en la bandeja: ya se aprobó o se descartó, o no existe. Revisá qué hay en la bandeja."
        case .noCards:
            "Una captura se aprueba en una o más fichas. Para sacarla de la bandeja sin fichas, descartala."
        case .cardNotFound(let id):
            "No hay ninguna ficha con el id \(id). Revisá los ids con `ficha cards`."
        case .cardNotNew(let id):
            "La ficha \(id) ya tuvo su primera vista. \(reopenReviewNow)"
        case .cardIsNew(let id):
            "La ficha \(id) es nueva: antes de repasarla tiene que tener su primera vista. \(reopenReviewNow)"
        case .cardNotDue(let id):
            "La ficha \(id) todavía no está vencida, así que no se puede repasar. \(reopenReviewNow)"
        case .storage:
            "Ficha no pudo leer o guardar su base de datos. Probá de nuevo y, si sigue pasando, reportalo."
        }
    }
}

/// What to do when the review panel shows a card for what it can't be used
/// for: start over with the cards as they are now.
private let reopenReviewNow = "Cerrá la cajita y volvé a abrir «Repasar ahora»."
