import CloudKit
import CrusadersKit

/// Saves the creator's creatures to the CloudKit public database, so every player gets them.
///
/// Record type `CreatureEntry`, one record per creature the creator added or changed, named `creature-<id>`:
/// - `creatureID` (String): the creature's id (SRD ids like `goblin`, or `custom-<uuid>` for new ones)
/// - `payload` (String): the full creature as JSON
///
/// Removing the record puts an SRD creature back to its built-in stats, or deletes a creature the creator added.
/// CloudKit Dashboard setup is described in README.md (Library creatures).
struct CloudKitCreatureStore: CreatureStore {
    static let recordType = "CreatureEntry"

    private var database: CKDatabase { CloudConfig.container.publicCloudDatabase }

    func loadCreatures() async throws -> [Creature] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var creatures: [Creature] = []
        var page = try await database.records(matching: query, desiredKeys: ["payload"])
        while true {
            for (_, result) in page.matchResults {
                if let record = try? result.get(), let creature = Self.decode(record) {
                    creatures.append(creature)
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["payload"])
        }
        return creatures
    }

    func save(_ creature: Creature) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: creature.id))
        record["creatureID"] = creature.id as CKRecordValue
        record["payload"] = try Self.encode(creature) as CKRecordValue
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[record.recordID] {
            _ = try saveResult.get()
        }
    }

    func remove(creatureID: String) async throws {
        let id = Self.recordID(for: creatureID)
        do {
            let result = try await database.modifyRecords(saving: [], deleting: [id])
            if let deleteResult = result.deleteResults[id] {
                try deleteResult.get()
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Nothing saved for this creature.
        }
    }

    static func recordID(for creatureID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "creature-\(creatureID)")
    }

    static func encode(_ creature: Creature) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(creature), as: UTF8.self)
    }

    static func decode(_ record: CKRecord) -> Creature? {
        guard let payload = record["payload"] as? String else { return nil }
        return try? JSONDecoder().decode(Creature.self, from: Data(payload.utf8))
    }
}
