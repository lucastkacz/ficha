// Ficha's detection probe (#12), throwaway. About once a second, it reads
// whether the camera or the microphone is in use, whether a video is playing
// and whether an app is in full screen, and what each reading is based on.
//
//   DetectionProbe.app (launched with `open`): a small floating window with the
//       readings, live. Each change is appended to
//       ~/Library/Logs/FichaDetectionProbe.log as one JSON line.
//   DetectionProbe --once: prints the current readings as JSON and exits.
//   DetectionProbe --watch <seconds>: prints each change as a JSON line for that
//       long, then exits.
//
// --once and --watch show no window and take neither the screen nor the
// keyboard. Nothing here asks for a permission: the bundle has no camera or
// microphone usage description, so if anything did touch a device, macOS would
// stop the probe instead of prompting.
import AVFoundation
import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Readings

/// Everything one read found. Only stable values go in here (no ages or
/// timers), so two reads are equal unless something really changed.
struct Readings: Codable, Equatable {
    var camera: CameraReading
    var microphone: MicrophoneReading
    var video: VideoReading
    var fullScreen: FullScreenReading
    var frontmostApp: Owner?
    var permissions: Permissions

    var summary: String {
        [
            "camera \(camera.inUse ? "ON" : "off")",
            "microphone \(microphone.inUse ? "ON" : "off")",
            "video \(video.playing ? "ON" : "off")",
            "full screen \(fullScreen.active ? "ON" : "off")",
        ].joined(separator: ", ")
    }
}

/// A process, as the readings name it.
struct Owner: Codable, Equatable, Hashable {
    var pid: Int32
    var name: String
    var bundleID: String?

    var label: String { "\(name) (pid \(pid))" }
}

struct CameraReading: Codable, Equatable {
    /// Any CoreMediaIO video device runs somewhere.
    var inUse: Bool
    /// CoreMediaIO's devices: `kCMIODevicePropertyDeviceIsRunningSomewhere`.
    var devices: [CaptureDevice]
    /// AVFoundation's video devices: `isInUseByAnotherApplication`, to compare.
    var avFoundation: [CaptureDevice]
}

struct CaptureDevice: Codable, Equatable {
    var name: String
    var transport: String?
    var running: Bool
}

struct MicrophoneReading: Codable, Equatable {
    /// Any input device other than an aggregate runs somewhere.
    var inUse: Bool
    /// A process with a bundle ID, other than this probe or Ficha, runs audio input:
    /// the process-level reading, to compare. A system daemon, historicalaudiod, runs
    /// input on a hidden device whenever any sound plays, so it can't count.
    var anyAppRunningInput: Bool
    /// CoreAudio's devices with input streams: `kAudioDevicePropertyDeviceIsRunningSomewhere`.
    var devices: [CaptureDevice]
    /// CoreAudio's process objects with `kAudioProcessPropertyIsRunningInput`: who uses the input.
    var processes: [AudioProcess]
    /// AVFoundation's audio devices: `isInUseByAnotherApplication`, to compare.
    var avFoundation: [CaptureDevice]
}

struct AudioProcess: Codable, Equatable {
    var owner: Owner
    /// The devices `kAudioProcessPropertyDevices` lists for the direction that's running.
    var devices: [String]
    var ignoredBecause: String?
}

struct VideoReading: Codable, Equatable {
    /// A process that isn't ignored holds a display-sleep assertion.
    var playing: Bool
    /// `PreventUserIdleDisplaySleep` (or its old name, `NoDisplaySleepAssertion`) assertions.
    var displaySleepAssertions: [Assertion]
    /// `PreventUserIdleSystemSleep` (or `NoIdleSleepAssertion`) assertions, to compare:
    /// coreaudiod holds one for each process playing sound.
    var systemSleepAssertions: [Assertion]
    /// CoreAudio's process objects with `kAudioProcessPropertyIsRunningOutput`.
    var processesPlayingAudio: [AudioProcess]
}

struct Assertion: Codable, Equatable {
    var type: String
    var name: String
    var holder: Owner
    /// Undocumented `AssertionOnBehalfOfPID`: coreaudiod sets it to the process it holds the assertion for.
    var onBehalfOf: Owner?
    /// Undocumented `ResourcesUsed`, like `audio-out BuiltInSpeakerDevice`.
    var resources: [String]?
    var ignoredBecause: String?
}

struct FullScreenReading: Codable, Equatable {
    /// A screen shows a full-screen window of the frontmost app.
    var active: Bool
    /// A screen shows a full-screen window of any app.
    var anyScreen: Bool
    var screens: [ScreenReading]
}

