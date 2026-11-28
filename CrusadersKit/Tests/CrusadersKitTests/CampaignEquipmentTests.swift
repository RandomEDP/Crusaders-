import XCTest
@testable import CrusadersKit

private let catalog = ItemCatalog(baseItems: (try? SRDItems.load()) ?? [])

/// A DM and two players sharing one directory, with the DM handing out gear.
@MainActor
private struct EquipTable {
    let dm: CampaignManager
    let player1: CampaignManager
    let player2: CampaignManager
    let code = "515151"

    init() {
        let directory = InMemoryCampaignDirectory()
        dm = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(),
                             makeCode: { "515151" }, newMemberID: { "dm" })
        player1 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p1" })
        player2 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p2" })
    }

    func setUp() async throws {
        try await dm.create(name: "Keep on the Borderlands", yourName: "Dana")
        try await player1.join(code: code, yourName: "Sam",
                               character: PlayerCharacter(name: "Aria", race: "Human", characterClass: "Fighter"))
        try await player2.join(code: code, yourName: "Lee",
                               character: PlayerCharacter(name: "Bram", race: "Human", characterClass: "Rogue"))
        await dm.refresh()
        for (id, name) in [("chain-mail", "Chain Mail"), ("shield", "Shield"), ("longsword", "Longsword"), ("greatsword", "Greatsword")] {
            try await dm.addItem(itemID: id, name: name, quantity: 1, to: "p1", inCampaign: code)
        }
        await player1.refresh()
        await player2.refresh()
    }

    func gear(_ manager: CampaignManager, of playerID: String) -> EquippedGear {
        manager.campaign(code: code)?.equippedGear(of: playerID, catalog: catalog) ?? .none
    }
}

@MainActor
final class CampaignEquipmentTests: XCTestCase {
    func testPlayerEquipsTheirOwnItemsAndTheDMSeesThem() async throws {
        let table = EquipTable()
        try await table.setUp()
        try await table.player1.equip(itemID: "chain-mail", in: .armour, for: "p1", inCampaign: table.code, catalog: catalog)
        try await table.player1.equip(itemID: "shield", in: .shield, for: "p1", inCampaign: table.code, catalog: catalog)
        try await table.player1.equip(itemID: "longsword", in: .mainHand, for: "p1", inCampaign: table.code, catalog: catalog)

        let mine = table.gear(table.player1, of: "p1")
        XCTAssertEqual(mine.armour?.id, "chain-mail")
        XCTAssertEqual(mine.shield?.id, "shield")
        XCTAssertEqual(mine.mainHand?.id, "longsword")

        await table.dm.refresh()
        XCTAssertEqual(table.gear(table.dm, of: "p1").equipped.map(\.gear.id), ["chain-mail", "shield", "longsword"])
    }

    func testTheRulesAreCheckedWhenEquipping() async throws {
        let table = EquipTable()
        try await table.setUp()
        try await table.player1.equip(itemID: "shield", in: .shield, for: "p1", inCampaign: table.code, catalog: catalog)
        do {
            try await table.player1.equip(itemID: "greatsword", in: .mainHand, for: "p1", inCampaign: table.code, catalog: catalog)
            XCTFail("a greatsword needs both hands")
        } catch {
            XCTAssertEqual(error as? EquipError, .needsBothHands(blockedBy: "Shield"))
        }
        XCTAssertNil(table.gear(table.player1, of: "p1").mainHand)
    }

    func testTheDMCanEquipAPlayerButOtherPlayersCant() async throws {
        let table = EquipTable()
        try await table.setUp()
        try await table.dm.equip(itemID: "chain-mail", in: .armour, for: "p1", inCampaign: table.code, catalog: catalog)
        XCTAssertEqual(table.gear(table.dm, of: "p1").armour?.id, "chain-mail")

        do {
            try await table.player2.equip(itemID: "longsword", in: .mainHand, for: "p1", inCampaign: table.code, catalog: catalog)
            XCTFail("players can't equip someone else")
        } catch {
            XCTAssertEqual(error as? CampaignError, .notYourCharacter)
        }
        do {
            try await table.dm.equip(itemID: "longsword", in: .mainHand, for: "nobody", inCampaign: table.code, catalog: catalog)
            XCTFail("unknown player")
        } catch {
            XCTAssertEqual(error as? CampaignError, .playerNotFound)
        }
    }

