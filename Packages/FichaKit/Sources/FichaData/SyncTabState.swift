import FichaCore
import Foundation

/// Settings' Sync tab, and the menu's line while iCloud is full (ADR 0017),
/// for as long as the app runs: what the "Sync with iCloud" switch shows and
/// whether the user can turn it, what the status line under it says, as
/// `SyncStatus` reads how sync stands on the device, which cards sync, every
/// one or those with the tags the user ticks in a list under the switch
/// (ADR 0020), and why turning the switch or choosing failed, while the tab
/// says so. The switch is on by default when
/// the Mac has an iCloud account, and shows off without one, since nothing
/// syncs then. The app reads it again whenever the database changes, as when
/// the switch, the account or a full iCloud do, and as time passes, for when
/// the device last synced, which changes without telling.
public struct SyncTabState: Sendable {
    /// What the status line under the switch says.
    public enum Status: Sendable, Equatable {
        /// Sync is on, and the device last synced then, or never yet.
        case on(lastSynced: Date?)
        /// iCloud is full: what changes waits until the user frees up space.
        case iCloudFull
        /// The switch is off. Turning it on does what `turningOn` says, as
        /// why sync went off decides, or only syncs again, as after the user
        /// turned it off; and it sends `sending` bytes of images and sounds,
        /// which the line says from 100 MB on, or nil under that.
        case off(turningOn: TurningOn?, sending: Int64?)
        /// The Mac has no iCloud account: nothing syncs, whatever the switch
        /// was left at.
        case noAccount
        /// The app hasn't heard yet whether the Mac has an iCloud account,
        /// which it asks iCloud as it launches.
        case checkingAccount
        /// How sync stands couldn't be read, for this reason.
        case unreadable(EngineError)
    }

    /// What turning the switch on does beyond syncing again, which the status
    /// line says while it's off.
    public enum TurningOn: Sendable, Equatable {
        /// It sends the device's cards that sync again, every one or only
        /// those with a chosen tag, as `onlyChosenTags` says, since the user
        /// deleted Ficha's data in iCloud's settings.
        case sendsCardsAgain(onlyChosenTags: Bool)
        /// It replaces the cards iCloud holds with the device's, which the
        /// other devices then take in place of theirs, since the user
        /// restored a copy.
        case replacesICloudsCopy
        /// It sends the device's cards that sync for the first time, every
        /// one or only those with a chosen tag, as `onlyChosenTags` says: the
        /// device held cards and had never synced when Ficha came to choose
        /// which cards sync, so it left sync off until the user says so.
        case sendsCardsForTheFirstTime(onlyChosenTags: Bool)
    }

    /// Why turning the switch, or choosing which cards sync, failed, which
    /// the tab says until the user closes it.
    public struct Failure: Sendable, Equatable {
        /// What the user did that failed.
        public enum Action: Sendable, Equatable {
            /// Turning the switch on.
            case turningOn
            /// Turning the switch off.
            case turningOff
            /// Choosing which cards sync: every card, those with chosen
            /// tags, or a tag.
            case choosing
        }

        public let action: Action
        public let error: EngineError
    }

