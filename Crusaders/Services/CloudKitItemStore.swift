import CloudKit
import CrusadersKit

/// iCloud setup shared by the CloudKit services.
enum CloudConfig {
    static let containerID = "iCloud.com.randomedp.Crusaders"
    static var container: CKContainer { CKContainer(identifier: containerID) }
}

/// Saves the creator's item edits to the CloudKit public database, so every player gets them.
///
/// Record type `ItemOverride`, one record per edited item, named `item-<id>`:
/// - `itemID` (String): the item's id
/// - `payload` (String): the full edited item as JSON
///
/// CloudKit Dashboard setup is described in README.md (Library items).
struct CloudKitItemOverrideStore: ItemOverrideStore {
    static let recordType = "ItemOverride"

    private var database: CKDatabase { CloudConfig.container.publicCloudDatabase }

    func loadOverrides() async throws -> [EquipmentItem] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var items: [EquipmentItem] = []
        var page = try await database.records(matching: query, desiredKeys: ["payload"])
        while true {
            for (_, result) in page.matchResults {
                if let record = try? result.get(), let item = Self.decode(record) {
                    items.append(item)
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["payload"])
        }
        return items
    }

    func save(_ item: EquipmentItem) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: item.id))
        record["itemID"] = item.id as CKRecordValue
        record["payload"] = try Self.encode(item) as CKRecordValue
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[record.recordID] {
            _ = try saveResult.get()
        }
    }

    func remove(itemID: String) async throws {
        let id = Self.recordID(for: itemID)
        do {
            let result = try await database.modifyRecords(saving: [], deleting: [id])
            if let deleteResult = result.deleteResults[id] {
                try deleteResult.get()
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Nothing saved for this item: it's already the built-in version.
        }
    }

    static func recordID(for itemID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "item-\(itemID)")
    }

    static func encode(_ item: EquipmentItem) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(item), as: UTF8.self)
    }

    static func decode(_ record: CKRecord) -> EquipmentItem? {
        guard let payload = record["payload"] as? String else { return nil }
        return try? JSONDecoder().decode(EquipmentItem.self, from: Data(payload.utf8))
    }
}

/// Checks whether the current iCloud user is on the creator list.
///
/// Record type `Creator` in the public database, with a `userID` (String, queryable) field holding
/// the creator's iCloud user record name. Only the CloudKit Dashboard can add these records.
struct CloudKitCreatorAccess: CreatorAccess {
    static let recordType = "Creator"

    func currentStatus() async -> CreatorStatus {
        let container = CloudConfig.container
        do {
            guard try await container.accountStatus() == .available else {
                return CreatorStatus(isCreator: false, problem: "Sign in to iCloud in Settings to use creator tools.")
            }
            let userID = try await container.userRecordID().recordName
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "userID == %@", userID))
            let page = try await container.publicCloudDatabase.records(matching: query, desiredKeys: ["userID"], resultsLimit: 1)
            let found = page.matchResults.contains { (try? $0.1.get()) != nil }
            return CreatorStatus(isCreator: found, userID: userID)
        } catch {
            return CreatorStatus(isCreator: false, problem: "Couldn't reach iCloud to check creator access.")
        }
    }
}
