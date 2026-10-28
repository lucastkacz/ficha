import AppKit
import CoreAudio
import CoreMediaIO
import FichaCore
import IOKit.pwr_mgt

/// What the detectors see at a moment: whether a camera or a microphone is
/// in use, which apps keep the display awake, and which app is in full
/// screen. Each is read the way #12's prototype found, with no permission
/// (`docs/prototypes/suppression-detection.md`).
struct Detection: Equatable {
    /// The cameras running in some process, by name.
    var cameras: DetectorReading
    /// The microphones running in some process, by name.
    var microphones: DetectorReading
    /// The apps using a microphone, by name, which Diagnostics shows to tell
    /// a call from dictation. It never decides anything: a system daemon runs
    /// input whenever sound plays (#12's findings).
    var microphoneApps: DetectorReading
    /// The apps that keep the display awake, as a video player does, by name.
    var displayAwake: DetectorReading
    /// The app in front, by name, while it's in full screen.
    var fullScreen: DetectorReading

    /// What the detectors see now.
    static func read() -> Detection {
        Detection(
            cameras: runningCameras(), microphones: runningMicrophones(), microphoneApps: appsUsingTheMicrophone(),
            displayAwake: appsKeepingTheDisplayAwake(), fullScreen: fullScreenApp())
    }

    /// The suppressions the detectors read. A Focus isn't one: macOS says
    /// when it's on, through Ficha's filter.
    static let suppressions: [Suppression] = [.meeting, .video, .fullScreen]

    /// Whether `suppression` is on, by the readings, or nil when they can't
    /// tell: a meeting while a camera or a microphone is in use, a video
    /// while an app keeps the display awake, and the app in front in full
    /// screen. They never tell a Focus.
    func isOn(_ suppression: Suppression) -> Bool? {
        switch suppression {
        case .meeting:
            if cameras.isInUse == true || microphones.isInUse == true {
                true
            } else if cameras.isInUse == nil || microphones.isInUse == nil {
                nil
            } else {
                false
            }
        case .video: displayAwake.isInUse
        case .fullScreen: fullScreen.isInUse
        case .focus: nil
        }
    }
}

/// What one detector sees.
enum DetectorReading: Equatable {
    /// What's in use, by name: devices or apps.
    case inUse([String])
    /// Nothing is.
    case notInUse
    /// The OS didn't answer, so the detector can't tell.
    case unknown

    /// Whether something is in use, or nil when the detector can't tell.
    var isInUse: Bool? {
        switch self {
        case .inUse: true
        case .notInUse: false
        case .unknown: nil
        }
    }

    /// `names` in use, or nothing when there are none; or, when a part of
    /// the reading failed and nothing is in use, that it can't tell.
    init(_ names: [String], anyFailed: Bool = false) {
        self =
            if !names.isEmpty {
                .inUse(names)
            } else if anyFailed {
                .unknown
            } else {
                .notInUse
            }
    }
}

// MARK: - Cameras

/// The video devices CoreMediaIO lists that run in some process
/// (`kCMIODevicePropertyDeviceIsRunningSomewhere`), which needs no permission.
private func runningCameras() -> DetectorReading {
    guard let devices = cmioObjects(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices) else {
        return .unknown
    }
    var running: [String] = []
    var anyFailed = false
    for device in devices {
        switch cmioUInt32(device, kCMIODevicePropertyDeviceIsRunningSomewhere) {
        case 1?:
            running.append(
                cmioString(device, kCMIOObjectPropertyName)
                    ?? String(
                        localized: "A camera", comment: "A camera whose name the OS doesn't give, in Diagnostics."))
        case _?:
            break
        case nil:
            anyFailed = true
        }
    }
    return DetectorReading(running, anyFailed: anyFailed)
}

private func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(selector),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

private func cmioObjects(_ object: CMIOObjectID, _ selector: Int) -> [CMIOObjectID]? {
    var address = cmioAddress(selector)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
    let stride = MemoryLayout<CMIOObjectID>.stride
    var objects = [CMIOObjectID](repeating: 0, count: Int(size) / stride)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &objects) == noErr else { return nil }
    return Array(objects.prefix(Int(used) / stride))
}

private func cmioUInt32(_ object: CMIOObjectID, _ selector: Int) -> UInt32? {
    var address = cmioAddress(selector)
    var value: UInt32 = 0
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == noErr else { return nil }
    return value
}

private func cmioString(_ object: CMIOObjectID, _ selector: Int) -> String? {
    var address = cmioAddress(selector)
    var value: Unmanaged<CFString>?
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, $0)
    }
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

// MARK: - Microphones

/// The audio devices with input that run in some process
/// (`kAudioDevicePropertyDeviceIsRunningSomewhere`), which needs no
/// permission. Aggregates are left out: they're made of other devices, which
/// are read on their own.
private func runningMicrophones() -> DetectorReading {
    guard let devices = audioObjects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) else {
        return .unknown
    }
    var running: [String] = []
    var anyFailed = false
    for device in devices {
        guard let hasInput = hasInput(device), let transport = audioUInt32(device, kAudioDevicePropertyTransportType)
        else {
            anyFailed = true
            continue
        }
        let isAggregate =
            transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeAutoAggregate
        guard hasInput, !isAggregate else { continue }
        switch audioUInt32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) {
        case 1?:
            running.append(
                audioString(device, kAudioObjectPropertyName)
                    ?? String(
                        localized: "A microphone",
                        comment: "A microphone whose name the OS doesn't give, in Diagnostics."
                    ))
        case _?:
            break
        case nil:
            anyFailed = true
        }
    }
    return DetectorReading(running, anyFailed: anyFailed)
}

