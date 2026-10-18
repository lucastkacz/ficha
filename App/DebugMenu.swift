import AppKit
import FichaCore
import SwiftUI

/// Ficha Dev's debug menu, in the menu under its icon, so Lucas and agents can
/// try a change in minutes: it loads sample cards, moves Ficha Dev's time
/// forward, checks for an appearance right away and turns on a capture
/// shortcut of Ficha Dev's own. The real Ficha has none
/// (`AppVariant.hasDebugMenu`). Its texts are in English and verbatim, so they
/// stay out of the String Catalog: the debug menu isn't translated (ADR 0009).
struct DebugMenu: View {
    let tools: DebugTools
    /// The settings the engine decides with, to say why there's no
    /// appearance.
    let settings: ReviewSettings
    /// What to do once the time moved, since cards may have come due.
    let timeMoved: () -> Void
    /// Asks right away whether the review panel shows up on its own.
    let checkAppearance: () -> AppearanceCheck?
    /// The shortcut that opens "Capture…" from any app, which the menu turns
    /// on and off.
    let captureShortcut: CaptureShortcutRegistration

    var body: some View {
        Menu {
            Button {
                attempt("Couldn't load the sample cards") {
                    try tools.loadSampleCards()
                }
            } label: {
                Text(verbatim: "Load sample cards")
            }
            Divider()
            ForEach(timeSteps, id: \.self) { step in
                Button {
                    attempt("Couldn't move the time forward") {
                        try tools.moveTimeForward(by: step)
                        timeMoved()
                    }
                } label: {
                    Text(verbatim: "Move forward \(inWords(step))")
                }
            }
            Divider()
            Button(action: checkForAppearance) {
                Text(verbatim: "Check for an appearance now")
            }
            Divider()
            Toggle(
                isOn: Binding(get: { captureShortcut.shortcut != nil }, set: { turnCaptureShortcut(on: $0) })
            ) {
                Text(verbatim: "Capture shortcut \(CaptureShortcut.fichaDev.symbols)")
            }
            Divider()
            Text(timeShiftLine)
        } label: {
            Text(verbatim: "Debug")
        }
    }

    /// How far ahead of the system's time Ficha Dev's time is, in words.
    private var timeShiftLine: String {
        tools.timeShift == .zero ? "On the system's time" : "Time moved forward by \(inWords(tools.timeShift))"
    }

    /// Checks for an appearance, as Ficha Dev does every minute: the review
    /// panel shows up if the engine says so, and otherwise an alert says why
    /// not.
    private func checkForAppearance() {
        guard let check = checkAppearance() else { return }
        let noAppearance = "No appearance now"
        switch check {
        case .decided(.show):
            break
        case .decided(.notNow(let reason)):
            showAlert(noAppearance, details: whyNot(reason), style: .informational, button: "OK")
        case .panelOpen:
            showAlert(
                noAppearance, details: "The review panel is open: close it, and check again.", style: .informational,
                button: "OK")
        case .failed(let error):
            showAlert("Couldn't check for an appearance", explaining: error, style: .warning, button: "OK")
        }
    }

    /// Why the engine said there's no appearance now, in words.
    private func whyNot(_ reason: NoAppearance) -> String {
        switch reason {
        case .asleep:
            "The Mac or its screens are asleep."
        case .outsideActiveHours:
            "It's outside active hours, from \(settings.activeHours.lowerBound):00 to \(settings.activeHours.upperBound):00."
        case .tooSoonAfterLastOne(let until):
            """
            The last appearance or review now closed less than \(inWords(settings.separation)) ago: the next \
            appearance can come in \(timeLeft(until)).
            """
        case .tooSoonAfterWaking(let until):
            """
            The Mac woke less than \(inWords(settings.waitAfterWaking)) ago: an appearance can come in \
            \(timeLeft(until)).
            """
        case .nothingDue:
            "No card is due, and no new card can come in today."
        case .suppressed(let suppression):
            "\(heldBackBy(suppression)) holds appearances back: Diagnostics says what each detector sees."
        case .tooSoonAfterSuppression(let until):
            """
            A suppression ended less than \(inWords(settings.waitAfterSuppression)) ago: an appearance can come \
            in \(timeLeft(until)).
            """
        }
    }

    /// What a suppression is, in words, at the start of a sentence.
    private func heldBackBy(_ suppression: Suppression) -> String {
        switch suppression {
        case .meeting: "A meeting (the camera or the microphone in use)"
        case .video: "A video (an app keeping the display awake)"
        case .fullScreen: "A full-screen app"
        }
    }

    /// How long until `time`, by Ficha Dev's time, in words, to the second.
    private func timeLeft(_ time: Date) -> String {
        inWords(.seconds(time.timeIntervalSince(tools.engine.now)), units: [.hours, .minutes, .seconds])
    }

    /// Turns Ficha Dev's capture shortcut on or off, which Ficha Dev keeps
    /// for its next launches. It's not the real Ficha's, so both apps can run
    /// side by side.
    private func turnCaptureShortcut(on: Bool) {
        attempt("Couldn't turn on the capture shortcut") {
            if on {
                try captureShortcut.turnOn(.fichaDev)
            } else {
                captureShortcut.turnOff()
            }
            tools.capturesWithShortcut = on
        }
    }

    /// Does `action`, and when it fails, says why in an alert headed by
    /// `failure`.
    private func attempt(_ failure: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            showAlert(failure, explaining: error, style: .warning, button: "OK")
        }
    }
}

/// How far the debug menu moves time forward at a time: from the 10 minutes an
/// untouched review panel stays open to the 30-day step, from which a card is
/// learned.
private let timeSteps: [Duration] = [
    .seconds(10 * 60), .seconds(60 * 60), .seconds(24 * 60 * 60), .seconds(7 * 24 * 60 * 60),
    .seconds(30 * 24 * 60 * 60),
]

/// A span of time in words, in English, like "1 day, 2 hours".
private func inWords(
    _ duration: Duration,
    units: Set<Duration.UnitsFormatStyle.Unit> = [.days, .hours, .minutes]
) -> String {
    duration.formatted(.units(allowed: units, width: .wide).locale(Locale(identifier: "en")))
}
