import Foundation
import Observation

/// What's saved on this phone: who the user is and which campaigns they're in.
public struct SavedCampaigns: Codable, Equatable, Sendable {
    public var me: CampaignMember
    public var book: CampaignBook

    public init(me: CampaignMember, book: CampaignBook) {
        self.me = me
        self.book = book
    }
}

/// Saves the user's campaign list on this phone.
public protocol CampaignPersistence: Sendable {
    func load() -> SavedCampaigns?
    func save(_ saved: SavedCampaigns) throws
}

/// Saves the campaign list as a JSON file.
public struct FileCampaignPersistence: CampaignPersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `campaigns.json` in Application Support.
    public static func applicationSupport() -> FileCampaignPersistence {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileCampaignPersistence(url: folder.appendingPathComponent("campaigns.json"))
    }

    public func load() -> SavedCampaigns? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedCampaigns.self, from: data)
    }

    public func save(_ saved: SavedCampaigns) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(saved).write(to: url, options: .atomic)
    }
}

/// Keeps the campaign list in memory. Used by tests, previews and UI tests.
public final class InMemoryCampaignPersistence: CampaignPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SavedCampaigns?

    public init(_ saved: SavedCampaigns? = nil) {
        stored = saved
    }

    public func load() -> SavedCampaigns? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ saved: SavedCampaigns) throws {
        lock.lock(); defer { lock.unlock() }
        stored = saved
    }
}

/// Creating, joining and refreshing campaigns.
/// Whoever creates a campaign is its Dungeon Master; everyone who joins with the code is a player.
@MainActor
@Observable
public final class CampaignManager {
    /// How many fresh codes to try before giving up when codes clash.
    public static let maxCodeAttempts = 20

    public private(set) var book: CampaignBook
    /// The user on this phone. Their name is remembered from the last create or join.
    public private(set) var me: CampaignMember
    /// The last refresh problem, shown as a banner. Saved campaigns still show when this is set.
    public private(set) var refreshError: String?

    /// Whether other phones can see campaigns made here (true once iCloud is on).
    public let isShared: Bool

    private let directory: CampaignDirectory
    private let persistence: CampaignPersistence
    private let makeCode: () -> String

    public init(
        directory: CampaignDirectory,
        persistence: CampaignPersistence,
        isShared: Bool = false,
        makeCode: @escaping () -> String = { JoinCode.generate() },
        newMemberID: () -> String = { UUID().uuidString }
    ) {
        let saved = persistence.load()
        self.me = saved?.me ?? CampaignMember(id: newMemberID(), name: "")
        self.book = saved?.book ?? CampaignBook()
        self.directory = directory
        self.persistence = persistence
        self.isShared = isShared
        self.makeCode = makeCode
        if saved == nil { persist() }
    }

    public var campaigns: [Campaign] { book.campaigns }

    public func campaign(code: String) -> Campaign? {
        book.campaign(code: code)
    }

    /// The user's role in a campaign.
    public func role(in campaign: Campaign) -> Campaign.Role? {
        campaign.role(of: me.id)
    }

    /// Creates a campaign with a new 6-digit code and makes the user its Dungeon Master.
    @discardableResult
    public func create(name: String, yourName: String) async throws -> Campaign {
        let campaignName = try CampaignBook.cleanName(name, error: .emptyName)
        let dmName = try CampaignBook.cleanName(yourName, error: .emptyPlayerName)
        let dungeonMaster = CampaignMember(id: me.id, name: dmName)

        for _ in 0..<Self.maxCodeAttempts {
            let code = makeCode()
            guard !book.contains(code: code) else { continue }
            let campaign = Campaign(name: campaignName, joinCode: code, dungeonMaster: dungeonMaster)
            do {
                try await directory.publish(campaign)
            } catch CampaignError.codeTaken {
                continue
            } catch let error as CampaignError {
                throw error
            } catch {
                throw CampaignError.directoryUnavailable
            }
            me.name = dmName
            book.upsert(campaign)
            persist()
            return campaign
        }
        throw CampaignError.codeTaken
    }

