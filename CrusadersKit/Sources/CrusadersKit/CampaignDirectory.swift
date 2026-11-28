import Foundation

/// The shared list of every campaign, looked up by join code, so players on other phones can join.
/// The app uses the CloudKit public database once iCloud is switched on; until then, and in tests,
/// it uses `InMemoryCampaignDirectory`.
public protocol CampaignDirectory: Sendable {
    /// Saves a brand new campaign. Throws `CampaignError.codeTaken` if its code is already used.
    func publish(_ campaign: Campaign) async throws
    /// The campaign with this code, with its current players, or nil if there isn't one.
    func campaign(forJoinCode code: String) async throws -> Campaign?
    /// Lists a player in the campaign and returns it with the updated player list.
    /// Throws `CampaignError.campaignNotFound` if the code isn't used.
    func addPlayer(_ player: CampaignMember, toCampaignWithCode code: String) async throws -> Campaign
    /// Saves an inventory change and returns the campaign with it applied.
    /// Throws `CampaignError.campaignNotFound` if the code isn't used.
    func record(_ change: InventoryChange, inCampaignWithCode code: String) async throws -> Campaign
}

/// Keeps campaigns in memory. Used by tests, previews, and the app while iCloud is switched off.
public actor InMemoryCampaignDirectory: CampaignDirectory {
    private var campaigns: [String: Campaign]

    public init(campaigns: [Campaign] = []) {
        self.campaigns = Dictionary(campaigns.map { ($0.joinCode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func publish(_ campaign: Campaign) async throws {
        guard campaigns[campaign.joinCode] == nil else { throw CampaignError.codeTaken }
        campaigns[campaign.joinCode] = campaign
    }

    public func campaign(forJoinCode code: String) async throws -> Campaign? {
        campaigns[code]
    }

    public func addPlayer(_ player: CampaignMember, toCampaignWithCode code: String) async throws -> Campaign {
        guard var campaign = campaigns[code] else { throw CampaignError.campaignNotFound }
        campaign.addPlayer(player)
        campaigns[code] = campaign
        return campaign
    }

    public func record(_ change: InventoryChange, inCampaignWithCode code: String) async throws -> Campaign {
        guard var campaign = campaigns[code] else { throw CampaignError.campaignNotFound }
        campaign.apply(change)
        campaigns[code] = campaign
        return campaign
    }

    /// The sample campaign's code, so people can try joining before iCloud is on.
    public static let sampleCode = "123456"

    public static let sampleCampaigns = [
        Campaign(
            name: "The Sunken Citadel",
            joinCode: sampleCode,
            dungeonMaster: CampaignMember(id: "sample-dm", name: "Sample DM"),
            players: [CampaignMember(
                id: "sample-player",
                name: "Sample Player",
                character: CampaignCharacter(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                             name: "Thorin", summary: "Level 1 Hill Dwarf Fighter")
            )],
            inventoryChanges: [
                InventoryChange(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    playerID: "sample-player", itemID: "potion-of-healing", itemName: "Potion of healing",
                    delta: 2, authorID: "sample-dm", date: Date(timeIntervalSince1970: 0)
                )
            ]
        )
    ]

    /// A directory holding the sample campaign.
    public static func withSamples() -> InMemoryCampaignDirectory {
        InMemoryCampaignDirectory(campaigns: sampleCampaigns)
    }
}
