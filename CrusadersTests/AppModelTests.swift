import XCTest
import CrusadersKit
@testable import Crusaders

@MainActor
final class AppModelTests: XCTestCase {
    func testStartsWithNoCharactersOrCampaignsAndPlaceholderLibrary() {
        let model = AppModel()
        XCTAssertTrue(model.roster.characters.isEmpty)
        XCTAssertTrue(model.campaignBook.campaigns.isEmpty)
        XCTAssertFalse(model.libraryCategories.isEmpty)
    }

    func testAddAndDeleteCharacter() throws {
        let model = AppModel()
        try model.addCharacter(name: "Aria", race: "Elf", characterClass: "Wizard", level: 2)
        XCTAssertEqual(model.roster.characters.map(\.name), ["Aria"])
        model.deleteCharacters(atOffsets: IndexSet(integer: 0))
        XCTAssertTrue(model.roster.characters.isEmpty)
    }

    func testCreateCampaign() throws {
        let model = AppModel()
        let campaign = try model.createCampaign(name: "Night Below")
        XCTAssertEqual(campaign.role, .dungeonMaster)
        XCTAssertEqual(model.campaignBook.campaigns, [campaign])
    }

    func testJoinCampaignUsesDirectory() throws {
        let directory = InMemoryCampaignDirectory(campaigns: [Campaign(name: "Tomb", joinCode: "TOMB22", role: .dungeonMaster)])
        let model = AppModel(campaignDirectory: directory)
        let joined = try model.joinCampaign(code: "tomb22")
        XCTAssertEqual(joined.name, "Tomb")
        XCTAssertEqual(joined.role, .player)
    }

    func testErrorsHaveFriendlyMessages() {
        let errors: [LocalizedError] = [
            CharacterError.emptyName, CharacterError.levelOutOfRange,
            CampaignError.emptyName, CampaignError.invalidJoinCode,
            CampaignError.campaignNotFound, CampaignError.alreadyJoined
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
