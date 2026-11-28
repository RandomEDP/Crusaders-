import XCTest
import CrusadersKit
@testable import Crusaders

/// Tapping attacks, spells and abilities on the character sheet: the rolls go into the campaign's party chat,
/// spell slots and limited uses are spent, and ranged weapons use ammunition from the campaign inventory.
@MainActor
final class RollActionAppTests: XCTestCase {
    private func makeModel(_ directory: CampaignDirectory, chat: CampaignChat, roller: DiceRoller = .random,
                           store: CharacterStore? = nil) -> AppModel {
        AppModel(campaigns: CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence()),
                 chat: chat, characterStore: store, diceRoller: roller)
    }

    private func wizard(_ model: AppModel) throws -> PlayerCharacter {
        var draft = CharacterDraft(name: "Aria")
        draft.selectRace("elf")
        draft.selectClass("wizard")
        draft.useStandardArray()
        draft.toggleSkill(.arcana)
        let character = try model.createCharacter(from: draft)
        model.toggleSpell("fire-bolt", for: character.id)
        model.toggleSpell("magic-missile", for: character.id)
        return character
    }

    func testFiringALongbowPostsTheRollAndUsesArrowsUntilNoneAreLeft() async throws {
        let directory = InMemoryCampaignDirectory()
        let chatService = InMemoryChatService()
        let dm = makeModel(directory, chat: CampaignChat(service: chatService))
        let player = makeModel(directory, chat: CampaignChat(service: chatService), roller: .sequence([12, 6]))
        var draft = CharacterDraft.starter(catalog: player.rules)
        draft.name = "Thalia"
        let hero = try player.createCharacter(from: draft)
        let campaign = try await dm.createCampaign(name: "Tomb", yourName: "Dana")
        let code = campaign.joinCode
        try await player.joinCampaign(code: code, yourName: "Aria", characterID: hero.id)
        await dm.campaigns.refresh()
        let playerID = player.campaigns.me.id

        // One "Arrows (20)" goes in as 20 single arrows.
        for id in ["longbow", "arrows"] {
            try await dm.addItem(try XCTUnwrap(dm.itemLibrary.catalog.item(id: id)), quantity: 1, to: playerID, inCampaign: code)
        }
        await player.campaigns.refresh()
        XCTAssertEqual(player.campaigns.campaign(code: code)?.inventory(of: playerID).first { $0.itemID == "arrows" }?.quantity, 20)
        XCTAssertEqual(player.campaigns.campaign(code: code)?.inventory(of: playerID).first { $0.itemID == "arrows" }?.name, "Arrows")
        try await player.equip("longbow", in: .mainHand, for: playerID, inCampaign: code)

        let sheet = try XCTUnwrap(player.sheet(for: hero.id, campaignCode: code))
        let longbow = try XCTUnwrap(sheet.attackOptions.first { $0.name == "Longbow" })
        XCTAssertEqual(longbow.ammunition, .arrow)
        XCTAssertEqual(player.ammunition(.arrow, for: hero.id, campaignCode: code).map(\.quantity), [20])

        let outcome = try await player.rollAttack(longbow, characterID: hero.id, campaignCode: code)
        XCTAssertEqual(outcome.postedTo, "Tomb")
        XCTAssertNil(outcome.problem)
        XCTAssertTrue(outcome.text.hasPrefix("⚔️ Thalia attacks with Longbow"))
        XCTAssertTrue(outcome.text.contains("Arrows: 19 left"))
        XCTAssertEqual(player.ammunition(.arrow, for: hero.id, campaignCode: code).map(\.quantity), [19])

        // Everyone at the table sees the roll in the party chat.
        let latest = try XCTUnwrap(dm.campaigns.campaign(code: code))
        await dm.chat.load(.party, campaign: latest, viewer: dm.campaigns.me)
        let posted = try XCTUnwrap(dm.chat.messages(in: .party, campaign: latest, viewer: dm.campaigns.me).last)
        XCTAssertEqual(posted.text, outcome.text)
        XCTAssertEqual(posted.senderID, playerID)

        // With no arrows left, the bow can't be fired and nothing is posted.
        await dm.campaigns.refresh()
        try await dm.campaigns.removeItem(itemID: "arrows", quantity: 19, from: playerID, inCampaign: code)
        await player.campaigns.refresh()
        XCTAssertTrue(player.ammunition(.arrow, for: hero.id, campaignCode: code).isEmpty)
        do {
            _ = try await player.rollAttack(longbow, characterID: hero.id, campaignCode: code)
            XCTFail("A bow with no arrows can't be fired")
        } catch {
            XCTAssertEqual(error as? ActionError, .noAmmunition(.arrow))
        }
        let after = try XCTUnwrap(player.campaigns.campaign(code: code))
        await player.chat.load(.party, campaign: after, viewer: player.campaigns.me)
        XCTAssertEqual(player.chat.messages(in: .party, campaign: after, viewer: player.campaigns.me).count, 1)
    }

    func testMeleeAttacksNeedNoAmmunitionAndRollOutsideACampaign() async throws {
        let model = makeModel(InMemoryCampaignDirectory(), chat: CampaignChat(service: InMemoryChatService()),
                              roller: .sequence([10, 1]))
        var draft = CharacterDraft.starter(catalog: model.rules)
        draft.name = "Loner"
        let hero = try model.createCharacter(from: draft)
        let unarmed = try XCTUnwrap(model.sheet(for: hero.id)?.attackOptions.first)
        XCTAssertNil(unarmed.ammunition)
        let outcome = try await model.rollAttack(unarmed, characterID: hero.id)
        XCTAssertNil(outcome.postedTo, "Not in a campaign, so there's no party chat")
        XCTAssertTrue(outcome.text.contains("To hit:"))
    }

    func testCastingSpendsSlotsAndStopsWhenNoneAreLeft() async throws {
        let store = InMemoryCharacterStore()
        let model = makeModel(InMemoryCampaignDirectory(), chat: CampaignChat(service: InMemoryChatService()),
                              roller: .sequence([4]), store: store)
        let aria = try wizard(model)
        let missile = try XCTUnwrap(model.rules.spells(ids: ["magic-missile"]).first)
        let fireBolt = try XCTUnwrap(model.rules.spells(ids: ["fire-bolt"]).first)
        XCTAssertEqual(model.sheet(for: aria.id)?.spellSlotsLeft(atLevel: 1), 2)

        let cantrip = try await model.castSpell(fireBolt, slotLevel: nil, characterID: aria.id)
        XCTAssertTrue(cantrip.text.contains("Spell attack:"))
        XCTAssertEqual(model.sheet(for: aria.id)?.spellSlotsLeft(atLevel: 1), 2, "Cantrips don't use slots")

        let first = try await model.castSpell(missile, slotLevel: 1, characterID: aria.id)
        XCTAssertTrue(first.text.hasPrefix("✨ Aria casts Magic Missile (1st-level slot, 1 left)"))
        _ = try await model.castSpell(missile, slotLevel: 1, characterID: aria.id)
        XCTAssertEqual(model.sheet(for: aria.id)?.spellSlotsLeft(atLevel: 1), 0)
        XCTAssertEqual(store.characters.first?.spellSlotsUsed(atLevel: 1), 2, "Spent slots are saved")

        do {
            _ = try await model.castSpell(missile, slotLevel: 1, characterID: aria.id)
            XCTFail("No slots left")
        } catch {
            XCTAssertEqual(error as? ActionError, .noSpellSlot(level: 1))
        }

        model.restoreSpellSlot(level: 1, for: aria.id)
        XCTAssertEqual(model.sheet(for: aria.id)?.spellSlotsLeft(atLevel: 1), 1)
        model.updateCharacter(aria.id) { $0.rest(long: true) }
        XCTAssertEqual(model.sheet(for: aria.id)?.spellSlotsLeft(atLevel: 1), 2)
    }

    func testUsingAnAbilitySpendsAUseAndPostsItsRoll() async throws {
        let directory = InMemoryCampaignDirectory()
        let chatService = InMemoryChatService()
        let dm = makeModel(directory, chat: CampaignChat(service: chatService))
        let player = makeModel(directory, chat: CampaignChat(service: chatService), roller: .sequence([7]))
        var draft = CharacterDraft.starter(catalog: player.rules)
        draft.name = "Omi"
        let hero = try player.createCharacter(from: draft)
        let breath = CharacterResource(name: "Breath Weapon", uses: 1, detail: "DC 12 Dex, 1d10 Acid")
        player.updateCharacter(hero.id) { $0.resources = [breath] }
        let campaign = try await dm.createCampaign(name: "Tomb", yourName: "Dana")
        try await player.joinCampaign(code: campaign.joinCode, yourName: "Sam", characterID: hero.id)

        let outcome = try await player.useAbility(breath.id, characterID: hero.id, campaignCode: campaign.joinCode)
        XCTAssertEqual(outcome.postedTo, "Tomb")
        XCTAssertEqual(outcome.text, "🔥 Omi uses Breath Weapon (0 of 1 left)\nDC 12 Dex, 1d10 Acid\nRoll: 7 acid (1d10: [7])")
        do {
            _ = try await player.useAbility(breath.id, characterID: hero.id, campaignCode: campaign.joinCode)
            XCTFail("No uses left")
        } catch {
            XCTAssertEqual(error as? ActionError, .noUsesLeft(name: "Breath Weapon"))
        }
    }
}