struct ScreenReading: Codable, Equatable {
    var name: String
    var displayID: UInt32
    /// In CoreGraphics' global coordinates: top-left origin, in points.
    var bounds: Rect
    /// `NSScreen.safeAreaInsets.top`: the camera housing's height on a notched screen, 0 otherwise.
    var safeAreaTop: Double
    /// The height of the menu bar window on this screen, or nil when no menu bar window is on screen.
    var menuBarHeight: Double?
    /// The owners and layers of the windows below the normal layer that fill this screen:
    /// the desktop's icons (Finder), the wallpaper (Dock) and the like.
    var desktopWindows: [String]
    /// The frontmost normal-layer window that spans the screen's width down to its bottom,
    /// starting no lower than the menu bar or the camera housing.
    var widestWindow: SpanningWindow?
    /// The widest window fills the screen: it starts at the very top, or it starts below the
    /// camera housing while no menu bar is on screen.
    var fullScreen: Bool
}

struct SpanningWindow: Codable, Equatable {
    var owner: Owner
    var bounds: Rect
    /// Points between the screen's top and the window's top.
    var topGap: Double
    var ownerIsFrontmost: Bool
}

struct Rect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var label: String { "\(Int(width))×\(Int(height)) at (\(Int(x)), \(Int(y)))" }
}

struct Permissions: Codable, Equatable {
    /// Who launched the probe. Only a probe launched by launchd (with `open` or from the
    /// Finder) has permissions of its own; one launched from a shell gets the terminal's.
    var launchedBy: String
    var accessibility: Bool
    var screenRecording: Bool
    var inputMonitoring: Bool
    var camera: String
    var microphone: String
}

// MARK: - Processes

let ownProcess = getpid()

/// Names a process: its app name if it has one, or its executable's. Its bundle ID
/// comes from Launch Services or, for helpers and XPC services, from the bundle
/// around its executable.
@MainActor
func owner(_ pid: pid_t) -> Owner {
    let app = NSRunningApplication(processIdentifier: pid)
    let bundleID = app?.bundleIdentifier ?? enclosingBundleID(pid)
    return Owner(pid: pid, name: app?.localizedName ?? command(pid) ?? "?", bundleID: bundleID)
}

/// The bundle ID of the `.app`, `.xpc` or `.appex` bundle the process's executable is in.
func enclosingBundleID(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0, let path = String(utf8String: buffer) else {
        return nil
    }
    var url = URL(fileURLWithPath: path)
    while url.pathComponents.count > 1 {
        url.deleteLastPathComponent()
        if ["app", "xpc", "appex"].contains(url.pathExtension) { return Bundle(url: url)?.bundleIdentifier }
    }
    return nil
}

/// A process's command name from the kernel (`sysctl`'s `KERN_PROC_PID`), which,
/// unlike `proc_name`, also works for root's processes.
func command(_ pid: pid_t) -> String? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var request = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&request, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    return name.isEmpty ? nil : name
}

/// Why a process doesn't count, if it doesn't: it's this probe or Ficha.
func ignoreReason(_ owner: Owner) -> String? {
    if owner.pid == ownProcess { return "this probe" }
    if owner.bundleID?.hasPrefix("com.lucastkacz.ficha") == true { return "Ficha" }
    return nil
}

/// A four-character code as text, like `bltn` for a built-in device.
func fourCharacterCode(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xff) }
    return String(decoding: bytes, as: UTF8.self)
}

// MARK: - CoreAudio

/// Reads CoreAudio's HAL properties (CoreAudio/AudioHardware.h).
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func size(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
    )
        -> UInt32
    {
        var address = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    static func objects(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = address(selector, scope)
        var size = size(object, selector, scope)
        let stride = MemoryLayout<AudioObjectID>.stride
        guard size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / stride))
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func pid(_ object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - CoreMediaIO

/// Reads CoreMediaIO's properties (CoreMediaIO/CMIOHardwareObject.h and CMIOHardwareDevice.h).
enum CMIO {
    static let system = CMIOObjectID(kCMIOObjectSystemObject)

    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func objects(_ object: CMIOObjectID, _ selector: Int) -> [CMIOObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = MemoryLayout<CMIOObjectID>.stride
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / stride)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(used) / stride))
    }

    static func uint32(_ object: CMIOObjectID, _ selector: Int) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: CMIOObjectID, _ selector: Int) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - Detector

