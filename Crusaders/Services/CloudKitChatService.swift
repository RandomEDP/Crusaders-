import CloudKit
import CrusadersKit

/// Campaign chats in CloudKit.
///
/// **Party chat** lives in the public database, like the rest of the campaign, because everyone with the code can read it.
/// Record type `ChatMessage`, one per message, named `chat-<uuid>`, written by its sender:
/// - `joinCode` (String, queryable), `channel`, `senderID`, `senderName`, `text` (String),
///   `narration` (Int64, 1 for DM narration), `sentAt` (Date)
///
/// **Private chats** (DM and one player) are never in the public database. Each one is a record zone
/// `whisper-<code>-<playerID>` in the **DM's private database**, shared with that one player through a zone-wide
/// `CKShare` with no public access. iCloud itself refuses everyone else, so other players can't read it even with
/// the share link. Messages are `WhisperMessage` records (same fields as `ChatMessage`, named `whisper-<uuid>`).
///
/// How a private chat opens:
/// 1. The DM's phone creates the zone and share, and adds the player as the only read-write participant. The player's
///    iCloud identity is taken from the iCloud-stamped creator of their `CampaignPlayer` record, so nobody can pose as them.
/// 2. The DM's phone saves the share link in a public `WhisperInvite` record (`whisper-invite-<code>-<playerID>`).
///    The link alone grants nothing: only the participant can accept it.
/// 3. The player's phone accepts the share (after checking the invite was written by the campaign's DM),
///    then reads and writes the zone through its shared database.
///
/// CloudKit Dashboard setup is described in README.md (Campaign chat).
actor CloudKitChatService: ChatService {
    static let partyType = "ChatMessage"
    static let whisperType = "WhisperMessage"
    static let inviteType = "WhisperInvite"

    private let container: CKContainer
    /// Private chats this phone has already set up (DM) or accepted (player), by zone name.
    private var openedZones: [String: CKRecordZone.ID] = [:]

    init(container: CKContainer = CloudConfig.container) {
        self.container = container
    }

    func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async throws -> [ChatMessage] {
        guard campaign.canUse(channel, memberID: viewer.id) else { throw ChatError.notAllowed }
        switch channel {
        case .party:
            let query = CKQuery(recordType: Self.partyType,
                                predicate: NSPredicate(format: "joinCode == %@", campaign.joinCode))
            var records: [CKRecord] = []
            var page = try await container.publicCloudDatabase.records(matching: query)
            while true {
                records += page.matchResults.compactMap { try? $0.1.get() }
                guard let cursor = page.queryCursor else { break }
                page = try await container.publicCloudDatabase.records(continuingMatchFrom: cursor)
            }
            return records.compactMap(Self.message(from:))
        case .whisper(let playerID):
            let (database, zoneID) = try await whisperZone(campaign: campaign, playerID: playerID, viewerID: viewer.id)
            var records: [CKRecord] = []
            var token: CKServerChangeToken?
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                records += changes.modificationResultsByID.values.compactMap { try? $0.get().record }
                token = changes.changeToken
                if !changes.moreComing { break }
            }
            return records.filter { $0.recordType == Self.whisperType }.compactMap(Self.message(from:))
        }
    }

    func send(_ message: ChatMessage, campaign: Campaign) async throws {
        guard campaign.allows(message) else { throw ChatError.notAllowed }
        let database: CKDatabase
        let record: CKRecord
        switch message.channel {
        case .party:
            database = container.publicCloudDatabase
            record = Self.record(for: message, code: campaign.joinCode, zoneID: nil)
        case .whisper(let playerID):
            let zone = try await whisperZone(campaign: campaign, playerID: playerID, viewerID: message.senderID)
            database = zone.0
            record = Self.record(for: message, code: campaign.joinCode, zoneID: zone.1)
        }
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[record.recordID] {
            _ = try saveResult.get()
        }
    }

    // MARK: - Private chats

    private func whisperZone(campaign: Campaign, playerID: String, viewerID: String) async throws -> (CKDatabase, CKRecordZone.ID) {
        let zoneName = Self.zoneName(code: campaign.joinCode, playerID: playerID)
        if viewerID == campaign.dungeonMaster.id {
            let zoneID = openedZones[zoneName] ?? CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            if openedZones[zoneName] == nil {
                try await openAsDungeonMaster(zoneID: zoneID, campaign: campaign, playerID: playerID)
                openedZones[zoneName] = zoneID
            }
            return (container.privateCloudDatabase, zoneID)
        }
        guard viewerID == playerID else { throw ChatError.notAllowed }
        if let zoneID = openedZones[zoneName] {
            return (container.sharedCloudDatabase, zoneID)
        }
        // Already accepted on this iCloud account (maybe on another device)?
        if let zone = try await container.sharedCloudDatabase.allRecordZones().first(where: { $0.zoneID.zoneName == zoneName }) {
            openedZones[zoneName] = zone.zoneID
            return (container.sharedCloudDatabase, zone.zoneID)
        }
        let zoneID = try await acceptInvite(campaign: campaign, playerID: playerID)
        openedZones[zoneName] = zoneID
        return (container.sharedCloudDatabase, zoneID)
    }

    /// DM's phone: makes the zone and its share, adds the player, and posts the link for them.
    private func openAsDungeonMaster(zoneID: CKRecordZone.ID, campaign: Campaign, playerID: String) async throws {
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        var share: CKShare
        do {
            guard let existing = try await database.record(for: shareID) as? CKShare else { throw ChatError.unavailable }
            share = existing
        } catch let error as CKError where error.code == .unknownItem {
            share = CKShare(recordZoneID: zoneID)
            share.publicPermission = .none
            share[CKShare.SystemFieldKey.title] = "\(campaign.name): private chat" as CKRecordValue
        }

        // The player's real iCloud identity: iCloud stamps who created their CampaignPlayer record.
        let playerRecord = try await container.publicCloudDatabase.record(
            for: CloudKitCampaignDirectory.playerRecordID(code: campaign.joinCode, memberID: playerID)
        )
        guard let playerUserID = playerRecord.creatorUserRecordID else { throw ChatError.unavailable }

        let alreadyAdded = share.participants.contains { $0.userIdentity.userRecordID?.recordName == playerUserID.recordName }
        if !alreadyAdded || share.url == nil {
            if !alreadyAdded {
                let participant = try await participant(for: playerUserID)
                participant.permission = .readWrite
                share.addParticipant(participant)
            }
            let result = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
            if let saved = try result.saveResults[share.recordID]?.get() as? CKShare {
                share = saved
            }
        }
        guard let url = share.url else { throw ChatError.unavailable }

        let invite = Self.inviteRecord(code: campaign.joinCode, playerID: playerID, shareURL: url)
        let result = try await container.publicCloudDatabase.modifyRecords(saving: [invite], deleting: [], savePolicy: .allKeys)
        if let saveResult = result.saveResults[invite.recordID] {
            _ = try saveResult.get()
        }
    }

    /// Player's phone: accepts the DM's share, after checking the invite really came from the DM.
    private func acceptInvite(campaign: Campaign, playerID: String) async throws -> CKRecordZone.ID {
        let invite: CKRecord
        let campaignRecord: CKRecord
        do {
            invite = try await container.publicCloudDatabase.record(for: Self.inviteID(code: campaign.joinCode, playerID: playerID))
            campaignRecord = try await container.publicCloudDatabase.record(for: CloudKitCampaignDirectory.campaignID(code: campaign.joinCode))
        } catch let error as CKError where error.code == .unknownItem {
            throw ChatError.privateChatNotReady
        }
        guard let dmUserID = campaignRecord.creatorUserRecordID,
              invite.creatorUserRecordID?.recordName == dmUserID.recordName,
              let url = Self.shareURL(from: invite) else {
            throw ChatError.privateChatNotReady
        }
        let metadata = try await shareMetadata(for: url)
        guard metadata.share.owner.userIdentity.userRecordID?.recordName == dmUserID.recordName else {
            throw ChatError.notAllowed
        }
        try await accept(metadata)
        return metadata.share.recordID.zoneID
    }

    private func participant(for userID: CKRecord.ID) async throws -> CKShare.Participant {
        let found = ResultBox<CKShare.Participant>()
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(
                userIdentityLookupInfos: [CKUserIdentity.LookupInfo(userRecordID: userID)]
            )
            operation.perShareParticipantResultBlock = { _, result in found.set(result) }
            operation.fetchShareParticipantsResultBlock = { result in
                continuation.resume(with: found.finish(result))
            }
            container.add(operation)
        }
    }

    private func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        let found = ResultBox<CKShare.Metadata>()
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.perShareMetadataResultBlock = { _, result in found.set(result) }
            operation.fetchShareMetadataResultBlock = { result in
                continuation.resume(with: found.finish(result))
            }
            container.add(operation)
        }
    }

    private func accept(_ metadata: CKShare.Metadata) async throws {
        let found = ResultBox<CKShare>()
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.perShareResultBlock = { _, result in found.set(result) }
            operation.acceptSharesResultBlock = { result in
                continuation.resume(with: found.finish(result))
            }
            container.add(operation)
        }
    }

    // MARK: - Record mapping (tested in AppModelTests)

    static func zoneName(code: String, playerID: String) -> String {
        "whisper-\(code)-\(playerID)"
    }

    static func inviteID(code: String, playerID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "whisper-invite-\(code)-\(playerID)")
    }

    static func inviteRecord(code: String, playerID: String, shareURL: URL) -> CKRecord {
        let record = CKRecord(recordType: inviteType, recordID: inviteID(code: code, playerID: playerID))
        record["joinCode"] = code as CKRecordValue
        record["playerID"] = playerID as CKRecordValue
        record["shareURL"] = shareURL.absoluteString as CKRecordValue
        return record
    }

    static func shareURL(from invite: CKRecord) -> URL? {
        (invite["shareURL"] as? String).flatMap(URL.init(string:))
    }

    /// A party message goes in the public database's default zone; a private one in its share zone.
    static func record(for message: ChatMessage, code: String, zoneID: CKRecordZone.ID?) -> CKRecord {
        let isWhisper = message.channel.whisperPlayerID != nil
        let name = (isWhisper ? "whisper-" : "chat-") + message.id.uuidString
        let recordID = zoneID.map { CKRecord.ID(recordName: name, zoneID: $0) } ?? CKRecord.ID(recordName: name)
        let record = CKRecord(recordType: isWhisper ? whisperType : partyType, recordID: recordID)
        record["joinCode"] = code as CKRecordValue
        record["channel"] = message.channel.id as CKRecordValue
        record["senderID"] = message.senderID as CKRecordValue
        record["senderName"] = message.senderName as CKRecordValue
        record["text"] = message.text as CKRecordValue
        record["narration"] = (message.isNarration ? 1 : 0) as CKRecordValue
        record["sentAt"] = message.sentAt as CKRecordValue
        return record
    }

    static func message(from record: CKRecord) -> ChatMessage? {
        let name = record.recordID.recordName
        let uuidText = ["chat-", "whisper-"].first(where: { name.hasPrefix($0) }).map { String(name.dropFirst($0.count)) }
        guard let id = uuidText.flatMap(UUID.init(uuidString:)),
              let channel = (record["channel"] as? String).flatMap(ChatChannel.init(id:)),
              let senderID = record["senderID"] as? String,
              let senderName = record["senderName"] as? String,
              let text = record["text"] as? String,
              let sentAt = record["sentAt"] as? Date else { return nil }
        return ChatMessage(id: id, channel: channel, senderID: senderID, senderName: senderName, text: text,
                           isNarration: (record["narration"] as? Int ?? 0) != 0, sentAt: sentAt)
    }
}

/// Collects the per-item result of a CloudKit operation for its completion block.
private final class ResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.result = result
    }

    /// The item's result, or the operation's error if the whole operation failed.
    func finish(_ operation: Result<Void, Error>) -> Result<Value, Error> {
        lock.lock(); defer { lock.unlock() }
        if case .failure(let error) = operation { return .failure(error) }
        return result ?? .failure(ChatError.unavailable)
    }
}

extension CampaignChat {
    /// The chat the app runs with: CloudKit when campaigns are shared through iCloud, otherwise on this phone only.
    static func makeDefault(sharedThroughCloudKit: Bool) -> CampaignChat {
        CampaignChat(service: sharedThroughCloudKit ? CloudKitChatService() : InMemoryChatService.withSamples())
    }
}
