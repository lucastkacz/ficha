import FichaData
import WidgetKit
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "widget")

/// Asks WidgetKit to reload the widget's timeline (#171) when what it shows
/// changes: as the app launches, since the cards may have changed while it
/// didn't run, and then after each change to the database, whichever process
/// made it, the CLI's included, when the engine says the widget shows
/// something else from then on (`WidgetReloading`), since WidgetKit budgets
/// reloads. Cards that come due as time passes need none: the timeline
/// already has an entry at each time. This is WidgetKit's documented way
/// ("Keeping a widget up to date"), and the widget's extension, which runs
/// only while WidgetKit asks it for a timeline, hears nothing on its own.
final class WidgetReloads {
    private let model: AppModel
    private var reloading = WidgetReloading()

    init(model: AppModel) {
        self.model = model
    }

    /// Reloads the widget now, and then whenever the database changes and
    /// what it shows changes with it.
    func start() {
        // Listening before reloading, so no change falls in between.
        let changes = model.changes()
        reloadIfItChanged(after: "the app launched")
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                reloadIfItChanged(after: "a change to the database")
            }
        }
    }

    /// Reloads the widget once Ficha Dev's debug menu moved its time forward:
    /// the widget's timeline runs on the system's time, which Ficha Dev's
    /// then runs further ahead of, so the times of its entries are off.
    func timeMoved() {
        reloading = WidgetReloading()
        reloadIfItChanged(after: "Ficha Dev's time moved forward")
    }

    /// Asks WidgetKit to reload the widget when what it shows from now on
    /// changed since the last reload, and logs either way, so a run with the
    /// widget reads from the log alone.
    private func reloadIfItChanged(after cause: String) {
        let timeline: WidgetTimeline
        do {
            timeline = try model.engine.widgetTimeline()
        } catch {
            logger.error(
                """
                Couldn't work out what the widget shows after \(cause, privacy: .public), so it isn't reloaded: \
                \(String(describing: error), privacy: .public)
                """)
            return
        }
        guard reloading.reloads(for: timeline) else {
            logger.info("The widget shows the same after \(cause, privacy: .public): no reload")
            return
        }
        logger.info("Asked WidgetKit to reload the widget's timeline after \(cause, privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
