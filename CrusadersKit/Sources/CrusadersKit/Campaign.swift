import Foundation

/// A campaign the user runs or plays in.
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

    public let id: UUID
    public var name: String
    public var joinCode: String
    public var role: Role

    public init(id: UUID = UUID(), name: String, joinCode: String, role: Role) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.role = role
    }
}

public enum CampaignError: Error, Equatable, Sendable {
    case emptyName
    case invalidJoinCode
    case campaignNotFound
    case alreadyJoined
}

/// Join codes are short, upper-case and avoid look-alike characters (0/O, 1/I/L).
public enum JoinCode {
    public static let length = 6
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// Upper-cases and strips spaces and dashes. Returns nil if the result is not a valid code.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }
}

/// Looks up campaigns that other people created, by join code.
/// Placeholder for the CloudKit-backed directory that comes later.
public protocol CampaignDirectory: Sendable {
    func campaign(forJoinCode code: String) -> Campaign?
}

public struct InMemoryCampaignDirectory: CampaignDirectory {
    private let campaigns: [String: Campaign]

    public init(campaigns: [Campaign]) {
        self.campaigns = Dictionary(campaigns.map { ($0.joinCode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func campaign(forJoinCode code: String) -> Campaign? {
        campaigns[code]
    }

    /// Sample campaigns you can join while there is no backend yet.
    public static let sample = InMemoryCampaignDirectory(campaigns: [
        Campaign(name: "The Sunken Citadel", joinCode: "CRUSAD", role: .player),
        Campaign(name: "Dragons of the Ember Coast", joinCode: "EMBER7", role: .player)
    ])
}

/// The campaigns the user is part of, plus the rules for creating and joining.
public struct CampaignBook: Equatable, Sendable {
    public private(set) var campaigns: [Campaign]

    public init(campaigns: [Campaign] = []) {
        self.campaigns = campaigns
    }

    @discardableResult
    public mutating func create(name: String, joinCode: String = JoinCode.generate()) throws -> Campaign {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CampaignError.emptyName }
        let campaign = Campaign(name: trimmed, joinCode: joinCode, role: .dungeonMaster)
        campaigns.append(campaign)
        return campaign
    }

    @discardableResult
    public mutating func join(code rawCode: String, directory: CampaignDirectory) throws -> Campaign {
        guard let code = JoinCode.normalize(rawCode) else { throw CampaignError.invalidJoinCode }
        guard !campaigns.contains(where: { $0.joinCode == code }) else { throw CampaignError.alreadyJoined }
        guard var found = directory.campaign(forJoinCode: code) else { throw CampaignError.campaignNotFound }
        found.role = .player
        campaigns.append(found)
        return found
    }

    public mutating func leave(id: Campaign.ID) {
        campaigns.removeAll { $0.id == id }
    }
}
