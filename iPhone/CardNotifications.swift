import FichaCore
import FichaData
import Foundation
import UserNotifications
import os

/// The card notifications' log, which iOS's answers reach on its own queue.
private nonisolated let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "notifications")

/// The appearances the engine plans, as card notifications (ADR 0010): one
/// for each appearance, at its time, with the front of its first card and
/// iOS's default sound, carrying the appearance's card IDs under `cardIDs`.
/// Each time it plans, the notifications it scheduled or showed before give
/// way to the new plan's, so they always match the cards. It asks Lucas
/// whether Ficha may send notifications before it plans for the first time,
/// and plans again whenever the engine's data changes, and when the app asks,
/// as it comes back to the foreground.
final class CardNotifications {
    /// How long "Bring the next appearance now" waits: enough to lock the
    /// iPhone and watch the notification arrive.
    private static let debugWait = Duration.seconds(5)

    private let engine: Engine
    private let center = UNUserNotificationCenter.current()
    /// Whether Lucas was asked whether Ficha may send notifications, which
    /// comes before the first plan.
    private var askedForPermission = false
    /// When "Bring the next appearance now" brings the next planned
    /// appearance's notification, by the engine's time. The plans made before
    /// then keep it.
    private var nextAppearanceBroughtTo: Date?

    init(engine: Engine) {
        self.engine = engine
        let center = center
        let changes = engine.changes()
        Task { [weak self] in
            await askForPermission(in: center)
            self?.askedForPermission = true
            self?.planAgain()
            for await _ in changes {
                guard let self else { return }
                planAgain()
            }
        }
    }

    /// Plans the appearances again, by the default settings until the iPhone
    /// has a Settings tab (#107), once Lucas was asked whether Ficha may send
    /// notifications. When it can't plan, the log says why.
    func planAgain() {
        guard askedForPermission else { return }
        do {
            try schedule()
        } catch {
            logger.error("Couldn't plan the appearances: \(String(describing: error), privacy: .public)")
        }
    }

    /// Ficha Dev's "Bring the next appearance now": the next planned
    /// appearance's notification comes a few seconds from now, instead of at
    /// its time, for Lucas to lock the iPhone and watch it arrive. It returns
    /// what it did, or why it couldn't, in English, as Ficha Dev's debug tools
    /// say it.
    func bringNextAppearanceNow() -> String {
        guard askedForPermission else {
            return "Ficha Dev is still asking whether it may send notifications."
        }
        nextAppearanceBroughtTo = engine.now.adding(Self.debugWait)
        do {
            guard !(try schedule()).isEmpty else {
                return "No appearance is planned: no card is due, and no new card can come in."
            }
            let seconds = Self.debugWait.components.seconds
            return "The next appearance arrives in \(seconds) seconds: lock the iPhone to watch it."
        } catch {
            logger.error("Couldn't bring the next appearance now: \(String(describing: error), privacy: .public)")
            return "Couldn't plan the appearances: \(error.localizedDescription)"
        }
    }

    /// Replaces every notification scheduled or shown so far with those of
    /// the appearances the engine plans now, and returns them. When it can't
    /// plan, none is left, so no notification brings cards the engine
    /// wouldn't.
    @discardableResult
    private func schedule() throws(EngineError) -> [UpcomingAppearance] {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        let upcoming = try engine.upcomingAppearances(.defaults)
        let now = engine.now
        if let broughtTo = nextAppearanceBroughtTo, broughtTo <= now {
            nextAppearanceBroughtTo = nil
        }
        for (number, appearance) in upcoming.enumerated() {
            let time = number == 0 ? nextAppearanceBroughtTo ?? appearance.time : appearance.time
            guard let request = request(for: appearance, number: number, in: time.timeIntervalSince(now)) else {
                logger.error("Planned an appearance with no cards, which has no notification")
                continue
            }
            // Without waiting for iOS's answers, so the whole plan reaches it
            // even when the app goes to the background right away, as when
            // Lucas locks the iPhone.
            center.add(request, withCompletionHandler: logFailureToSchedule)
        }
        logger.info("Planned \(upcoming.count) appearances")
        return upcoming
    }
}

/// Logs why iOS couldn't schedule a card notification, when it couldn't: its
/// answer to the request, which comes on a queue of its own.
private nonisolated func logFailureToSchedule(_ error: (any Error)?) {
    if let error {
        logger.error("Couldn't schedule an appearance: \(String(describing: error), privacy: .public)")
    }
}

/// The card notification of an appearance, the `number`th the engine plans,
/// counted from 0, which iOS delivers `wait` seconds from now, or a second
/// from now when its time came already: the front of its first card, with
/// iOS's default sound and the appearance's card IDs. Every appearance's
/// notification goes in one stack on the lock screen. Nil for an appearance
/// with no cards.
private func request(for appearance: UpcomingAppearance, number: Int, in wait: TimeInterval)
    -> UNNotificationRequest?
{
    guard let first = appearance.cards.first else {
        return nil
    }
    let content = UNMutableNotificationContent()
    content.body = first.card.front
    content.sound = .default
    content.threadIdentifier = "appearances"
    content.userInfo = ["cardIDs": appearance.cards.map(\.card.id)]
    // iOS takes only waits above 0, so one whose time came already waits a
    // second, which is our own pick.
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, wait), repeats: false)
    // Each pending notification needs an identifier of its own: one scheduled
    // with another's would take its place.
    return UNNotificationRequest(identifier: "appearance \(number)", content: content, trigger: trigger)
}

/// Asks Lucas whether Ficha may send notifications, with their sounds. iOS
/// asks him only the first time: after that, it answers with what he said,
/// which he changes in iOS's Settings.
private func askForPermission(in center: UNUserNotificationCenter) async {
    do {
        let allowed = try await center.requestAuthorization(options: [.alert, .sound])
        logger.info("Notifications are \(allowed ? "allowed" : "not allowed", privacy: .public)")
    } catch {
        logger.error(
            "Couldn't ask for permission to send notifications: \(String(describing: error), privacy: .public)")
    }
}