@MainActor
final class Detector {
    private let cameras = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
        mediaType: .video, position: .unspecified)
    private let microphones = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)

    func read() -> Readings {
        let frontmost = NSWorkspace.shared.frontmostApplication.map { owner($0.processIdentifier) }
        let clients = audioClients()
        return Readings(
            camera: readCamera(),
            microphone: readMicrophone(clients),
            video: readVideo(clients),
            fullScreen: readFullScreen(frontmost: frontmost),
            frontmostApp: frontmost,
            permissions: readPermissions())
    }

    // Camera: CoreMediaIO's video devices, and AVFoundation's to compare.

    private func readCamera() -> CameraReading {
        let devices = CMIO.objects(CMIO.system, kCMIOHardwarePropertyDevices).map { device in
            CaptureDevice(
                name: CMIO.string(device, kCMIOObjectPropertyName) ?? "device \(device)",
                transport: CMIO.uint32(device, kCMIODevicePropertyTransportType).map(fourCharacterCode),
                running: CMIO.uint32(device, kCMIODevicePropertyDeviceIsRunningSomewhere) == 1)
        }
        let avFoundation = cameras.devices.map {
            CaptureDevice(name: $0.localizedName, transport: nil, running: $0.isInUseByAnotherApplication)
        }
        return CameraReading(
            inUse: devices.contains { $0.running },
            devices: devices.sorted { $0.name < $1.name },
            avFoundation: avFoundation.sorted { $0.name < $1.name })
    }

    // Microphone: CoreAudio's input devices running somewhere, with its process
    // objects to say who, and AVFoundation's devices to compare.

    /// One of CoreAudio's process objects with audio running in either direction.
    private struct AudioClient {
        var owner: Owner
        var input: [String]?
        var output: [String]?
    }

    private func audioClients() -> [AudioClient] {
        HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard let pid = HAL.pid(object) else { return nil }
            let input = HAL.uint32(object, kAudioProcessPropertyIsRunningInput) == 1
            let output = HAL.uint32(object, kAudioProcessPropertyIsRunningOutput) == 1
            guard input || output else { return nil }
            var who = owner(pid)
            if who.bundleID == nil, let bundleID = HAL.string(object, kAudioProcessPropertyBundleID), !bundleID.isEmpty
            {
                who.bundleID = bundleID
            }
            let devices = { (scope: AudioObjectPropertyScope) in
                HAL.objects(object, kAudioProcessPropertyDevices, scope).map { device in
                    device == kAudioObjectUnknown
                        ? "a hidden device" : HAL.string(device, kAudioObjectPropertyName) ?? "device \(device)"
                }
            }
            return AudioClient(
                owner: who, input: input ? devices(kAudioObjectPropertyScopeInput) : nil,
                output: output ? devices(kAudioObjectPropertyScopeOutput) : nil)
        }
        .sorted { $0.owner.pid < $1.owner.pid }
    }

    private func readMicrophone(_ clients: [AudioClient]) -> MicrophoneReading {
        let devices = HAL.objects(HAL.system, kAudioHardwarePropertyDevices)
            .filter { HAL.size($0, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput) > 0 }
            .map { device in
                CaptureDevice(
                    name: HAL.string(device, kAudioObjectPropertyName) ?? "device \(device)",
                    transport: HAL.uint32(device, kAudioDevicePropertyTransportType).map(fourCharacterCode),
                    running: HAL.uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1)
            }
        let processes = clients.compactMap { client in
            client.input.map {
                AudioProcess(
                    owner: client.owner, devices: $0,
                    ignoredBecause: ignoreReason(client.owner) ?? (client.owner.bundleID == nil ? "no bundle ID" : nil))
            }
        }
        let avFoundation = microphones.devices.map {
            CaptureDevice(name: $0.localizedName, transport: nil, running: $0.isInUseByAnotherApplication)
        }
        return MicrophoneReading(
            // Aggregates, `kAudioDeviceTransportTypeAggregate` ('grup') and the
            // old `kAudioDeviceTransportTypeAutoAggregate` ('fgrp'), are made of
            // other devices, which are read on their own.
            inUse: devices.contains { $0.running && !["grup", "fgrp"].contains($0.transport) },
            anyAppRunningInput: processes.contains { $0.ignoredBecause == nil },
            devices: devices.sorted { $0.name < $1.name },
            processes: processes,
            avFoundation: avFoundation.sorted { $0.name < $1.name })
    }

    // Video: power assertions that keep the display awake (IOKit/pwr_mgt/IOPMLib.h).

    private func readVideo(_ clients: [AudioClient]) -> VideoReading {
        var display: [Assertion] = []
        var system: [Assertion] = []
        var byProcess: Unmanaged<CFDictionary>?
        if IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
            let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        {
            for (pid, list) in assertions {
                let holder = owner(pid.int32Value)
                for properties in list {
                    guard let type = properties[kIOPMAssertionTypeKey] as? String,
                        (properties[kIOPMAssertionLevelKey] as? Int) != Int(kIOPMAssertionLevelOff)
                    else { continue }
                    let onBehalfOf = (properties["AssertionOnBehalfOfPID"] as? NSNumber).map { owner($0.int32Value) }
                    let assertion = Assertion(
                        type: type,
                        name: properties[kIOPMAssertionNameKey] as? String ?? "",
                        holder: holder,
                        onBehalfOf: onBehalfOf,
                        resources: properties["ResourcesUsed"] as? [String],
                        ignoredBecause: ignoreReason(onBehalfOf ?? holder))
                    switch type {
                    case kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertionTypeNoDisplaySleep:
                        display.append(assertion)
                    case kIOPMAssertPreventUserIdleSystemSleep, kIOPMAssertionTypeNoIdleSleep:
                        // Only what apps and audio hold: system daemons' come and go every few
                        // seconds (Handoff, Bluetooth advertising, RunningBoard's background
                        // tasks for apps) and would flood the log.
                        if assertion.resources != nil || holder.bundleID != nil {
                            system.append(assertion)
                        }
                    default:
                        continue
                    }
                }
            }
        }
        let order: (Assertion, Assertion) -> Bool = {
            ($0.holder.pid, $0.onBehalfOf?.pid ?? 0, $0.name) < ($1.holder.pid, $1.onBehalfOf?.pid ?? 0, $1.name)
        }
        let sound = clients.compactMap { client in
            client.output.map {
                AudioProcess(owner: client.owner, devices: $0, ignoredBecause: ignoreReason(client.owner))
            }
        }
        return VideoReading(
            playing: display.contains { $0.ignoredBecause == nil },
            displaySleepAssertions: display.sorted(by: order),
            systemSleepAssertions: system.sorted(by: order),
            processesPlayingAudio: sound)
    }

    // Full screen: on-screen windows' layers, bounds and owners (CoreGraphics/CGWindow.h).
    // Window names need Screen Recording, so nothing here reads them.

    private struct Window {
        var layer: Int
        var bounds: CGRect
        var pid: pid_t
        var ownerName: String
    }

    private func readFullScreen(frontmost: Owner?) -> FullScreenReading {
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let windows: [Window] = info.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                let pid = window[kCGWindowOwnerPID as String] as? Int32,
                let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            return Window(
                layer: layer, bounds: bounds, pid: pid,
                ownerName: window[kCGWindowOwnerName as String] as? String ?? "?")
        }
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let screens: [ScreenReading] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            let safeAreaTop = Double(screen.safeAreaInsets.top)
            let menuBar = windows.first {
                $0.layer == menuBarLevel && abs($0.bounds.minY - bounds.minY) < 1 && $0.bounds.intersects(bounds)
            }
            let desktop = windows.filter { $0.layer < 0 && $0.bounds.equalTo(bounds) }.map {
                "\($0.ownerName) (\($0.layer))"
            }
            let reach = max(safeAreaTop, Double(menuBar?.bounds.height ?? 0), 40)
            // Only regular apps' windows: the Dock briefly puts a screen-sized window on the
            // normal layer while switching Spaces or apps.
            let spanning = windows.first { window in
                window.layer == 0 && window.pid != ownProcess
                    && NSRunningApplication(processIdentifier: window.pid)?.activationPolicy == .regular
                    && abs(window.bounds.minX - bounds.minX) < 1 && abs(window.bounds.maxX - bounds.maxX) < 1
                    && abs(window.bounds.maxY - bounds.maxY) < 1
                    && window.bounds.minY - bounds.minY > -1 && window.bounds.minY - bounds.minY <= reach
            }
            let widest = spanning.map { window in
                SpanningWindow(
                    owner: owner(window.pid), bounds: Rect(window.bounds), topGap: window.bounds.minY - bounds.minY,
                    ownerIsFrontmost: window.pid == frontmost?.pid)
            }
            let fullScreen = widest.map { window in
                window.topGap < 1 || (menuBar == nil && window.topGap <= safeAreaTop + 1)
            }
            return ScreenReading(
                name: screen.localizedName, displayID: displayID, bounds: Rect(bounds), safeAreaTop: safeAreaTop,
                menuBarHeight: menuBar.map { Double($0.bounds.height) }, desktopWindows: desktop, widestWindow: widest,
                fullScreen: fullScreen ?? false)
        }
        return FullScreenReading(
            active: screens.contains { $0.fullScreen && $0.widestWindow?.ownerIsFrontmost == true },
            anyScreen: screens.contains { $0.fullScreen },
            screens: screens)
    }

    // Permissions: only checks, none of these asks.

    private func readPermissions() -> Permissions {
        let parent = getppid()
        return Permissions(
            launchedBy: parent == 1 ? "launchd (open or the Finder)" : owner(parent).label,
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess(),
            inputMonitoring: CGPreflightListenEventAccess(),
            camera: authorization(.video),
            microphone: authorization(.audio))
    }

    private func authorization(_ media: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}

