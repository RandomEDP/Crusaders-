import Foundation

/// Someone in a campaign: the Dungeon Master or a player.
public struct CampaignMember: Identifiable, Hashable, Codable, Sendable {
    /// Stable id for this person. A random id made on first launch for now;
    /// it becomes the Sign in with Apple / iCloud user id once those are switched on.
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
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

    public init(name: String, joinCode: String, dungeonMaster: CampaignMember, players: [CampaignMember] = []) {
        self.name = name
        self.joinCode = joinCode
        self.dungeonMaster = dungeonMaster
        self.players = players
    }

    /// This person's role, or nil if they aren't in the campaign.
    public func role(of memberID: String) -> Role? {
        if dungeonMaster.id == memberID { return .dungeonMaster }
        if players.contains(where: { $0.id == memberID }) { return .player }
        return nil
    }

    /// Adds a player, or updates their name if they're already listed. The DM is never added as a player.
    public mutating func addPlayer(_ player: CampaignMember) {
        guard player.id != dungeonMaster.id else { return }
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].name = player.name
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
