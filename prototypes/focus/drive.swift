// Waits for the prototype's panel, clicks it (only if it's the topmost window
// there and the given app is frontmost), then presses the given keys, each
// only while that app is frontmost, so no key can land in another app.
// Usage: drive <panel bundle path part> <frontmost bundle id> <button|button-stay|readout> <keys...>
// `button` clicks "Dar vuelta" and `readout` the text under the card;
// `button-stay` leaves the pointer on the panel. Keys go 0.25 s apart.
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
let pathPart = arguments[1]
let guardBundle = arguments[2]
let target = arguments[3]
let keys = Array(arguments.dropFirst(4))
let codes: [String: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "space": 49, "esc": 53, "x": 7, "f19": 80, "return": 36]
let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"
func log(_ message: String) {
    print("\(formatter.string(from: Date())) drive: \(message)")
    fflush(stdout)
}
func windows() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
}
func bounds(_ window: [String: Any]) -> CGRect? {
    (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
}
func guardIsFrontmost() -> Bool {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == guardBundle
}
let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    guard
        let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path.contains(pathPart) == true }
        ),
        let panel = windows().first(where: {
            ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
                && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
        }),
        let frame = bounds(panel)
    else {
        Thread.sleep(forTimeInterval: 0.1)
        continue
    }
    Thread.sleep(forTimeInterval: 0.8)
    // "Dar vuelta" sits at the card's bottom right; the readout is text at the bottom.
    let point =
        target.hasPrefix("button")
        ? CGPoint(x: frame.minX + 315, y: frame.minY + 68) : CGPoint(x: frame.midX, y: frame.maxY - 20)
    let topmost = windows().first(where: { window in
        (bounds(window)?.contains(point) ?? false) && ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0
    })
    guard (topmost?[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier, guardIsFrontmost() else {
        log("not clicking: the panel isn't the topmost window there, or \(guardBundle) isn't frontmost")
        exit(1)
    }
    let original = CGEvent(source: nil)?.location ?? point
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(
            tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
    }
    if !target.hasSuffix("-stay") { CGWarpMouseCursorPosition(original) }
    log("clicked the panel's \(target)")
    for key in keys {
        Thread.sleep(forTimeInterval: 0.25)
        guard let code = codes[key], guardIsFrontmost() else {
            log("not pressing \(key): \(guardBundle) isn't frontmost")
            exit(1)
        }
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)
        }
        log("pressed \(key)")
    }
    exit(0)
}
log("no panel found")
exit(1)
