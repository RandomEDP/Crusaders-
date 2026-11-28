import CloudKit
import CrusadersKit

/// The shared campaign list in the CloudKit public database, so players on other phones can join by code.
///
/// Record type `Campaign`, one per campaign, named `campaign-<code>`:
/// - `name` (String), `joinCode` (String), `dmID` (String), `dmName` (String)
///
/// Record type `CampaignPlayer`, one per player per campaign, named `player-<code>-<memberID>`.
/// Each player creates their own record, so nobody needs write access to anyone else's:
/// - `joinCode` (String, queryable), `memberID` (String), `name` (String),
///   `characterID`, `characterName`, `characterSummary` (String): the character they joined with
///
/// Record type `InventoryChange`, one per item added or removed, named `inventory-<uuid>`, written by whoever made it:
/// - `joinCode` (String, queryable), `playerID`, `itemID`, `itemName`, `authorID` (String), `delta` (Int64),
///   `changedAt` (Date). The app ignores changes the rules don't allow (see `Campaign.allows`).
///
/// CloudKit Dashboard setup is described in README.md (Campaigns).
struct CloudKitCampaignDirectory: CampaignDirectory {
    static let campaignType = "Campaign"
    static let playerType = "CampaignPlayer"
    static let inventoryType = "InventoryChange"

    private var database: CKDatabase { CloudConfig.container.publicCloudDatabase }

    func publish(_ campaign: Campaign) async throws {
        let record = Self.record(for: campaign)
        // `.ifServerRecordUnchanged` refuses to overwrite a record that already exists,
        // which is how we find out the code is taken.
        do {
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            if let saveResult = result.saveResults[record.recordID] {
                _ = try saveResult.get()
            }
        } catch let error as CKError where Self.isAlreadyExists(error) {
            throw CampaignError.codeTaken
        }
    }

    func campaign(forJoinCode code: String) async throws -> Campaign? {
        let record: CKRecord
        do {
            record = try await database.record(for: Self.campaignID(code: code))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard var campaign = Self.campaign(from: record) else { return nil }
        for player in try await players(code: code) {
            campaign.addPlayer(player)
        }
        for change in try await records(type: Self.inventoryType, code: code).compactMap(Self.inventoryChange(from:)) {
            campaign.apply(change)
        }
        return campaign
    }

    func record(_ change: InventoryChange, inCampaignWithCode code: String) async throws -> Campaign {
        let record = Self.inventoryRecord(change, code: code)
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[record.recordID] {
            _ = try saveResult.get()
        }
        guard var updated = try await campaign(forJoinCode: code) else { throw CampaignError.campaignNotFound }
        // A query can lag just behind a save, so make sure our own change is in.
        updated.apply(change)
        return updated
    }

    private func records(type: String, code: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(format: "joinCode == %@", code))
        var records: [CKRecord] = []
        var page = try await database.records(matching: query)
        while true {
            records += page.matchResults.compactMap { try? $0.1.get() }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor)
        }
        return records
    }

    func addPlayer(_ player: CampaignMember, toCampaignWithCode code: String) async throws -> Campaign {
        guard try await campaign(forJoinCode: code) != nil else { throw CampaignError.campaignNotFound }
        let record = Self.playerRecord(player, code: code)
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[record.recordID] {
            _ = try saveResult.get()
        }
        guard let updated = try await campaign(forJoinCode: code) else { throw CampaignError.campaignNotFound }
        return updated
    }

    private func players(code: String) async throws -> [CampaignMember] {
        // Sorted here rather than in the query, so no extra index is needed.
        try await records(type: Self.playerType, code: code)
            .sorted { ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture) }
            .compactMap(Self.player(from:))
    }

    private static func isAlreadyExists(_ error: CKError) -> Bool {
        if error.code == .serverRecordChanged { return true }
        if error.code == .partialFailure, let partial = error.partialErrorsByItemID?.values {
            return partial.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }

    // MARK: - Record mapping (tested in AppModelTests)

    static func campaignID(code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "campaign-\(code)")
    }

    static func record(for campaign: Campaign) -> CKRecord {
        let record = CKRecord(recordType: campaignType, recordID: campaignID(code: campaign.joinCode))
        record["name"] = campaign.name as CKRecordValue
        record["joinCode"] = campaign.joinCode as CKRecordValue
        record["dmID"] = campaign.dungeonMaster.id as CKRecordValue
        record["dmName"] = campaign.dungeonMaster.name as CKRecordValue
        return record
    }

    static func campaign(from record: CKRecord) -> Campaign? {
        guard let name = record["name"] as? String,
              let code = record["joinCode"] as? String,
              let dmID = record["dmID"] as? String,
              let dmName = record["dmName"] as? String else { return nil }
        return Campaign(name: name, joinCode: code, dungeonMaster: CampaignMember(id: dmID, name: dmName))
    }

    static func playerRecordID(code: String, memberID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "player-\(code)-\(memberID)")
    }

    static func playerRecord(_ player: CampaignMember, code: String) -> CKRecord {
        let id = playerRecordID(code: code, memberID: player.id)
        let record = CKRecord(recordType: playerType, recordID: id)
        record["joinCode"] = code as CKRecordValue
        record["memberID"] = player.id as CKRecordValue
        record["name"] = player.name as CKRecordValue
        if let character = player.character {
            record["characterID"] = character.id.uuidString as CKRecordValue
            record["characterName"] = character.name as CKRecordValue
            record["characterSummary"] = character.summary as CKRecordValue
        }
        return record
    }

    static func player(from record: CKRecord) -> CampaignMember? {
        guard let id = record["memberID"] as? String, let name = record["name"] as? String else { return nil }
        var character: CampaignCharacter?
        if let characterID = (record["characterID"] as? String).flatMap(UUID.init(uuidString:)),
           let characterName = record["characterName"] as? String {
            character = CampaignCharacter(id: characterID, name: characterName,
                                          summary: record["characterSummary"] as? String ?? "")
        }
        return CampaignMember(id: id, name: name, character: character)
    }

    static func inventoryRecord(_ change: InventoryChange, code: String) -> CKRecord {
        let record = CKRecord(recordType: inventoryType, recordID: CKRecord.ID(recordName: "inventory-\(change.id.uuidString)"))
        record["joinCode"] = code as CKRecordValue
        record["playerID"] = change.playerID as CKRecordValue
        record["itemID"] = change.itemID as CKRecordValue
        record["itemName"] = change.itemName as CKRecordValue
        record["delta"] = change.delta as CKRecordValue
        record["authorID"] = change.authorID as CKRecordValue
        record["changedAt"] = change.date as CKRecordValue
        return record
    }

    static func inventoryChange(from record: CKRecord) -> InventoryChange? {
        let prefix = "inventory-"
        let name = record.recordID.recordName
        guard name.hasPrefix(prefix),
              let id = UUID(uuidString: String(name.dropFirst(prefix.count))),
              let playerID = record["playerID"] as? String,
              let itemID = record["itemID"] as? String,
              let itemName = record["itemName"] as? String,
              let delta = record["delta"] as? Int,
              let authorID = record["authorID"] as? String,
              let date = record["changedAt"] as? Date else { return nil }
        return InventoryChange(id: id, playerID: playerID, itemID: itemID, itemName: itemName,
                               delta: delta, authorID: authorID, date: date)
    }
}

