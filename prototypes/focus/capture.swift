// Waits for the prototype instance's floating panel, then captures only that window.
import AppKit
import CoreGraphics

let pathPart = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path.contains(pathPart) == true }),
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
        let window = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
                && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
        }),
        let number = window[kCGWindowNumber as String] as? Int
    {
        Thread.sleep(forTimeInterval: 2)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l\(number)", "-o", "-x", output]
        try process.run()
        process.waitUntilExit()
        print(
            "captured window \(number) of pid \(app.processIdentifier), bounds \(window[kCGWindowBounds as String] ?? "?")"
        )
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
print("no panel found")
exit(1)
