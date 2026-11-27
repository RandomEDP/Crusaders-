import CloudKit
import CrusadersKit

/// The shared campaign list in the CloudKit public database, so players on other phones can join by code.
///
/// Record type `Campaign`, one per campaign, named `campaign-<code>`:
/// - `name` (String), `joinCode` (String), `dmID` (String), `dmName` (String)
///
/// Record type `CampaignPlayer`, one per player per campaign, named `player-<code>-<memberID>`.
/// Each player creates their own record, so nobody needs write access to anyone else's:
/// - `joinCode` (String, queryable), `memberID` (String), `name` (String)
///
/// CloudKit Dashboard setup is described in README.md (Campaigns).
struct CloudKitCampaignDirectory: CampaignDirectory {
    static let campaignType = "Campaign"
    static let playerType = "CampaignPlayer"

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
        return campaign
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
        let query = CKQuery(recordType: Self.playerType, predicate: NSPredicate(format: "joinCode == %@", code))
        var players: [(joined: Date, member: CampaignMember)] = []
        var page = try await database.records(matching: query, desiredKeys: ["memberID", "name"])
        while true {
            for (_, result) in page.matchResults {
                if let record = try? result.get(), let player = Self.player(from: record) {
                    players.append((record.creationDate ?? .distantFuture, player))
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["memberID", "name"])
        }
        // Sorted here rather than in the query, so no extra index is needed.
        return players.sorted { $0.joined < $1.joined }.map(\.member)
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

    static func playerRecord(_ player: CampaignMember, code: String) -> CKRecord {
        let id = CKRecord.ID(recordName: "player-\(code)-\(player.id)")
        let record = CKRecord(recordType: playerType, recordID: id)
        record["joinCode"] = code as CKRecordValue
        record["memberID"] = player.id as CKRecordValue
        record["name"] = player.name as CKRecordValue
        return record
    }

    static func player(from record: CKRecord) -> CampaignMember? {
        guard let id = record["memberID"] as? String, let name = record["name"] as? String else { return nil }
        return CampaignMember(id: id, name: name)
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
        let persistence: CampaignPersistence = arguments.contains("-inMemoryCampaigns")
            ? InMemoryCampaignPersistence()
            : FileCampaignPersistence.applicationSupport()
        if cloudKitEnabled && (!isDebug || arguments.contains("-useCloudKit")) {
            return CampaignManager(directory: CloudKitCampaignDirectory(), persistence: persistence, isShared: true)
        }
        // Re-list campaigns saved on this phone so joining them on this phone still works after a relaunch.
        let saved = persistence.load()?.book.campaigns ?? []
        let directory = InMemoryCampaignDirectory(campaigns: InMemoryCampaignDirectory.sampleCampaigns + saved)
        return CampaignManager(directory: directory, persistence: persistence)
    }
}
