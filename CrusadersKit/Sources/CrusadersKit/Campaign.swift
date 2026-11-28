import Foundation

/// The character a player brought to a campaign: a copy of the key details, so the DM can see it on their phone.
public struct CampaignCharacter: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// e.g. "Level 3 Hill Dwarf Cleric"
    public var summary: String

    public init(id: UUID, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }

    public init(_ character: PlayerCharacter) {
        self.init(id: character.id, name: character.name, summary: character.summary)
    }
}

/// Someone in a campaign: the Dungeon Master or a player.
public struct CampaignMember: Identifiable, Hashable, Codable, Sendable {
    /// Stable id for this person. A random id made on first launch for now;
    /// it becomes the Sign in with Apple / iCloud user id once those are switched on.
    public let id: String
    public var name: String
    /// The character a player joined with. Nil for the DM.
    public var character: CampaignCharacter?

    public init(id: String, name: String, character: CampaignCharacter? = nil) {
        self.id = id
        self.name = name
        self.character = character
    }
}

/// A campaign the user runs or plays in. The 6-digit join code identifies it everywhere.
public struct Campaign: Identifiable, Hashable, Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case dungeonMaster
        case player

        public var label: String {
            switch self {
            case .dungeonMaster: return "Dungeon Master"
            case .player: return "Player"
            }
        }
    }

    public var id: String { joinCode }
    public var name: String
    public var joinCode: String
    /// Whoever created the campaign.
    public var dungeonMaster: CampaignMember
    /// Everyone who joined with the code, in the order they joined.
    public var players: [CampaignMember]
    /// Every item added to or removed from a character's inventory, oldest first.
    /// Inventories are worked out from this log (see `inventory(of:)`).
    public var inventoryChanges: [InventoryChange]
    /// Every change to what a character wears, holds and is attuned to, oldest first.
    /// The latest allowed one for each player counts (see `loadout(of:)`).
    public var loadoutChanges: [LoadoutChange]
    /// Damage, healing, effects and rounds, oldest first (see `combatState(of:)`).
    public var combatEvents: [CombatEvent]
    /// Coins given, spent and exchanged, oldest first (see `purse(of:)`).
    public var coinChanges: [CoinChange]

    public init(
        name: String,
        joinCode: String,
        dungeonMaster: CampaignMember,
        players: [CampaignMember] = [],
        inventoryChanges: [InventoryChange] = [],
        loadoutChanges: [LoadoutChange] = [],
        combatEvents: [CombatEvent] = [],
        coinChanges: [CoinChange] = []
    ) {
        self.name = name
        self.joinCode = joinCode
        self.dungeonMaster = dungeonMaster
        self.players = players
        self.inventoryChanges = inventoryChanges
        self.loadoutChanges = loadoutChanges
        self.combatEvents = combatEvents
        self.coinChanges = coinChanges
    }

    enum CodingKeys: String, CodingKey {
        case name, joinCode, dungeonMaster, players, inventoryChanges, loadoutChanges, combatEvents, coinChanges
    }

    /// Campaigns saved before inventories existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            joinCode: try container.decode(String.self, forKey: .joinCode),
            dungeonMaster: try container.decode(CampaignMember.self, forKey: .dungeonMaster),
            players: try container.decodeIfPresent([CampaignMember].self, forKey: .players) ?? [],
            inventoryChanges: try container.decodeIfPresent([InventoryChange].self, forKey: .inventoryChanges) ?? [],
            loadoutChanges: try container.decodeIfPresent([LoadoutChange].self, forKey: .loadoutChanges) ?? [],
            combatEvents: try container.decodeIfPresent([CombatEvent].self, forKey: .combatEvents) ?? [],
            coinChanges: try container.decodeIfPresent([CoinChange].self, forKey: .coinChanges) ?? []
        )
    }

    public func player(id: String) -> CampaignMember? {
        players.first { $0.id == id }
    }

    /// Adds a change to the log, once.
    public mutating func apply(_ change: InventoryChange) {
        guard !inventoryChanges.contains(where: { $0.id == change.id }) else { return }
        inventoryChanges.append(change)
        inventoryChanges.sort { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// Whether `actorID` may make this change: only the DM adds items;
    /// the DM or the player who owns the inventory can remove them.
    public func allows(_ change: InventoryChange) -> Bool {
        if change.delta > 0 { return change.authorID == dungeonMaster.id }
        if change.delta < 0 { return change.authorID == dungeonMaster.id || change.authorID == change.playerID }
        return false
    }

    /// A player's character inventory, in the order items were first added.
    /// Changes the rules don't allow are ignored, and quantities never go below zero.
    public func inventory(of playerID: String) -> [InventoryEntry] {
        var entries: [InventoryEntry] = []
        for change in inventoryChanges where change.playerID == playerID && allows(change) {
            if let index = entries.firstIndex(where: { $0.itemID == change.itemID }) {
                entries[index].quantity = max(0, entries[index].quantity + change.delta)
            } else if change.delta > 0 {
                entries.append(InventoryEntry(itemID: change.itemID, name: change.itemName, quantity: change.delta))
            }
        }
        return entries.filter { $0.quantity > 0 }
    }

    /// Adds a loadout change to the log, once.
    public mutating func apply(_ change: LoadoutChange) {
        guard !loadoutChanges.contains(where: { $0.id == change.id }) else { return }
        loadoutChanges.append(change)
        loadoutChanges.sort { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// The DM or the player who owns the character can change what it wears and holds.
    public func allows(_ change: LoadoutChange) -> Bool {
        change.authorID == dungeonMaster.id || change.authorID == change.playerID
    }

    /// What a player's character wears and holds, as last set. Check it against the inventory with
    /// `Loadout.sanitized` or `EquippedGear(loadout:inventory:catalog:)`, since items may have been removed since.
    public func loadout(of playerID: String) -> Loadout {
        loadoutChanges.last { $0.playerID == playerID && allows($0) }?.loadout ?? .empty
    }

    /// A player's worn and held items, checked against their inventory.
    public func equippedGear(of playerID: String, catalog: ItemCatalog) -> EquippedGear {
        EquippedGear(loadout: loadout(of: playerID), inventory: inventory(of: playerID), catalog: catalog)
    }

    // MARK: Coins

    /// Adds a coin change to the log, once.
    public mutating func apply(_ change: CoinChange) {
        guard !coinChanges.contains(where: { $0.id == change.id }) else { return }
        coinChanges.append(change)
        coinChanges.sort { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// The DM can give or take any coins. A player can spend or exchange their own coins, but never make money.
    public func allows(_ change: CoinChange) -> Bool {
        if change.authorID == dungeonMaster.id { return true }
        return change.authorID == change.playerID && change.valueCopper <= 0
    }

    /// A player's coins. Changes that aren't allowed, or that would take more coins than there are, are ignored.
    public func purse(of playerID: String) -> CoinPurse {
        var purse = CoinPurse()
        for change in coinChanges where change.playerID == playerID && allows(change) {
            if let next = purse.adding(change.deltas) { purse = next }
        }
        return purse
    }

    // MARK: Combat

    /// Adds a combat event to the log, once.
    public mutating func apply(_ event: CombatEvent) {
        guard !combatEvents.contains(where: { $0.id == event.id }) else { return }
        combatEvents.append(event)
        combatEvents.sort { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// The DM can do anything. A player can only affect their own character (drinking a potion,
    /// ending an effect, reporting their stats), and can't move rounds on or take a long rest.
    public func allows(_ event: CombatEvent) -> Bool {
        if event.authorID == dungeonMaster.id { return true }
        switch event.kind {
        case .roundsAdvanced, .longRest: return false
        default: return event.authorID == event.playerID && !event.playerID.isEmpty
        }
    }

    /// The campaign's current combat round: every round the DM has moved on, added up.
    public var round: Int {
        combatEvents.reduce(0) { total, event in
            guard allows(event), case .roundsAdvanced(let count) = event.kind else { return total }
            return total + max(0, count)
        }
    }

    /// A player's character's damage, healing and effects in this campaign.
    public func combatState(of playerID: String) -> CombatState {
        CombatState(round: round, events: combatEvents.filter { $0.playerID == playerID && allows($0) })
    }

    /// The player in this campaign playing a character, if any.
    public func player(playingCharacter characterID: UUID) -> CampaignMember? {
        players.first { $0.character?.id == characterID }
    }

    /// This person's role, or nil if they aren't in the campaign.
    public func role(of memberID: String) -> Role? {
        if dungeonMaster.id == memberID { return .dungeonMaster }
        if players.contains(where: { $0.id == memberID }) { return .player }
        return nil
    }

    /// Adds a player, or updates their name and character if they're already listed. The DM is never added as a player.
    public mutating func addPlayer(_ player: CampaignMember) {
        guard player.id != dungeonMaster.id else { return }
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].name = player.name
            players[index].character = player.character ?? players[index].character
        } else {
            players.append(player)
        }
    }
}

public enum CampaignError: Error, Equatable, Sendable {
    case emptyName
    case emptyPlayerName
    case invalidJoinCode
    case campaignNotFound
    case alreadyJoined
    /// Every code we tried was already in use.
    case codeTaken
    /// iCloud couldn't be reached.
    case directoryUnavailable
    /// Joining needs one of the user's characters.
    case noCharacterSelected
    /// Only the DM can add items to an inventory.
    case onlyDungeonMasterCanAdd
    /// Players can only remove items from their own character.
    case notYourInventory
    case invalidQuantity
    case itemNotInInventory
    case playerNotFound
    /// Players can only change their own character's equipment.
    case notYourCharacter
}

/// One line of a character's inventory, e.g. Longsword ×2.
public struct InventoryEntry: Identifiable, Hashable, Sendable {
    /// The Library item id (or any stable id for the item).
    public let itemID: String
    public var name: String
    public var quantity: Int

    public var id: String { itemID }

    public init(itemID: String, name: String, quantity: Int) {
        self.itemID = itemID
        self.name = name
        self.quantity = quantity
    }
}

/// Something added to (`delta` > 0) or removed from (`delta` < 0) a player's character inventory.
/// Each change is its own record, written by whoever made it, so nobody edits anyone else's data.
public struct InventoryChange: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// The player whose character holds the item.
    public var playerID: String
    public var itemID: String
    public var itemName: String
    public var delta: Int
    /// Who made the change.
    public var authorID: String
    public var date: Date

    public init(
        id: UUID = UUID(),
        playerID: String,
        itemID: String,
        itemName: String,
        delta: Int,
        authorID: String,
        date: Date = Date()
    ) {
        self.id = id
        self.playerID = playerID
        self.itemID = itemID
        self.itemName = itemName
        self.delta = delta
        self.authorID = authorID
        self.date = date
    }
}

/// A new loadout for a player's character, written by whoever changed it (the player or the DM).
public struct LoadoutChange: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var playerID: String
    public var loadout: Loadout
    public var authorID: String
    public var date: Date

    public init(id: UUID = UUID(), playerID: String, loadout: Loadout, authorID: String, date: Date = Date()) {
        self.id = id
        self.playerID = playerID
        self.loadout = loadout
        self.authorID = authorID
        self.date = date
    }
}

/// Join codes are 6 digits, e.g. "042917". Leading zeros count.
public enum JoinCode {
    public static let length = 6
    public static let digits = Array("0123456789")

    public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<length).map { _ in digits.randomElement(using: &generator)! })
    }

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// Strips spaces and dashes. Returns nil unless exactly 6 digits are left.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy({ digits.contains($0) }) else { return nil }
        return cleaned
    }

    /// "042917" shown as "042 917" so it's easy to read out at the table.
    public static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// The campaigns this user is part of. Pure rules, no networking.
public struct CampaignBook: Equatable, Codable, Sendable {
    public private(set) var campaigns: [Campaign]

    public init(campaigns: [Campaign] = []) {
        self.campaigns = campaigns
    }

    public func campaign(code: String) -> Campaign? {
        campaigns.first { $0.joinCode == code }
    }

    public func contains(code: String) -> Bool {
        campaign(code: code) != nil
    }

    /// Adds a campaign, or replaces the stored copy with the same code (e.g. after a refresh).
    public mutating func upsert(_ campaign: Campaign) {
        if let index = campaigns.firstIndex(where: { $0.joinCode == campaign.joinCode }) {
            campaigns[index] = campaign
        } else {
            campaigns.append(campaign)
        }
    }

    public mutating func leave(code: String) {
        campaigns.removeAll { $0.joinCode == code }
    }

    /// Trims a name and rejects blanks.
    static func cleanName(_ raw: String, error: CampaignError) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw error }
        return trimmed
    }
}