    /// Joins someone else's campaign by its 6-digit code with one of the user's characters.
    /// The user is listed as a player.
    @discardableResult
    public func join(code rawCode: String, yourName: String, character: PlayerCharacter?) async throws -> Campaign {
        guard let code = JoinCode.normalize(rawCode) else { throw CampaignError.invalidJoinCode }
        let playerName = try CampaignBook.cleanName(yourName, error: .emptyPlayerName)
        guard let character else { throw CampaignError.noCharacterSelected }
        guard !book.contains(code: code) else { throw CampaignError.alreadyJoined }
        let player = CampaignMember(id: me.id, name: playerName, character: CampaignCharacter(character))

        let joined: Campaign
        do {
            guard let found = try await directory.campaign(forJoinCode: code) else {
                throw CampaignError.campaignNotFound
            }
            guard found.role(of: me.id) != .dungeonMaster else { throw CampaignError.alreadyJoined }
            joined = try await directory.addPlayer(player, toCampaignWithCode: code)
        } catch let error as CampaignError {
            throw error
        } catch {
            throw CampaignError.directoryUnavailable
        }
        me.name = playerName
        book.upsert(joined)
        persist()
        return joined
    }

    /// The DM adds items to a player's character inventory.
    @discardableResult
    public func addItem(itemID: String, name: String, quantity: Int, to playerID: String, inCampaign code: String) async throws -> Campaign {
        guard quantity > 0 else { throw CampaignError.invalidQuantity }
        let campaign = try requireCampaign(code)
        guard campaign.role(of: me.id) == .dungeonMaster else { throw CampaignError.onlyDungeonMasterCanAdd }
        guard campaign.player(id: playerID) != nil else { throw CampaignError.playerNotFound }
        let change = InventoryChange(playerID: playerID, itemID: itemID, itemName: name, delta: quantity, authorID: me.id)
        return try await send(change, code: code)
    }

    /// The DM, or the player who owns the character, removes items. Removing more than there are removes them all.
    @discardableResult
    public func removeItem(itemID: String, quantity: Int = 1, from playerID: String, inCampaign code: String) async throws -> Campaign {
        guard quantity > 0 else { throw CampaignError.invalidQuantity }
        let campaign = try requireCampaign(code)
        guard campaign.role(of: me.id) == .dungeonMaster || me.id == playerID else { throw CampaignError.notYourInventory }
        guard let entry = campaign.inventory(of: playerID).first(where: { $0.itemID == itemID }) else {
            throw CampaignError.itemNotInInventory
        }
        let change = InventoryChange(playerID: playerID, itemID: itemID, itemName: entry.name,
                                     delta: -min(quantity, entry.quantity), authorID: me.id)
        return try await send(change, code: code)
    }

    private func requireCampaign(_ code: String) throws -> Campaign {
        guard let campaign = book.campaign(code: code) else { throw CampaignError.campaignNotFound }
        return campaign
    }

    private func send(_ change: InventoryChange, code: String) async throws -> Campaign {
        let updated: Campaign
        do {
            updated = try await directory.record(change, inCampaignWithCode: code)
        } catch let error as CampaignError {
            throw error
        } catch {
            throw CampaignError.directoryUnavailable
        }
        book.upsert(updated)
        persist()
        return updated
    }

    /// Fetches the latest player list for every campaign.
    public func refresh() async {
        var failed = false
        for code in book.campaigns.map(\.joinCode) {
            do {
                if let latest = try await directory.campaign(forJoinCode: code) {
                    book.upsert(latest)
                }
            } catch {
                failed = true
            }
        }
        refreshError = failed ? "Couldn't load the latest players. Showing what's saved on this phone." : nil
        persist()
    }

    /// Removes a campaign from this phone.
    public func leave(code: String) {
        book.leave(code: code)
        persist()
    }

    private func persist() {
        try? persistence.save(SavedCampaigns(me: me, book: book))
    }
}