    /// What the status line says.
    public private(set) var status: Status
    /// Whether the switch shows on: as the user left it, while the Mac has
    /// an iCloud account or the app hasn't heard yet, and off without one.
    public private(set) var switchIsOn: Bool
    /// Whether only the cards with a tag the user chose sync, rather than
    /// every card, as the choice under the switch shows it.
    public private(set) var onlyChosenTags: Bool
    /// The tags the user can choose to sync, as a tree, as the list under
    /// the choice shows them while only the cards with a chosen tag sync, and
    /// none otherwise: as `Engine.tagsToChooseFrom()` says.
    public private(set) var tags: [TagToChoose]
    /// Why turning the switch, or choosing, failed, while the tab says so.
    public private(set) var failure: Failure?
    private let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        status = .checkingAccount
        switchIsOn = false
        onlyChosenTags = false
        tags = []
        read()
    }

    /// Whether the user can turn the switch: not without an iCloud account,
    /// which the switch can't make sync, nor when how sync stands couldn't be
    /// read.
    public var canTurnSwitch: Bool {
        switch status {
        case .on, .iCloudFull, .off, .checkingAccount: true
        case .noAccount, .unreadable: false
        }
    }

    /// Whether the user can choose which cards sync: as they can turn the
    /// switch.
    public var canChoose: Bool {
        canTurnSwitch
    }

    /// Whether the menu says iCloud is full, with a line that opens the tab.
    public var saysICloudIsFull: Bool {
        status == .iCloudFull
    }

    /// Reads again how sync stands on the device: while the switch is off,
    /// what the images and sounds turning it on sends weigh too, of the
    /// cards that sync; and which cards sync, with the tags to choose from
    /// while only those with a chosen tag do.
    public mutating func read() {
        do throws(EngineError) {
            onlyChosenTags = try engine.syncsOnlyChosenTags()
            tags = onlyChosenTags ? try engine.tagsToChooseFrom() : []
            let stored = try engine.syncStatus()
            switch (stored.hasICloudAccount, stored.offBecause) {
            case (nil, _):
                status = .checkingAccount
            case (false?, _):
                status = .noAccount
            case (true?, let reason?):
                status = .off(
                    turningOn: Self.turningOn(after: reason, onlyChosenTags: onlyChosenTags),
                    sending: weightWorthSaying(try engine.weightICloudLacks()))
            case (true?, nil):
                status = stored.iCloudIsFull ? .iCloudFull : .on(lastSynced: stored.lastSynced)
            }
            switchIsOn = stored.isOn && canTurnSwitch
        } catch {
            status = .unreadable(error)
            switchIsOn = false
            tags = []
        }
    }

    /// What turning the switch on does beyond syncing again, after sync went
    /// off for `reason`, with only the cards with a chosen tag syncing or
    /// not, as `onlyChosenTags` says, or nil when it only syncs again, as
    /// after the user turned it off: the off switch says all there is then.
    private static func turningOn(after reason: SyncOffReason, onlyChosenTags: Bool) -> TurningOn? {
        switch reason {
        case .user: nil
        case .purge: .sendsCardsAgain(onlyChosenTags: onlyChosenTags)
        case .restore: .replacesICloudsCopy
        case .firstSync: .sendsCardsForTheFirstTime(onlyChosenTags: onlyChosenTags)
        }
    }

    /// Turns sync on or off, as the user turns the switch, while they can,
    /// or keeps why it couldn't. The app's sync follows it.
    public mutating func turnSync(on: Bool) {
        guard canTurnSwitch else { return }
        let engine = engine
        change(on ? .turningOn : .turningOff) { () throws(EngineError) in
            if on {
                try engine.turnSyncOn()
            } else {
                try engine.turnSyncOff()
            }
        }
    }

    /// Has only the cards with a tag the user chose sync, or every card, as
    /// `only` says, as the user picks under the switch, while they can, or
    /// keeps why it couldn't. Choosing never deletes: the cards that stop
    /// syncing leave iCloud, kept on every device.
    public mutating func syncOnlyChosenTags(_ only: Bool) {
        guard canChoose else { return }
        let engine = engine
        change(.choosing) { () throws(EngineError) in try engine.syncOnlyChosenTags(only) }
    }

    /// Chooses the tag named `tag` to sync, or stops choosing it, as
    /// `chosen` says, as the user ticks or unticks it in the list, while they
    /// can, or keeps why it couldn't. A tag inside a chosen tag syncs with it,
    /// and its checkbox changes nothing meanwhile.
    public mutating func choose(_ tag: String, _ chosen: Bool) {
        guard canChoose, Self.tag(named: tag, in: tags)?.canChoose != false else { return }
        let engine = engine
        change(.choosing) { () throws(EngineError) in try engine.chooseToSync(tag, chosen) }
    }

    /// The tag named `name` in `trees`, at any depth, or nil when they don't
    /// list it.
    private static func tag(named name: String, in trees: [TagToChoose]) -> TagToChoose? {
        for tree in trees {
            if tree.name == name {
                return tree
            }
            if let tag = tag(named: name, in: tree.children) {
                return tag
            }
        }
        return nil
    }

    /// Makes the change `make` makes, for `action`, or keeps why it failed,
    /// and reads again how sync stands.
    private mutating func change(_ action: Failure.Action, _ make: () throws(EngineError) -> Void) {
        do throws(EngineError) {
            try make()
        } catch {
            failure = Failure(action: action, error: error)
        }
        read()
    }

    /// Clears why turning the switch failed, once the tab said so and the
    /// user closed it.
    public mutating func dismissFailure() {
        failure = nil
    }
}

extension Engine {
    /// Settings' Sync tab's state, and the menu's line while iCloud is full,
    /// as sync stands on the device now.
    public func openSyncTab() -> SyncTabState {
        SyncTabState(engine: self)
    }
}