/// The apps running audio input, through CoreAudio's process objects, but
/// those with no bundle identifier, like the system daemon that runs input
/// whenever sound plays, and Ficha.
private func appsUsingTheMicrophone() -> DetectorReading {
    guard
        let processes = audioObjects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    else {
        return .unknown
    }
    var apps: Set<String> = []
    var anyFailed = false
    for process in processes {
        guard let isRunningInput = audioUInt32(process, kAudioProcessPropertyIsRunningInput),
            let pid = audioUInt32(process, kAudioProcessPropertyPID).map({ pid_t(bitPattern: $0) })
        else {
            anyFailed = true
            continue
        }
        let bundleID = audioString(process, kAudioProcessPropertyBundleID) ?? ""
        guard isRunningInput == 1, !bundleID.isEmpty, !isFicha(pid) else { continue }
        apps.insert(appName(pid))
    }
    return DetectorReading(apps.sorted(), anyFailed: anyFailed)
}

/// Whether the device has input streams, or nil when the OS doesn't say.
private func hasInput(_ device: AudioObjectID) -> Bool? {
    var address = audioAddress(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return nil }
    return size > 0
}

private func audioAddress(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func audioObjects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
    var address = audioAddress(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
    let stride = MemoryLayout<AudioObjectID>.stride
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / stride)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return nil }
    return Array(objects.prefix(Int(size) / stride))
}

private func audioUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var address = audioAddress(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

private func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = audioAddress(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

// MARK: - Videos

/// The apps, other than Ficha, that hold a power assertion keeping the
/// display awake (`PreventUserIdleDisplaySleep`, or its old name), as video
/// players and browsers playing a video do and music apps don't. It needs no
/// permission.
private func appsKeepingTheDisplayAwake() -> DetectorReading {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
        let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else {
        return .unknown
    }
    let displayAwake: Set<String> = [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertionTypeNoDisplaySleep]
    var holders: Set<String> = []
    var anyFailed = false
    for (pid, list) in assertions where !isFicha(pid.int32Value) {
        for properties in list {
            guard let type = properties[kIOPMAssertionTypeKey] as? String,
                let level = properties[kIOPMAssertionLevelKey] as? Int
            else {
                anyFailed = true
                continue
            }
            if displayAwake.contains(type), level == Int(kIOPMAssertionLevelOn) {
                holders.insert(appName(pid.int32Value))
            }
        }
    }
    return DetectorReading(holders.sorted(), anyFailed: anyFailed)
}

// MARK: - Full screen

/// The app in front, while one of its windows covers a whole screen: from
/// the screen's very top, or from under the camera housing of a notched
/// screen while its menu bar is gone. It reads the windows' layers, bounds
/// and owners, which need no permission, and never their names.
private func fullScreenApp() -> DetectorReading {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
        let frontmost = NSWorkspace.shared.frontmostApplication
    else {
        return .unknown
    }
    guard !isFicha(frontmost.processIdentifier) else {
        return .notInUse
    }
    let windows = info.compactMap(ScreenWindow.init)
    guard windows.count == info.count else {
        return .unknown
    }
    var anyFailed = false
    for screen in NSScreen.screens {
        switch covers(screen, withAWindowOf: frontmost.processIdentifier, among: windows) {
        case true?: return .inUse([frontmost.localizedName ?? appName(frontmost.processIdentifier)])
        case false?: break
        case nil: anyFailed = true
        }
    }
    return anyFailed ? .unknown : .notInUse
}

/// A window on screen, as the window list describes it.
private struct ScreenWindow {
    let layer: Int
    let bounds: CGRect
    let pid: pid_t

    init?(_ info: [String: Any]) {
        guard let layer = info[kCGWindowLayer as String] as? Int,
            let pid = info[kCGWindowOwnerPID as String] as? Int32,
            let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsInfo)
        else {
            return nil
        }
        self.layer = layer
        self.bounds = bounds
        self.pid = pid
    }
}

/// Whether a normal window of the app with `pid` covers `screen` as a
/// full-screen window does, or nil when the screen doesn't say which display
/// it is. Bounds are in points, from the main screen's top-left corner, as
/// the window list gives them.
private func covers(_ screen: NSScreen, withAWindowOf pid: pid_t, among windows: [ScreenWindow]) -> Bool? {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return nil
    }
    let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    let cameraHousing = Double(screen.safeAreaInsets.top)
    let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    let hasMenuBar = windows.contains {
        $0.layer == menuBarLevel && abs($0.bounds.minY - bounds.minY) < 1 && $0.bounds.intersects(bounds)
    }
    return windows.contains { window in
        guard window.layer == 0, window.pid == pid,
            abs(window.bounds.minX - bounds.minX) < 1, abs(window.bounds.maxX - bounds.maxX) < 1,
            abs(window.bounds.maxY - bounds.maxY) < 1
        else {
            return false
        }
        let topGap = window.bounds.minY - bounds.minY
        return abs(topGap) < 1 || (!hasMenuBar && topGap > -1 && topGap <= cameraHousing + 1)
    }
}

// MARK: - Processes

/// Whether the process is Ficha or Ficha Dev, which never holds its own
/// appearances back.
private func isFicha(_ pid: pid_t) -> Bool {
    pid == ProcessInfo.processInfo.processIdentifier
        || NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?.hasPrefix("com.lucastkacz.ficha") == true
}

/// The name of the app with `pid`, or of its process when it isn't an app.
private func appName(_ pid: pid_t) -> String {
    if let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
        return name
    }
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var request = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let unnamed = String(
        localized: "Process \(pid)", comment: "A process with no name, by its id, in Diagnostics: a noun.")
    guard sysctl(&request, UInt32(request.count), &info, &size, nil, 0) == 0, size > 0 else {
        return unnamed
    }
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    return name.isEmpty ? unnamed : name
}