// MARK: - Recording

/// One line of the log, or the output of --once.
struct Entry: Encodable {
    var at: String
    var changed: [String]?
    var summary: String
    var readings: Readings
}

@MainActor
final class Recorder {
    private let detector = Detector()
    private let handle: FileHandle
    private let clock = ISO8601DateFormatter()
    private(set) var readings: Readings
    var onChange: (Readings) -> Void = { _ in }

    init(handle: FileHandle) {
        self.handle = handle
        clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        clock.timeZone = .current
        readings = detector.read()
        write(Entry(at: clock.string(from: Date()), changed: ["start"], summary: readings.summary, readings: readings))
    }

    func tick() {
        let next = detector.read()
        guard next != readings else { return }
        var changed: [String] = []
        if next.camera != readings.camera { changed.append("camera") }
        if next.microphone != readings.microphone { changed.append("microphone") }
        if next.video != readings.video { changed.append("video") }
        if next.fullScreen != readings.fullScreen { changed.append("fullScreen") }
        if next.frontmostApp != readings.frontmostApp { changed.append("frontmostApp") }
        if next.permissions != readings.permissions { changed.append("permissions") }
        readings = next
        write(Entry(at: clock.string(from: Date()), changed: changed, summary: next.summary, readings: next))
        onChange(next)
    }

