import AppKit
import FichaData
import SwiftUI

/// Shows an alert that tells Lucas what went wrong, in front of the other
/// apps, and waits until he closes it.
func showAlert(_ message: String, explaining error: any Error, style: NSAlert.Style, button: String) {
    showAlert(message, details: error.localizedDescription, style: style, button: button)
}

/// Shows an alert headed by `message`, in front of the other apps, since a
/// menu-bar app isn't active until it's asked to be, and waits until Lucas
/// closes it.
func showAlert(_ message: String, details: String, style: NSAlert.Style, button: String) {
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = message
    alert.informativeText = details
    alert.addButton(withTitle: button)
    NSApplication.shared.activate()
    alert.runModal()
}

/// Something Lucas did that couldn't be saved, as an alert says it.
struct Failure {
    /// What couldn't be done, which heads the alert.
    let title: LocalizedStringResource
    /// Why, which the alert says under it.
    let error: EngineError
}

extension View {
    /// An alert that says what couldn't be done, and why, while `failure`
    /// holds something, which closing it clears.
    func failureAlert(_ failure: Binding<Failure?>) -> some View {
        alert(
            failure.wrappedValue.map { Text($0.title) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } }),
            presenting: failure.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure.error.localizedDescription)
        }
    }
}
