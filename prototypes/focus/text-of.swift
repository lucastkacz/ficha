// Prints the text of TextEdit's focused text area, through Accessibility. Reads only.
import AppKit
import ApplicationServices

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
    print("TextEdit isn't running")
    exit(1)
}
let element = AXUIElementCreateApplication(app.processIdentifier)
var focused: AnyObject?
AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused)
var value: AnyObject?
if let focused { AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) }
print("TextEdit's focused text: \((value as? String).map { "\"\($0)\"" } ?? "none")")
