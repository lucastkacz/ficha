import FichaData
import Observation
import WidgetKit

/// Keeps the widget (#171) up to date, in WidgetKit's documented way
/// ("Keeping a widget up to date"): the widget's extension runs only while
/// WidgetKit asks it for a timeline, and hears nothing on its own. So the app
/// hands the widget what it needs of this Mac's settings, and asks WidgetKit
/// to reload its timeline when what it shows changes, as `WidgetReloading`
/// decides when to look: as the app launches, since the cards may have
/// changed while it didn't run, once a burst of changes to the database ends,
/// whichever process made them, the CLI's and sync's included, once the
/// review panel closes, which holds the looks back while it's open, when
/// this Mac's settings change, and once Ficha Dev's debug menu moved its
/// time. Cards that come due as time passes need none: the timeline already
/// has an entry at each time. It works the timeline out away from the main
/// thread, which a large deck would hold up.
final class WidgetReloads {
    private let model: AppModel
    private var reloading = WidgetReloading()
    /// What the app handed the widget of this Mac's settings last.
    private var handedOver: WidgetSettings?
    /// The last look at what the widget shows, which the next one waits for,
    /// so they note their reloads in order.
    private var looking: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Hands the widget this Mac's settings, and reloads it now, and then
    /// whenever what it shows changes.
    func start() {
        // Listening before looking, so no change falls in between.
        let changes = model.changes()
        handOverSettings()
        look(after: "the app launched")
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                databaseChanged()
            }
        }
    }

    /// Holds the looks back while the review panel is open.
    func panelOpened() {
        reloading.panelOpened()
    }

    /// Looks at what the widget shows once the review panel closed, when the
    /// database changed meanwhile.
    func panelClosed() {
        guard reloading.panelClosed() else { return }
        look(after: "the review panel closed")
    }

    /// Looks at what the widget shows once Ficha Dev's debug menu moved its
    /// time forward: the widget's timeline runs on the system's time, which
    /// Ficha Dev's then runs further ahead of.
    func timeMoved() {
        look(after: "Ficha Dev's time moved forward")
    }

    /// Looks at what the widget shows once the changes to the database stop
    /// for a while, or once the review panel closes.
    private func databaseChanged() {
        guard let lookAt = reloading.databaseChanged(at: model.now) else {
            widgetLogger.debug("The review panel holds back the widget's reload after a change to the database")
            return
        }
        Task { [weak self] in
            do {
                try await Task.sleep(for: WidgetReloading.quietPeriod)
            } catch {
                return
            }
            guard let self, reloading.looks(at: lookAt) else { return }
            look(after: "changes to the database")
        }
    }

    /// Hands the widget what it needs of this Mac's settings, now and then
    /// whenever they change, looking at what it shows when that changed.
    private func handOverSettings() {
        let settings = withObservationTracking {
            WidgetSettings(model.settings)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.settingsChanged() }
        }
        handedOver = settings
        WidgetHandover.handOver(settings)
    }

    private func settingsChanged() {
        let before = handedOver
        handOverSettings()
        guard handedOver != before else { return }
        look(after: "a change to this Mac's settings")
    }

    /// Works out what the widget shows, away from the main thread, and asks
    /// WidgetKit to reload it when that changed since the last reload. It
    /// logs either way, so a run with the widget reads from the log alone.
    private func look(after cause: String) {
        let engine = model.engine
        let settings = WidgetSettings(model.settings)
        let shift = model.debugTools?.timeShift ?? .zero
        let previous = looking
        looking = Task { [weak self] in
            await previous?.value
            let timeline = await Self.timeline(of: engine, with: settings, engineAheadBy: shift)
            self?.reloadIfItChanged(to: timeline, after: cause)
        }
    }

    @concurrent
    private nonisolated static func timeline(
        of engine: Engine, with settings: WidgetSettings, engineAheadBy shift: Duration
    ) async -> Result<WidgetTimeline, EngineError> {
        Result { () throws(EngineError) in try engine.widgetTimeline(settings, engineAheadBy: shift) }
    }

    private func reloadIfItChanged(to timeline: Result<WidgetTimeline, EngineError>, after cause: String) {
        switch timeline {
        case .failure(let error):
            widgetLogger.error(
                """
                Couldn't work out what the widget shows after \(cause, privacy: .public), so it isn't reloaded: \
                \(String(describing: error), privacy: .public)
                """)
        case .success(let timeline):
            guard reloading.needsReload(for: timeline) else {
                widgetLogger.info("The widget shows the same after \(cause, privacy: .public): no reload")
                return
            }
            reloading.recordReload(of: timeline)
            widgetLogger.info("Asked WidgetKit to reload the widget's timeline after \(cause, privacy: .public)")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