extension CampaignManager {
    /// The campaign manager the app runs with.
    ///
    /// Builds with iCloud turned on share campaigns through CloudKit (always in Release; in Debug only with
    /// `-useCloudKit`). Otherwise campaigns live on this phone only, plus a sample campaign (code 123456)
    /// to try joining. `-inMemoryCampaigns` (used by UI tests) skips saving to disk.
    static func makeDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        cloudKitEnabled: Bool = ItemLibrary.cloudKitEnabledInBuild
    ) -> CampaignManager {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let persistence: CampaignPersistence
        if isDebug && arguments.contains("-dmTestCampaign") {
            // UI tests: start as the DM of a campaign that already has a player, so the DM's tools can be tried on one phone.
            persistence = InMemoryCampaignPersistence(dmTestSetup)
        } else if arguments.contains("-inMemoryCampaigns") {
            persistence = InMemoryCampaignPersistence()
        } else {
            persistence = FileCampaignPersistence.applicationSupport()
        }
        if cloudKitEnabled && (!isDebug || arguments.contains("-useCloudKit")) {
            return CampaignManager(directory: CloudKitCampaignDirectory(), persistence: persistence, isShared: true)
        }
        // Re-list campaigns saved on this phone so joining them on this phone still works after a relaunch.
        let saved = persistence.load()?.book.campaigns ?? []
        let directory = InMemoryCampaignDirectory(campaigns: InMemoryCampaignDirectory.sampleCampaigns + saved)
        return CampaignManager(directory: directory, persistence: persistence)
    }

    /// Used by `-dmTestCampaign` (Debug only): you are "Dana", DM of "Test Table" (code 654321) with one player.
    static let dmTestSetup: SavedCampaigns = {
        let me = CampaignMember(id: "ui-test-dm", name: "Dana")
        let player = CampaignMember(
            id: "ui-test-player",
            name: "Sam",
            character: CampaignCharacter(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                                         name: "Thorin", summary: "Level 1 Hill Dwarf Fighter")
        )
        let campaign = Campaign(name: "Test Table", joinCode: "654321", dungeonMaster: me, players: [player])
        return SavedCampaigns(me: me, book: CampaignBook(campaigns: [campaign]))
    }()
}
