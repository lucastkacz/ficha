// A throwaway app that stands for the app Lucas types in: one window with a
// text field. It logs when its window gains or loses the keyboard, and when it
// becomes active or not, so an agent can tell whether the keyboard came back
// after Ficha's panel closed. Usage: open -n Probe.app --args <log file> <seconds>
import AppKit

let arguments = CommandLine.arguments
let logFile = arguments.count > 1 ? arguments[1] : "/dev/null"
let lifetime = arguments.count > 2 ? Double(arguments[2]) ?? 12 : 12
FileManager.default.createFile(atPath: logFile, contents: nil)
let handle = FileHandle(forWritingAtPath: logFile)
let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"
func log(_ message: String) {
    handle?.write("\(formatter.string(from: Date())) probe: \(message)\n".data(using: .utf8)!)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(
    contentRect: NSRect(x: 160, y: 160, width: 320, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Probe (prueba de foco)"
let field = NSTextField(frame: NSRect(x: 20, y: 30, width: 280, height: 24))
window.contentView?.addSubview(field)
let center = NotificationCenter.default
for (name, text) in [
    (NSWindow.didBecomeKeyNotification, "window became key"),
    (NSWindow.didResignKeyNotification, "window resigned key"),
] {
    center.addObserver(forName: name, object: window, queue: .main) { _ in log(text) }
}
for (name, text) in [
    (NSApplication.didBecomeActiveNotification, "app became active"),
    (NSApplication.didResignActiveNotification, "app resigned active"),
] {
    center.addObserver(forName: name, object: nil, queue: .main) { _ in log(text) }
}
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    log("got key \(event.keyCode)")
    return event
}
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(field)
log("launched")
Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { _ in
    log("quits")
    exit(0)
}
app.run()
