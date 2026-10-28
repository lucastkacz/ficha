import Foundation

/// The app's preferences in a file of its data folder, which carries them
/// into its sandbox, where the app has preferences of its own (ADR 0018):
/// the last build of the real Ficha without its sandbox writes them there,
/// all of them, and the sandboxed Ficha reads them in at its first launch.
public struct PreferencesFile: Sendable {
    /// The file, `Preferences.plist` in the data folder.
    public let file: URL

    /// The preferences file in the data folder `dataFolder`.
    public init(in dataFolder: URL) {
        file = dataFolder.appending(path: "Preferences.plist")
    }

    /// Writes every preference of the domain `domain` in `defaults`, the
    /// app's own, in place of what the file held, as a property list. So
    /// every setting travels, those the app no longer writes too, without
    /// naming them.
    public func write(_ domain: String, from defaults: UserDefaults) throws(PreferencesFileError) {
        let preferences = defaults.persistentDomain(forName: domain) ?? [:]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            try data.write(to: file, options: .atomic)
        } catch {
            moveLogger.error("Couldn't write the preferences file: \(String(describing: error), privacy: .public)")
            throw .unwritable("\(error)")
        }
    }

    /// Reads the file's preferences into `defaults`, the app's own, in place
    /// of those it holds, the first time it's asked, and never again, which
    /// `defaults` keeps: at the sandboxed app's first launch. A file that
    /// isn't there, as for anyone but Lucas, has nothing to read in, and the
    /// app never asks again either. A file that can't be read is refused,
    /// and the app asks again at its next launch. Returns whether it read
    /// preferences in.
    @discardableResult
    public func readIn(to defaults: UserDefaults) throws(PreferencesFileError) -> Bool {
        guard !defaults.bool(forKey: readInKey) else {
            return false
        }
        let preferences: [String: Any]
        do {
            let data = try Data(contentsOf: file)
            guard
                let read = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                throw PreferencesFileError.unreadable("It holds no preferences.")
            }
            preferences = read
        } catch CocoaError.fileReadNoSuchFile {
            defaults.set(true, forKey: readInKey)
            return false
        } catch {
            moveLogger.error("Couldn't read the preferences file: \(String(describing: error), privacy: .public)")
            throw error as? PreferencesFileError ?? .unreadable("\(error)")
        }
        for (key, value) in preferences {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: readInKey)
        moveLogger.notice("Read \(preferences.count) preferences in from the preferences file")
        return true
    }
}

/// The preference that says the preferences file was read in, in the
/// sandboxed app's preferences.
private let readInKey = "PreferencesFileReadIn"

/// Why the preferences file couldn't be written or read. Each says what
/// happened, in English, for the log, which alone shows it.
public enum PreferencesFileError: Error, Equatable, CustomStringConvertible {
    /// It couldn't be written, as this says.
    case unwritable(String)
    /// It couldn't be read, as this says.
    case unreadable(String)

    public var description: String {
        switch self {
        case .unwritable(let reason):
            "Couldn't write the preferences file: \(reason). It's written again as a setting changes."
        case .unreadable(let reason):
            "Couldn't read the preferences file: \(reason). It's read again at the next launch."
        }
    }
}
