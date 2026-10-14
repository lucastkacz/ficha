import Foundation

/// What can go wrong in the engine. Each message says what happened and what
/// to do about it, in Spanish, since Lucas reads it in the app.
public enum EngineError: Error, Equatable {
    /// The database has migrations this version doesn't know: a newer version
    /// of Ficha migrated it, so this one refuses to open it.
    case migratedByNewerVersion
    /// A capture's text was empty, so there was nothing to save.
    case emptyCapture
    /// SQLite couldn't open, read or write the database, for the reason given.
    case storage(String)
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .migratedByNewerVersion:
            """
            Una versión más nueva de Ficha modificó la base de datos, y esta versión no la abre para no dañar \
            tus fichas. Instalá la versión más nueva de Ficha.
            """
        case .emptyCapture:
            "La captura está vacía: escribí lo que querés recordar."
        case .storage(let reason):
            "Ficha no pudo leer o guardar su base de datos (\(reason)). Probá de nuevo y, si sigue pasando, reportalo."
        }
    }
}
