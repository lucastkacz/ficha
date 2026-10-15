import AppKit
import SwiftUI

/// Ficha Dev's debug menu, in the menu under its icon, so Lucas and agents can
/// try a change in minutes: it loads sample cards and moves Ficha Dev's time
/// forward. The real Ficha has none (`AppVariant.hasDebugMenu`).
struct DebugMenu: View {
    let tools: DebugTools
    /// What to do once the time moved, since cards may have come due.
    let timeMoved: () -> Void

    var body: some View {
        Menu("Depuración") {
            Button("Cargar fichas de ejemplo") {
                attempt("No se pudieron cargar las fichas de ejemplo") {
                    try tools.loadSampleCards()
                }
            }
            Divider()
            ForEach(timeSteps, id: \.self) { step in
                Button("Avanzar \(inWords(step))") {
                    attempt("No se pudo avanzar el tiempo") {
                        try tools.moveTimeForward(by: step)
                        timeMoved()
                    }
                }
            }
            Divider()
            Text(timeShiftLine)
            // PROTOTYPE for #10, throwaway: this branch is never merged.
            Divider()
            Menu("Prototipo: foco de la cajita") {
                Text("La cajita aparece 10 s después: andá a escribir a otra app")
                ForEach(PrototypeFocusMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        FocusPrototype.shared.start(mode)
                    }
                }
            }
        }
    }

    /// How far ahead of the system's time Ficha Dev's time is, in words.
    private var timeShiftLine: String {
        tools.timeShift == .zero ? "El tiempo es el del sistema" : "Tiempo avanzado: \(inWords(tools.timeShift))"
    }

    /// Does `action`, and when it fails, says why in an alert headed by
    /// `failure`.
    private func attempt(_ failure: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            showAlert(failure, explaining: error, style: .warning, button: "Aceptar")
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

/// A span of time in words, in Spanish, like "1 día y 2 horas".
private func inWords(_ duration: Duration) -> String {
    duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide).locale(Locale(identifier: "es")))
}
