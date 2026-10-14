import AppKit
import SwiftUI

/// Ficha Dev's debug menu, in the menu under its icon, so Lucas and agents can
/// try a change in minutes: it loads sample cards and moves Ficha Dev's time
/// forward. The real Ficha has none (`AppVariant.hasDebugMenu`).
struct DebugMenu: View {
    let tools: DebugTools

    var body: some View {
        Menu("Depuración") {
            Button("Cargar fichas de ejemplo", action: loadSampleCards)
            Divider()
            ForEach(timeSteps, id: \.self) { step in
                Button("Avanzar \(inWords(step))") {
                    tools.moveTimeForward(by: step)
                }
            }
            Divider()
            Text(timeShiftLine)
        }
    }

    /// How far ahead of the system's time Ficha Dev's time is, in words.
    private var timeShiftLine: String {
        tools.timeShift == 0 ? "El tiempo es el del sistema" : "Tiempo avanzado: \(inWords(tools.timeShift))"
    }

    /// Loads the sample cards, and says why when they couldn't be loaded.
    private func loadSampleCards() {
        do {
            try tools.loadSampleCards()
        } catch {
            let alert = NSAlert()
            alert.messageText = "No se pudieron cargar las fichas de ejemplo"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Aceptar")
            // A menu-bar app isn't active until it's asked to be, and its
            // alert would open behind the other apps.
            NSApplication.shared.activate()
            alert.runModal()
        }
    }
}

/// How far the debug menu moves time forward at a time: from the 10 minutes an
/// untouched review panel stays open to the 30 days a learned card waits.
private let timeSteps: [TimeInterval] = [10 * 60, 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60, 30 * 24 * 60 * 60]

/// An interval in words, in Spanish, like "1 día y 2 horas".
private func inWords(_ interval: TimeInterval) -> String {
    Duration.seconds(interval).formatted(
        .units(allowed: [.days, .hours, .minutes], width: .wide).locale(Locale(identifier: "es"))
    )
}
