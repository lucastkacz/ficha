import FichaCore
import Foundation

/// Settings' Sync tab, and the menu's line while iCloud is full (ADR 0017),
/// for as long as the app runs: what the "Sync with iCloud" switch shows and
/// whether the user can turn it, what the status line under it says, as
/// `SyncStatus` reads how sync stands on the device, and why turning the
/// switch failed, while the tab says so. The switch is on by default when
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
        /// The switch is off, for this reason, which says what turning it on
        /// does. Turning it on sends `sending` bytes of images and sounds,
        /// which the line says from 100 MB on, or nil under that.
        case off(SyncOffReason, sending: Int64?)
        /// The Mac has no iCloud account: nothing syncs, whatever the switch
        /// was left at.
        case noAccount
        /// The app hasn't heard yet whether the Mac has an iCloud account,
        /// which it asks iCloud as it launches.
        case checkingAccount
        /// How sync stands couldn't be read, for this reason.
        case unreadable(EngineError)
    }

    /// Why turning the switch failed, which the tab says until the user
    /// closes it.
    public struct Failure: Sendable, Equatable {
        /// Whether the user turned it on, or off.
        public let turningOn: Bool
        public let error: EngineError
    }

    /// What the status line says.
    public private(set) var status: Status
    /// Whether the switch shows on: as the user left it, while the Mac has
    /// an iCloud account or the app hasn't heard yet, and off without one.
    public private(set) var switchIsOn: Bool
    /// Why turning the switch failed, while the tab says so.
    public private(set) var failure: Failure?
    private let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        status = .checkingAccount
        switchIsOn = false
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

    /// Whether the menu says iCloud is full, with a line that opens the tab.
    public var saysICloudIsFull: Bool {
        status == .iCloudFull
    }

    /// Reads again how sync stands on the device: while the switch is off,
    /// what the images and sounds turning it on sends weigh too.
    public mutating func read() {
        do throws(EngineError) {
            let stored = try engine.syncStatus()
            switch (stored.hasICloudAccount, stored.offBecause) {
            case (nil, _):
                status = .checkingAccount
            case (false?, _):
                status = .noAccount
            case (true?, let reason?):
                status = .off(reason, sending: heavyUpload(try engine.weightICloudLacks()))
            case (true?, nil):
                status = stored.iCloudIsFull ? .iCloudFull : .on(lastSynced: stored.lastSynced)
            }
            switchIsOn = stored.isOn && canTurnSwitch
        } catch {
            status = .unreadable(error)
            switchIsOn = false
        }
    }

    /// Turns sync on or off, as the user turns the switch, while they can,
    /// or keeps why it couldn't. The app's sync follows it.
    public mutating func turnSync(on: Bool) {
        guard canTurnSwitch else { return }
        do throws(EngineError) {
            if on {
                try engine.turnSyncOn()
            } else {
                try engine.turnSyncOff()
            }
        } catch {
            failure = Failure(turningOn: on, error: error)
        }
        read()
    }

    /// Clears why turning the switch failed, once the tab said so and the
    /// user closed it.
    public mutating func dismissFailure() {
        failure = nil
    }
}

extension SyncStatus {
    /// Whether what changes goes up to the user's iCloud: the switch is on
    /// and the device is signed into iCloud, as far as the app heard.
    var sendsToICloud: Bool {
        isOn && hasICloudAccount == true
    }
}

/// `bytes` of images and sounds going up to the user's iCloud, when they
/// weigh enough for Ficha to say so, 100 MB or more, or nil under that: the
/// Sync tab's line while sync is off, and the Import sheet's while it's on
/// (#317's decision of 2026-10-28, our own: Anki never warns). 100 MB is
/// 100,000,000 bytes, as Finder writes sizes.
func heavyUpload(_ bytes: Int64) -> Int64? {
    bytes >= 100_000_000 ? bytes : nil
}

extension Engine {
    /// Settings' Sync tab's state, and the menu's line while iCloud is full,
    /// as sync stands on the device now.
    public func openSyncTab() -> SyncTabState {
        SyncTabState(engine: self)
    }
}
