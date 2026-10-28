/// The app's delegate as its App Intents reach it. The tool leaves out the
/// app's own, `App/AppDelegate.swift`, which loads CloudKit (ADR 0017), but
/// compiles the App Intents, since `SystemMacSignals` reads the Focus filter.
/// The tool never runs as the app, so no App Intent finds it launched. This
/// stand-in is our own: when the App Intents ask the delegate for more, add
/// it here, doing nothing.
final class AppDelegate {
    static var launched: AppDelegate? { nil }

    func focusChanged(holdsBack: Bool) {}

    func openReviewPanel() {}
}