    private func write(_ entry: Entry) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry) else { return }
        handle.write(data + Data("\n".utf8))
    }
}

// MARK: - Window

@MainActor
final class Model: ObservableObject {
    @Published var readings: Readings

    init(readings: Readings) { self.readings = readings }
}

struct SignalView: View {
    var title: String
    var on: Bool
    var state: String
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(on ? Color.red : Color.secondary.opacity(0.4)).frame(width: 10, height: 10)
                Text(verbatim: title).font(.headline)
                Text(verbatim: state).font(.headline).foregroundStyle(on ? Color.red : Color.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ProbeView: View {
    @ObservedObject var model: Model
    let logPath: String

    var body: some View {
        let readings = model.readings
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SignalView(
                        title: "Camera", on: readings.camera.inUse,
                        state: readings.camera.inUse ? "in use" : "not in use",
                        lines: cameraLines(readings.camera))
                    SignalView(
                        title: "Microphone", on: readings.microphone.inUse,
                        state: readings.microphone.inUse ? "in use" : "not in use",
                        lines: microphoneLines(readings.microphone))
                    SignalView(
                        title: "Video", on: readings.video.playing,
                        state: readings.video.playing ? "playing" : "not playing",
                        lines: videoLines(readings.video))
                    SignalView(
                        title: "Full screen", on: readings.fullScreen.active,
                        state: readings.fullScreen.active ? "yes" : "no",
                        lines: fullScreenLines(readings))
                    SignalView(title: "Permissions", on: false, state: "", lines: permissionLines(readings.permissions))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            Divider()
            HStack {
                Text(verbatim: "Logging changes to \(logPath)").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(8)
        }
    }

    private func cameraLines(_ camera: CameraReading) -> [String] {
        let devices = camera.devices.map {
            "CoreMediaIO: \($0.name) [\($0.transport ?? "?")] \($0.running ? "RUNNING" : "idle")"
        }
        let av = camera.avFoundation.map { "AVFoundation: \($0.name) \($0.running ? "IN USE by another app" : "free")" }
        return (devices.isEmpty ? ["CoreMediaIO: no video devices"] : devices) + av
    }

    private func microphoneLines(_ microphone: MicrophoneReading) -> [String] {
        let processes = microphone.processes.map { process in
            "input: \(process.owner.label) on \(process.devices.joined(separator: ", "))"
                + (process.ignoredBecause.map { " (ignored: \($0))" } ?? "")
        }
        let devices = microphone.devices.map {
            "device: \($0.name) [\($0.transport ?? "?")] \($0.running ? "RUNNING" : "idle")"
        }
        let av = microphone.avFoundation.map {
            "AVFoundation: \($0.name) \($0.running ? "IN USE by another app" : "free")"
        }
        return devices + (processes.isEmpty ? ["input: no process"] : processes)
            + ["by process: \(microphone.anyAppRunningInput ? "an app runs input" : "no app runs input")"] + av
    }

    private func videoLines(_ video: VideoReading) -> [String] {
        let display = video.displaySleepAssertions.map { "display: \(assertionLine($0))" }
        let system = video.systemSleepAssertions.map { "system: \(assertionLine($0))" }
        let audio = video.processesPlayingAudio.map {
            "sound: \($0.owner.label) on \($0.devices.joined(separator: ", "))"
        }
        return (display.isEmpty ? ["display: no assertion"] : display) + system + audio
    }

    private func assertionLine(_ assertion: Assertion) -> String {
        var line = "\(assertion.holder.label)"
        if let onBehalfOf = assertion.onBehalfOf { line += " for \(onBehalfOf.label)" }
        line += " \"\(assertion.name)\""
        if let resources = assertion.resources { line += " [\(resources.joined(separator: " "))]" }
        if let reason = assertion.ignoredBecause { line += " (ignored: \(reason))" }
        return line
    }

    private func fullScreenLines(_ readings: Readings) -> [String] {
        let front = "frontmost: \(readings.frontmostApp?.label ?? "none")"
        return [front]
            + readings.fullScreen.screens.flatMap { screen -> [String] in
                let menuBar = screen.menuBarHeight.map { "menu bar \(Int($0)) pt" } ?? "NO menu bar"
                let header =
                    "\(screen.name) \(screen.bounds.label), notch \(Int(screen.safeAreaTop)) pt, \(menuBar)"
                    + (screen.fullScreen ? ": FULL SCREEN" : "")
                let window =
                    screen.widestWindow.map {
                        "  widest: \($0.owner.label) \($0.bounds.label), top gap \(Int($0.topGap)) pt"
                            + ($0.ownerIsFrontmost ? ", frontmost" : "")
                    } ?? "  widest: none"
                let desktop =
                    "  desktop: "
                    + (screen.desktopWindows.isEmpty ? "none" : screen.desktopWindows.joined(separator: ", "))
                return [header, window, desktop]
            }
    }

    private func permissionLines(_ permissions: Permissions) -> [String] {
        [
            "launched by \(permissions.launchedBy)",
            "accessibility \(permissions.accessibility), screen recording \(permissions.screenRecording), "
                + "input monitoring \(permissions.inputMonitoring)",
            "camera \(permissions.camera), microphone \(permissions.microphone)",
        ]
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var recorder: Recorder?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/Logs/FichaDetectionProbe.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            NSLog("DetectionProbe: can't open %@", logURL.path)
            NSApp.terminate(nil)
            return
        }
        handle.seekToEndOfFile()
        let recorder = Recorder(handle: handle)
        let model = Model(readings: recorder.readings)
        recorder.onChange = { model.readings = $0 }
        self.recorder = recorder

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Ficha detection probe (#12)"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ProbeView(model: model, logPath: logURL.path))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 540, y: frame.maxY - 20))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        // In the common modes, so the readings keep coming while the panel is dragged.
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { recorder.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The panel is the probe's only window: closing it quits.
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

// MARK: - Main

let arguments = CommandLine.arguments
if arguments.contains("--once") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let readings = Detector().read()
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    clock.timeZone = .current
    let entry = Entry(at: clock.string(from: Date()), changed: nil, summary: readings.summary, readings: readings)
    if let data = try? encoder.encode(entry) {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
    exit(0)
} else if let index = arguments.firstIndex(of: "--watch") {
    let seconds = arguments.dropFirst(index + 1).first.flatMap(Double.init) ?? 10
    let recorder = Recorder(handle: .standardOutput)
    let timer = Timer(timeInterval: 1, repeats: true) { _ in
        MainActor.assumeIsolated { recorder.tick() }
    }
    RunLoop.main.add(timer, forMode: .default)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    exit(0)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
