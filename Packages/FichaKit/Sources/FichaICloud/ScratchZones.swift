import CloudKit
import FichaData
import Foundation

/// The zones an agent's scratch run of Ficha Dev synced in, in the user's
/// private database (`ICloudZones.scratch(_:)`), which the agent deletes
/// once it's done, without the app: Ficha Dev's binary does it when run with
/// `--delete-scratch-zones`, as docs/development.md says, since only the
/// app's process holds iCloud's entitlements. Like `CloudKitSync`, it's
/// never used in a process without them.
public enum ScratchZones {
    /// Deletes the zones of the scratch run `name`, in the environment the
    /// app's entitlements name, and returns their names, sorted: never
    /// another run's, nor Ficha's own, which no scratch run's name, written
    /// with letters, digits, `-` and `_` alone, can spell (`ScratchName`).
    public static func delete(ofScratch name: ScratchName) async throws(ScratchZonesError) -> [String] {
        let zones = ICloudZones.scratch(name)
        let database = CKContainer(identifier: CloudKitSync.containerIdentifier).privateCloudDatabase
        do {
            let ids = try await database.allRecordZones().map(\.zoneID)
                .filter { zones.contains(ICloudZone(name: $0.zoneName)) }
            guard !ids.isEmpty else {
                return []
            }
            let (_, deletions) = try await database.modifyRecordZones(saving: [], deleting: ids)
            for result in deletions.values {
                try result.get()
            }
            return ids.map(\.zoneName).sorted()
        } catch {
            throw .iCloudFailed(error.localizedDescription)
        }
    }
}

/// Why a scratch run's zones couldn't be deleted. Only agents see it, so it's
/// in English and verbatim, as Ficha Dev's debug tools are (ADR 0009).
public enum ScratchZonesError: Error, LocalizedError {
    /// iCloud didn't list the zones or delete them, saying this.
    case iCloudFailed(String)

    public var errorDescription: String? {
        switch self {
        case .iCloudFailed(let reason):
            """
            iCloud didn't delete the scratch run's zones: \(reason) Check that this Mac is online and signed into \
            iCloud, and run it again.
            """
        }
    }
}
