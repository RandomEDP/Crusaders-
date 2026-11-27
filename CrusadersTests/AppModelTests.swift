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
        let directory = InMemoryCampaignDirectory(campaigns: [Campaign(name: "Tomb", joinCode: "TMB234", role: .dungeonMaster)])
        let model = AppModel(campaignDirectory: directory)
        let joined = try model.joinCampaign(code: "tmb234")
        XCTAssertEqual(joined.name, "Tomb")
        XCTAssertEqual(joined.role, .player)
    }

    func testCreateCharacterFromDraftUsesSRDRules() throws {
        let model = AppModel()
        var draft = CharacterDraft.starter(catalog: model.rules)
        draft.name = "Bram"
        let hero = try model.createCharacter(from: draft)
        XCTAssertEqual(hero.summary, "Level 1 Human Fighter")
        XCTAssertEqual(model.sheet(for: hero.id)?.maxHitPoints, 12)
        XCTAssertNil(model.sheet(for: UUID()))
    }

    func testCreateCharacterRejectsBlankName() {
        let model = AppModel()
        XCTAssertThrowsError(try model.createCharacter(from: CharacterDraft.starter())) {
            XCTAssertEqual($0 as? CharacterError, .emptyName)
        }
        XCTAssertTrue(model.roster.characters.isEmpty)
    }

    func testAddExperienceReturnsLevelUpSummaryOnlyWhenLevelling() throws {
        let model = AppModel()
        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        let hero = try model.createCharacter(from: draft)
        XCTAssertNil(try model.addExperience(100, to: hero.id))
        let summary = try XCTUnwrap(try model.addExperience(800, to: hero.id))
        XCTAssertEqual(summary.fromLevel, 1)
        XCTAssertEqual(summary.toLevel, 3)
        XCTAssertEqual(summary.levels.map(\.level), [2, 3])
        XCTAssertEqual(model.character(id: hero.id)?.experiencePoints, 900)
        XCTAssertThrowsError(try model.addExperience(0, to: hero.id))
    }

    func testToggleSpellAndSpendImprovementPoint() throws {
        let model = AppModel()
        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        draft.level = 4
        let hero = try model.createCharacter(from: draft)
        model.toggleSpell("fire-bolt", for: hero.id)
        XCTAssertEqual(model.character(id: hero.id)?.spellIDs, ["fire-bolt"])
        model.toggleSpell("fire-bolt", for: hero.id)
        XCTAssertEqual(model.character(id: hero.id)?.spellIDs, [])

        try model.spendImprovementPoint(on: .con, for: hero.id)
        XCTAssertEqual(model.sheet(for: hero.id)?.unspentImprovementPoints, 1)
    }
}
