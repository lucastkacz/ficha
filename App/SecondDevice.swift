import AppKit
import FichaData
import FichaICloud

/// Ficha Dev's second device: another copy of the cards on the same Mac, in
/// a folder of its own, which syncs through iCloud's Development environment
/// as another device would, so Lucas watches a change made on one reach the
/// other. Ficha Dev's debug menu opens it, its Cards window and its review
/// now; it never shows up on its own, and has no capture, Settings or
/// backups of its own. Like the debug menu, it's Ficha Dev's alone, and its
/// texts are verbatim, never translated (ADR 0009).
///
/// iCloud doesn't push a change to the device that made it, and both devices
/// run on one Mac, so each fetches once the other sent what iCloud took: our
/// own stand-in for the push another Mac or iPhone would get.
final class SecondDevice {
    private let model: AppModel
    private let iCloud: CloudKitSync
    private let panel: ReviewPanel
    /// Its Cards window, once Lucas opened it.
    private var cardsWindow: CardsWindow?

    /// Opens the second device's cards with `debugTools`, on Ficha Dev's
    /// time, and starts syncing them beside `thisMac`, in its zones.
    init(debugTools: DebugTools, beside thisMac: CloudKitSync) throws {
        let model = try AppModel(engine: try debugTools.openSecondDevice())
        let iCloud = CloudKitSync(engine: model.engine, zones: thisMac.zones, device: "Second device")
        self.model = model
        self.iCloud = iCloud
        panel = ReviewPanel(model: model, mac: SystemMacSignals { model.now })
        Task {
            await iCloud.afterSending { await thisMac.fetchNow() }
            await thisMac.afterSending { await iCloud.fetchNow() }
            await iCloud.run()
        }
    }

    /// Opens its Cards window, apart from this Mac's, or brings it forward.
    func openCards() {
        let window = cardsWindow ?? CardsWindow(model: model, frameName: "Cards of the second device")
        window.subtitle = "Second device"
        window.open()
        cardsWindow = window
    }

    /// Opens its review panel with the cards a review now brings there.
    func reviewNow() {
        panel.openReviewNow()
    }

    /// Sends what waits and fetches what changed now, on this device.
    func syncNow() async {
        await iCloud.syncNow()
    }
}
