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
    /// The apps that keep the display awake, as a video player does, by name.
    var displayAwake: DetectorReading
    /// The app in front, by name, while it's in full screen.
    var fullScreen: DetectorReading

    /// What holds appearances back now: a meeting while a camera or a
    /// microphone is in use, a video while an app keeps the display awake,
    /// and the app in front in full screen. A reading that can't tell holds
    /// nothing back, and Diagnostics shows it.
    var suppressions: Set<Suppression> {
        var suppressions: Set<Suppression> = []
        if cameras.isInUse || microphones.isInUse {
            suppressions.insert(.meeting)
        }
        if displayAwake.isInUse {
            suppressions.insert(.video)
        }
        if fullScreen.isInUse {
            suppressions.insert(.fullScreen)
        }
        return suppressions
    }

    /// What the detectors see now.
    static func now() -> Detection {
        Detection(
            cameras: runningCameras(), microphones: runningMicrophones(), displayAwake: appsKeepingTheDisplayAwake(),
            fullScreen: fullScreenApp())
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

    /// Whether something is in use.
    var isInUse: Bool {
        if case .inUse = self { true } else { false }
    }

    /// `names` in use, or nothing when there are none.
    init(_ names: [String]) {
        self = names.isEmpty ? .notInUse : .inUse(names)
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
    for device in devices {
        guard let isRunning = cmioUInt32(device, kCMIODevicePropertyDeviceIsRunningSomewhere) else {
            return .unknown
        }
        if isRunning == 1 {
            running.append(cmioString(device, kCMIOObjectPropertyName) ?? String(localized: "A camera"))
        }
    }
    return DetectorReading(running)
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
    for device in devices where hasInput(device) && !isAggregate(device) {
        guard let isRunning = audioUInt32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) else {
            return .unknown
        }
        if isRunning == 1 {
            running.append(audioString(device, kAudioObjectPropertyName) ?? String(localized: "A microphone"))
        }
    }
    return DetectorReading(running)
}

/// Whether the device has input streams.
private func hasInput(_ device: AudioObjectID) -> Bool {
    var address = audioAddress(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
}

/// Whether the device is an aggregate: `kAudioDeviceTransportTypeAggregate`,
/// or the old `kAudioDeviceTransportTypeAutoAggregate`.
private func isAggregate(_ device: AudioObjectID) -> Bool {
    let transport = audioUInt32(device, kAudioDevicePropertyTransportType)
    return transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeAutoAggregate
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
    let holders = assertions.compactMap { pid, list -> String? in
        let keepsTheDisplayAwake = list.contains { properties in
            guard let type = properties[kIOPMAssertionTypeKey] as? String else { return false }
            return displayAwake.contains(type)
                && (properties[kIOPMAssertionLevelKey] as? Int) != Int(kIOPMAssertionLevelOff)
        }
        guard keepsTheDisplayAwake, !isFicha(pid.int32Value) else { return nil }
        return appName(pid.int32Value)
    }
    return DetectorReading(Array(Set(holders)).sorted())
}

// MARK: - Full screen

/// The app in front, while one of its windows covers a whole screen: from
/// the screen's very top, or from under the camera housing of a notched
/// screen while its menu bar is gone. It reads the windows' layers, bounds
/// and owners, which need no permission, and never their names.
private func fullScreenApp() -> DetectorReading {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return .unknown
    }
    guard let frontmost = NSWorkspace.shared.frontmostApplication, !isFicha(frontmost.processIdentifier) else {
        return .notInUse
    }
    let windows = info.compactMap(ScreenWindow.init)
    let coversAScreen = NSScreen.screens.contains { screen in
        covers(screen, withAWindowOf: frontmost.processIdentifier, among: windows)
    }
    return coversAScreen ? .inUse([frontmost.localizedName ?? appName(frontmost.processIdentifier)]) : .notInUse
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
/// full-screen window does. Bounds are in points, from the main screen's
/// top-left corner, as the window list gives them.
private func covers(_ screen: NSScreen, withAWindowOf pid: pid_t, among windows: [ScreenWindow]) -> Bool {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return false
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
    guard sysctl(&request, 4, &info, &size, nil, 0) == 0, size > 0 else {
        return String(localized: "Process \(pid)")
    }
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    return name.isEmpty ? String(localized: "Process \(pid)") : name
}
