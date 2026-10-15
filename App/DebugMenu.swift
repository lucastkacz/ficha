import AppKit
import SwiftUI

/// Ficha Dev's debug menu, in the menu under its icon, so Lucas and agents can
/// try a change in minutes: it loads sample cards and moves Ficha Dev's time
/// forward. The real Ficha has none (`AppVariant.hasDebugMenu`). Its texts are
/// in English and verbatim, so they stay out of the String Catalog: the debug
/// menu isn't translated (ADR 0009).
struct DebugMenu: View {
    let tools: DebugTools
    /// What to do once the time moved, since cards may have come due.
    let timeMoved: () -> Void

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
            Text(timeShiftLine)
        } label: {
            Text(verbatim: "Debug")
        }
    }

    /// How far ahead of the system's time Ficha Dev's time is, in words.
    private var timeShiftLine: String {
        tools.timeShift == .zero ? "On the system's time" : "Time moved forward by \(inWords(tools.timeShift))"
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
private func inWords(_ duration: Duration) -> String {
    duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide).locale(Locale(identifier: "en")))
}
