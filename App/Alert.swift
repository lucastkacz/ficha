import AppKit

/// Shows an alert that tells Lucas what went wrong, in front of the other
/// apps, since a menu-bar app isn't active until it's asked to be, and waits
/// until he closes it.
func showAlert(_ message: String, explaining error: any Error, style: NSAlert.Style, button: String) {
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = message
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: button)
    NSApplication.shared.activate()
    alert.runModal()
}
