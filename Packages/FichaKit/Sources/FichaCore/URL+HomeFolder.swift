import Foundation

extension URL {
    /// Its path as Finder and the Terminal write it: with a tilde in place of
    /// `home`, the user's home folder, when it's in there, and no slash at
    /// its end. Foundation's `abbreviatingWithTildeInPath` does the same with
    /// the home folder Foundation knows, which in the sandbox is the app's
    /// container, as `NSHomeDirectory()`'s documentation says: a folder in
    /// the App Group's, as the Backups folder is, isn't in there (#305).
    public func path(abbreviatingHome home: URL) -> String {
        let components = standardized.pathComponents
        let homeComponents = home.standardized.pathComponents
        let shown =
            components.starts(with: homeComponents)
            ? ["~"] + components.dropFirst(homeComponents.count) : components
        return NSString.path(withComponents: shown)
    }
}
