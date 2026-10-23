import Foundation

extension Sequence<String> {
    /// These texts in alphabetical order as the Mac sorts text, as Finder
    /// sorts names (`localizedStandardCompare`).
    public func sortedAlphabetically() -> [String] {
        sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
