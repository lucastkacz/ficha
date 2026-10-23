import SwiftUI

extension View {
    /// Scrolls the table this is to the row `id` names, each time it's set,
    /// by the least that brings the whole row into view, and then calls
    /// `revealed`.
    func revealingRow<ID: Hashable>(_ id: ID?, then revealed: @escaping () -> Void) -> some View {
        ScrollViewReader { proxy in
            onChange(of: id, initial: true) {
                guard let id else { return }
                proxy.scrollTo(id)
                revealed()
            }
        }
    }
}
