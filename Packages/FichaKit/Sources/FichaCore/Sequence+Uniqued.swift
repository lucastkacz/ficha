extension Sequence where Element: Hashable {
    /// Its elements, each once, in the order they first come, as Swift
    /// Algorithms' `uniqued()` gives them: tags a file proposes, say.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
