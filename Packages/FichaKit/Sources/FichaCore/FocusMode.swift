/// Whether the review panel takes the keyboard when it shows up on its own,
/// so it doesn't catch what Lucas is typing in another app. It has nothing to
/// do with macOS's Focus.
public enum FocusMode: Sendable {
    /// It never takes the keyboard on its own: Lucas clicks it.
    case never
    /// It takes the keyboard once Lucas has been idle for a moment.
    case onceIdle
    /// It takes the keyboard as soon as it shows up.
    case always
}

extension FocusMode {
    /// Whether the panel takes the keyboard now, with Lucas idle for `idle`,
    /// or nil when the Mac doesn't say: in the once-idle mode, once he has
    /// been idle for `threshold`.
    public func takesKeyboard(idle: Duration?, after threshold: Duration) -> Bool {
        switch self {
        case .never: false
        case .onceIdle: idle.map { $0 >= threshold } ?? false
        case .always: true
        }
    }
}