    func testUnequipAndRemovingAnEquippedItem() async throws {
        let table = EquipTable()
        try await table.setUp()
        try await table.player1.equip(itemID: "chain-mail", in: .armour, for: "p1", inCampaign: table.code, catalog: catalog)
        try await table.player1.equip(itemID: "longsword", in: .mainHand, for: "p1", inCampaign: table.code, catalog: catalog)
        try await table.player1.setUsesBothHands(true, for: "p1", inCampaign: table.code, catalog: catalog)
        XCTAssertTrue(table.gear(table.player1, of: "p1").usesBothHands)

        try await table.player1.unequip(itemID: "longsword", for: "p1", inCampaign: table.code, catalog: catalog)
        XCTAssertNil(table.gear(table.player1, of: "p1").mainHand)

        // The DM takes the armour away: it drops off the character too.
        await table.dm.refresh()
        try await table.dm.removeItem(itemID: "chain-mail", from: "p1", inCampaign: table.code)
        await table.player1.refresh()
        XCTAssertNil(table.gear(table.player1, of: "p1").armour)
    }

    func testAttunementThroughTheCampaign() async throws {
        let table = EquipTable()
        try await table.setUp()
        try await table.dm.addItem(itemID: "holy-avenger", name: "Holy Avenger", quantity: 1, to: "p1", inCampaign: table.code)
        await table.player1.refresh()
        try await table.player1.equip(itemID: "holy-avenger", in: .mainHand, base: "longsword", for: "p1",
                                      inCampaign: table.code, catalog: catalog)
        try await table.player1.attune(itemID: "holy-avenger", for: "p1", inCampaign: table.code, catalog: catalog)
        XCTAssertEqual(table.gear(table.player1, of: "p1").attuned.map(\.id), ["holy-avenger"])
        XCTAssertEqual(table.gear(table.player1, of: "p1").mainHand?.name, "Holy Avenger (Longsword)")

        try await table.player1.endAttunement(itemID: "holy-avenger", for: "p1", inCampaign: table.code, catalog: catalog)
        XCTAssertEqual(table.gear(table.player1, of: "p1").attuned, [])
    }

    func testLoadoutsWrittenBySomeoneElseAreIgnored() {
        var campaign = Campaign(name: "Keep", joinCode: "515151", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Sam"))
        campaign.addPlayer(CampaignMember(id: "p2", name: "Lee"))
        let start = Date(timeIntervalSince1970: 100)
        campaign.apply(LoadoutChange(playerID: "p1", loadout: Loadout(armourID: "leather"), authorID: "p1", date: start))
        campaign.apply(LoadoutChange(playerID: "p1", loadout: Loadout(armourID: "plate"), authorID: "p2", date: start + 1))
        XCTAssertEqual(campaign.loadout(of: "p1").armourID, "leather")

        let dmChange = LoadoutChange(playerID: "p1", loadout: Loadout(armourID: "chain-mail"), authorID: "dm", date: start + 2)
        campaign.apply(dmChange)
        campaign.apply(dmChange)
        XCTAssertEqual(campaign.loadoutChanges.count, 3)
        XCTAssertEqual(campaign.loadout(of: "p1").armourID, "chain-mail")
        XCTAssertEqual(campaign.loadout(of: "p2"), .empty)
    }

    func testCampaignsSavedBeforeEquipmentStillLoad() throws {
        let json = #"{"name":"Old","joinCode":"111111","dungeonMaster":{"id":"dm","name":"Dana"},"players":[],"inventoryChanges":[]}"#
        let campaign = try JSONDecoder().decode(Campaign.self, from: Data(json.utf8))
        XCTAssertEqual(campaign.loadoutChanges, [])

        var withGear = campaign
        withGear.apply(LoadoutChange(playerID: "p1", loadout: Loadout(shieldID: "shield"), authorID: "dm"))
        let roundTrip = try JSONDecoder().decode(Campaign.self, from: JSONEncoder().encode(withGear))
        XCTAssertEqual(roundTrip, withGear)
    }

    func testFindsThePlayerPlayingACharacter() {
        let id = UUID()
        var campaign = Campaign(name: "Keep", joinCode: "515151", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Sam", character: CampaignCharacter(id: id, name: "Aria", summary: "")))
        XCTAssertEqual(campaign.player(playingCharacter: id)?.id, "p1")
        XCTAssertNil(campaign.player(playingCharacter: UUID()))
    }

    func testEquipErrorsHaveFriendlyMessages() {
        XCTAssertEqual(EquipError.handsFull(blockedBy: "Greatsword").localizedDescription,
                       "Your hands are full. Put away Greatsword first.")
        XCTAssertEqual(EquipError.attunementFull.localizedDescription,
                       "You can only be attuned to 3 magic items at once. End attunement to one first.")
        XCTAssertEqual(CampaignError.notYourCharacter.localizedDescription,
                       "You can only change your own character's equipment.")
    }
}
