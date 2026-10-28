import Foundation

extension URL {
    /// Its path as Finder and the Terminal write it: with a tilde in place of
    /// `home`, the user's home folder, when it's in there, and no slash at
    /// its end. Foundation's `abbreviatingWithTildeInPath` does the same with
    /// the home folder it knows, which in the sandbox is the app's container:
    /// a folder in the App Group's, as the Backups folder is, isn't in there
    /// (#305).
    public func path(abbreviatingHome home: String) -> String {
        let components = standardized.pathComponents
        let homeComponents = URL(filePath: home, directoryHint: .isDirectory).standardized.pathComponents
        let shown =
            components.starts(with: homeComponents)
            ? ["~"] + components.dropFirst(homeComponents.count) : components
        return NSString.path(withComponents: shown)
    }
}
