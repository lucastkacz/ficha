import FichaCore
import FichaData
import Foundation
import UserNotifications
import os

/// The card notifications' log, which iOS's answers reach on its own queue.
private nonisolated let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "notifications")

/// The appearances the engine plans, as card notifications (ADR 0010): one
/// for each appearance, at its time, with its first card and iOS's default
/// sound. A new card's notification shows it whole, with "Got it", and a due
/// card's shows its front, with its ratings. Their buttons answer the card in
/// the background, without unlocking the iPhone, and the appearance's next
/// card comes right away, without sound, until none is left. Swiping one away
/// snoozes its appearance, and so does leaving them alone, which the engine
/// notes as it plans again. Each time it plans, the notifications it planned
/// before, scheduled or shown, give way to the new plan's, so they always
/// match the cards, and each answer takes away the next cards that answers
/// before it sent. It asks Lucas whether Ficha may send notifications before
/// it plans for the first time, and plans again whenever the engine's data
/// changes, after a swipe, and when the app asks, as it comes back to the
/// foreground or Ficha Dev's time moves forward. It plans by the engine's
/// time, so with Ficha Dev's time moved forward, each notification comes at
/// the real time that matches its appearance's time. In the app
/// `make render-iphone` opens (`Rendering`), it neither asks nor plans.
final class CardNotifications: NSObject {
    /// How long "Bring the next appearance now" waits: enough to lock the
    /// iPhone and watch the notification arrive.
    private static let debugWait = Duration.seconds(5)
    /// Every identifier a plan's notifications can have: no plan has more
    /// appearances than the engine plans ahead.
    private static let plannedIdentifiers = (0..<Engine.mostUpcomingAppearances).map(identifier(ofAppearance:))
    /// How the identifier of every next card's notification starts.
    private static let nextCardPrefix = "next card "

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
        super.init()
        center.setNotificationCategories(categories())
        // Before the app finishes launching, as iOS asks, so that a button's
        // answer reaches it when iOS launches it in the background for it.
        center.delegate = self
        // iOS's alert would cover the screen in `make render-iphone`'s pictures.
        guard !Rendering.isOn else { return }
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
        planNow()
    }

    /// Clears every card notification iOS shows, the next card's too, and
    /// plans the appearances again, as the app comes back to the foreground:
    /// the notifications iOS showed meanwhile are old news once Lucas is back
    /// in the app, and a new plan reaches further ahead than the one iOS
    /// holds.
    func clearAndPlanAgain() {
        center.removeAllDeliveredNotifications()
        planAgain()
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

    /// Records Lucas's answer to a card of `appearance`, given with one of its
    /// notification's buttons, sends the notification of the appearance's
    /// next card, while it has one, and plans the appearances again. The next
    /// cards that answers before it sent go: the answer leaves them behind. It
    /// returns once iOS has the next card's notification. When it can't
    /// record the answer, the log says why.
    private func record(_ answer: ReviewLogEntry.Kind, of cardID: Int64, in appearance: NotifiedAppearance) async {
        let next: PanelCard?
        do {
            next = try engine.answerFromNotification(answer, of: cardID, in: appearance, settings: .defaults)
        } catch {
            logger.error(
                "Couldn't record an answer from a card notification: \(String(describing: error), privacy: .public)")
            return
        }
        await clearNextCards(but: next)
        if let next {
            logger.info("Recorded an answer from a card notification, and the appearance goes on")
            await send(next, in: appearance)
        } else {
            logger.info("Recorded an answer from a card notification, and the appearance is over")
        }
        // A card notification came, so Lucas was asked whether Ficha may send
        // them, in this run or an earlier one: the plan doesn't wait for this
        // run's question, which a launch in the background for the answer may
        // not have asked yet.
        planNow()
    }

    /// Takes away the notifications of next cards that iOS still shows, but
    /// `next`'s, which comes right after: one shown with its identifier, from
    /// an earlier appearance, gives way to it as it's sent.
    private func clearNextCards(but next: PanelCard?) async {
        let kept = next.map { Self.identifier(ofNextCard: $0.card.id) }
        let earlier = await center.deliveredNotifications().map(\.request.identifier).filter {
            $0.hasPrefix(Self.nextCardPrefix) && $0 != kept
        }
        center.removeDeliveredNotifications(withIdentifiers: earlier)
    }

    /// Records that Lucas swiped away one of `appearance`'s card
    /// notifications, a snooze, and plans the appearances again, which wait
    /// from now. When it can't record it, the log says why.
    private func snooze(_ appearance: NotifiedAppearance) {
        do {
            try engine.snoozeFromNotification(appearance)
        } catch {
            logger.error(
                "Couldn't record a card notification swiped away: \(String(describing: error), privacy: .public)")
            return
        }
        logger.info("Recorded a card notification swiped away, which snoozes its appearance")
        // As after an answer, a launch in the background for it may not have
        // asked yet.
        planNow()
    }

    /// Plans the appearances again now, whether or not Lucas was asked yet
    /// whether Ficha may send notifications. When it can't, the log says why.
    private func planNow() {
        do {
            try schedule()
        } catch {
            logger.error("Couldn't plan the appearances: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sends the notification of `card`, the next of `appearance`'s, right
    /// away and without sound, since Lucas is going through the appearance's
    /// card notifications, and returns once iOS has it: iOS may stop the app
    /// as soon as it's done with his answer.
    private func send(_ card: PanelCard, in appearance: NotifiedAppearance) async {
        guard let content = content(of: card, in: appearance) else {
            logger.error("The next card of an appearance is a review ahead, which no card notification shows")
            return
        }
        // With no trigger, iOS shows it at once.
        let request = UNNotificationRequest(
            identifier: Self.identifier(ofNextCard: card.card.id), content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logFailureToSchedule(error)
        }
    }

    /// Replaces every notification a plan scheduled or showed so far with
    /// those of the appearances the engine plans now, and returns them. The
    /// notifications of next cards stay, for the answers to take away. When
    /// it can't plan, no planned notification is left, so none brings cards
    /// the engine wouldn't.
    @discardableResult
    private func schedule() throws(EngineError) -> [UpcomingAppearance] {
        center.removePendingNotificationRequests(withIdentifiers: Self.plannedIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: Self.plannedIdentifiers)
        let now = engine.now
        if let broughtTo = nextAppearanceBroughtTo, broughtTo <= now {
            nextAppearanceBroughtTo = nil
        }
        let upcoming = try engine.upcomingAppearances(.defaults, bringingTheFirstTo: nextAppearanceBroughtTo)
        for (number, appearance) in upcoming.enumerated() {
            guard
                let request = request(for: appearance, identifier: Self.identifier(ofAppearance: number), after: now)
            else {
                logger.error("Planned an appearance whose first card no card notification shows")
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

    /// The identifier of the `number`th appearance's notification in a plan,
    /// counted from 0. Each pending notification needs one of its own: one
    /// scheduled with another's would take its place.
    private nonisolated static func identifier(ofAppearance number: Int) -> String {
        "appearance \(number)"
    }

    /// The identifier of the notification of a card that comes next in an
    /// appearance. No plan's notification has it, so the plan that comes
    /// right after Lucas answers doesn't take it away, and each card has its
    /// own: as the notification he answered closes, iOS takes away every
    /// notification with its identifier, even one sent meanwhile.
    private static func identifier(ofNextCard cardID: Int64) -> String {
        "\(nextCardPrefix)\(cardID)"
    }
}

extension CardNotifications: @MainActor UNUserNotificationCenterDelegate {
    /// Answers the card when Lucas presses one of its notification's buttons,
    /// and snoozes its appearance when he swipes it away. iOS keeps the app
    /// running until it returns, once iOS has the next card's notification.
    /// It runs on the main actor whatever queue iOS calls it on, since iOS's
    /// completion handler, which Swift calls as it returns, updates the app's
    /// snapshot, which UIKit allows only on the main thread. Tapping the
    /// notification itself only opens the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let button = response.actionIdentifier
        guard button != UNNotificationDefaultActionIdentifier else { return }
        guard let payload = Payload(userInfo: response.notification.request.content.userInfo) else {
            logger.error("A card notification's button, \(button, privacy: .public), came from one with no card")
            return
        }
        if button == UNNotificationDismissActionIdentifier {
            snooze(payload.appearance)
        } else if let answer = answer(ofButton: button) {
            await record(answer, of: payload.cardID, in: payload.appearance)
        } else {
            logger.error("A card notification's button, \(button, privacy: .public), didn't answer its card")
        }
    }
}

/// Logs why iOS couldn't schedule a card notification, when it couldn't: its
/// answer to the request, which comes on a queue of its own.
private nonisolated func logFailureToSchedule(_ error: (any Error)?) {
    if let error {
        logger.error("Couldn't schedule a card notification: \(String(describing: error), privacy: .public)")
    }
}

/// The card notification of an appearance, with this identifier, which iOS
/// delivers at its time, by the engine's time, which is `now`, or a second
/// after `now` when its time came already: its first card's, with iOS's
/// default sound. It carries the appearance's time as when it showed, as the
/// engine keeps it in its plan, by which the appearance log finds it. Nil
/// when no card notification shows its first card.
private func request(
    for appearance: UpcomingAppearance,
    identifier: String,
    after now: Date
) -> UNNotificationRequest? {
    guard let first = appearance.cards.first, let content = content(of: first, in: NotifiedAppearance(appearance))
    else {
        return nil
    }
    content.sound = .default
    // iOS takes only waits above 0, so one whose time came already waits a
    // second, which is our own pick.
    let wait = max(1, appearance.time.timeIntervalSince(now))
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
    return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
}

/// A card notification of `card`, in `appearance`: a new card whole, its
/// front as the title and its back below it, with "Got it", or a due card's
/// front, with its ratings, until pressing and holding it shows the back too
/// (#103). Every card notification goes in one stack on the lock screen, and
/// carries its card and its appearance for its buttons. Nil for a review
/// ahead, which no appearance brings.
private func content(of card: PanelCard, in appearance: NotifiedAppearance) -> UNMutableNotificationContent? {
    let content = UNMutableNotificationContent()
    switch card {
    case .firstView(let card, _):
        content.title = card.front
        content.body = card.back
        content.categoryIdentifier = Identifiers.firstView
    case .review(let card, _):
        content.body = card.front
        content.categoryIdentifier = Identifiers.review
    case .reviewAhead:
        return nil
    }
    content.threadIdentifier = "appearances"
    content.userInfo = Payload(cardID: card.card.id, appearance: appearance).userInfo
    return content
}

/// The card notifications' categories, each with its buttons, which answer
/// the card in the background, without unlocking the iPhone: a due card's,
/// whose buttons rate it, each named by its rating's raw value, and a new
/// card's, with "Got it". Both ask iOS to tell the app when Lucas swipes one
/// away.
private func categories() -> Set<UNNotificationCategory> {
    let review = UNNotificationCategory(
        identifier: Identifiers.review,
        actions: [
            UNNotificationAction(
                identifier: Rating.again.rawValue,
                title: String(
                    localized: "Don't know", comment: "A due card's notification's button: Lucas didn't know the card."),
                options: []),
            UNNotificationAction(
                identifier: Rating.hard.rawValue,
                title: String(
                    localized: "Sort of", comment: "A due card's notification's button: Lucas sort of knew the card."),
                options: []),
            UNNotificationAction(
                identifier: Rating.good.rawValue,
                title: String(
                    localized: "Know it", comment: "A due card's notification's button: Lucas knew the card."),
                options: []),
        ],
        intentIdentifiers: [],
        options: [.customDismissAction])
    let firstView = UNNotificationCategory(
        identifier: Identifiers.firstView,
        actions: [
            UNNotificationAction(
                identifier: Identifiers.gotIt,
                title: String(localized: "Got it", comment: "A new card's notification's button: Lucas read the card."),
                options: [])
        ],
        intentIdentifiers: [],
        options: [.customDismissAction])
    return [review, firstView]
}

/// The answer a card notification's button gives: a review with its rating,
/// for a button named by the rating's raw value, or the end of a new card's
/// first view, for "Got it". Nil for any other button.
private func answer(ofButton identifier: String) -> ReviewLogEntry.Kind? {
    if identifier == Identifiers.gotIt {
        return .firstView
    }
    return Rating(rawValue: identifier).map { .review($0) }
}

/// The identifiers of the card notifications' categories, and of "Got it".
private enum Identifiers {
    /// A due card's notification, with its ratings.
    static let review = "review"
    /// A new card's notification, with "Got it".
    static let firstView = "firstView"
    /// "Got it", which ends a new card's first view.
    static let gotIt = "gotIt"
}

/// What a card notification carries for its buttons, in its `userInfo`: its
/// card, and its appearance, by when it showed, in seconds since 1970, and
/// its cards.
private struct Payload {
    let cardID: Int64
    let appearance: NotifiedAppearance

    init(cardID: Int64, appearance: NotifiedAppearance) {
        self.cardID = cardID
        self.appearance = appearance
    }

    /// What a notification's `userInfo` carries, or nil when it doesn't carry
    /// a card of its appearance.
    init?(userInfo: [AnyHashable: Any]) {
        guard
            let cardID = userInfo["cardID"] as? Int64,
            let cardIDs = userInfo["cardIDs"] as? [Int64],
            let shownAt = userInfo["shownAt"] as? Double,
            cardIDs.contains(cardID)
        else {
            return nil
        }
        self.init(
            cardID: cardID,
            appearance: NotifiedAppearance(shownAt: Date(timeIntervalSince1970: shownAt), cardIDs: cardIDs))
    }

    /// The `userInfo` a notification carries it in.
    var userInfo: [AnyHashable: Any] {
        ["cardID": cardID, "cardIDs": appearance.cardIDs, "shownAt": appearance.shownAt.timeIntervalSince1970]
    }
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
