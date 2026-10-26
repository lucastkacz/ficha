extension Sequence where Element: Hashable {
    /// Its elements, each once, in the order they first come, as Swift
    /// Algorithms' `uniqued()` gives them: tags a file proposes, say.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Sequence {
    /// Its elements, each once by the key `key` gives it, in the order they
    /// first come, as Swift Algorithms' `uniqued(on:)` gives them: an
    /// imported card's tags by `duplicateKey`, say.
    public func uniqued<Key: Hashable>(on key: (Element) throws -> Key) rethrows -> [Element] {
        var seen = Set<Key>()
        return try filter { try seen.insert(key($0)).inserted }
    }
}
