import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Where Lucas picks, in Settings, the shortcut that opens "Capture…" from
/// any app: he clicks it and types the shortcut, which turns on at once. Esc
/// leaves the one that was on, Delete turns it off, and a key without two of
/// Control, Option and Command is refused with a beep.
struct CaptureShortcutRecorder: View {
    let registration: CaptureShortcutRegistration
    @State private var recording = Recording()

    var body: some View {
        HStack {
            Button {
                if recording.isOn {
                    recording.cancel()
                } else {
                    recording.start(registration)
                }
            } label: {
                if recording.isOn {
                    Text("Type a shortcut…", comment: "Settings: the capture shortcut, while Lucas types a new one.")
                } else if let shortcut = registration.shortcut {
                    Text(verbatim: shortcut.symbols)
                } else {
                    Text("Record Shortcut", comment: "Settings: the capture shortcut's button, while there's none.")
                }
            }
            if !recording.isOn, registration.shortcut != nil {
                Button {
                    change(registration, to: nil, fallback: nil)
                } label: {
                    Label {
                        Text("Turn Off the Capture Shortcut")
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .onDisappear {
            recording.cancel()
        }
    }
}

/// Lucas typing a new capture shortcut, while he does. The shortcut that was
/// on is off meanwhile, so typing it again records it instead of opening
/// "Capture…". If he leaves the Settings window, or it closes, the one that
/// was on turns on again.
@Observable
private final class Recording {
    /// Whether Lucas is typing a new shortcut.
    private(set) var isOn = false
    @ObservationIgnored private var registration: CaptureShortcutRegistration?
    /// The shortcut that was on as he started.
    @ObservationIgnored private var previous: CaptureShortcut?
    /// What hears his keys, and his leaving the window, while he types.
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// Starts hearing the keys Lucas types in the Settings window, the key
    /// window, with `registration`'s shortcut off meanwhile.
    func start(_ registration: CaptureShortcutRegistration) {
        guard !isOn, let window = NSApplication.shared.keyWindow else { return }
        self.registration = registration
        previous = registration.shortcut
        registration.turnOff()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.typed(event)
            return nil
        }
        for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: notification, object: window, queue: .main) {
                    [weak self] _ in
                    // An observer on the main queue runs on the main actor.
                    MainActor.assumeIsolated {
                        self?.cancel()
                    }
                })
        }
        isOn = true
    }

    /// Stops hearing Lucas's keys and turns on again the shortcut that was
    /// on, if he was typing one, leaving the preferences as they were. When
    /// macOS refuses it, an alert says why.
    func cancel() {
        guard isOn, let registration else { return }
        stop()
        guard let previous else { return }
        do {
            try registration.turnOn(previous)
        } catch {
            showAlert(
                String(localized: "Couldn't turn on the capture shortcut"), explaining: error, style: .warning,
                button: String(localized: "OK"))
        }
    }

    /// What a key Lucas typed does while he types a new shortcut.
    private func typed(_ event: NSEvent) {
        guard let registration else { return }
        let modifiers = eventModifiers(of: event)
        switch Int(event.keyCode) {
        case kVK_Escape where modifiers.isEmpty:
            cancel()
        case kVK_Delete where modifiers.isEmpty, kVK_ForwardDelete where modifiers.isEmpty:
            stop()
            change(registration, to: nil, fallback: nil)
        default:
            guard let shortcut = CaptureShortcut(typed: event) else {
                NSSound.beep()
                return
            }
            stop()
            change(registration, to: shortcut, fallback: previous)
        }
    }

    /// Stops hearing Lucas's keys and his leaving the window.
    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        isOn = false
    }
}

/// Turns `shortcut` on in `registration`, or turns it off when it's nil,
/// keeping it for the next launches. When macOS refuses it, `fallback` turns
/// on instead, as it was, and an alert says why.
private func change(
    _ registration: CaptureShortcutRegistration,
    to shortcut: CaptureShortcut?,
    fallback: CaptureShortcut?
) {
    do {
        try registration.change(to: shortcut, fallback: fallback)
    } catch {
        showAlert(
            String(localized: "Couldn't turn on the capture shortcut"), explaining: error, style: .warning,
            button: String(localized: "OK"))
    }
}
