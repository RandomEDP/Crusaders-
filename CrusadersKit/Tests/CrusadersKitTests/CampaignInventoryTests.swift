import XCTest
@testable import CrusadersKit

private let aria = PlayerCharacter(name: "Aria", race: "High Elf", characterClass: "Wizard", level: 3)
private let bram = PlayerCharacter(name: "Bram", race: "Human", characterClass: "Fighter")

/// A DM and two players sharing one directory.
@MainActor
private struct Table {
    let directory: InMemoryCampaignDirectory
    let dm: CampaignManager
    let player1: CampaignManager
    let player2: CampaignManager
    let code = "424242"

    init() {
        let directory = InMemoryCampaignDirectory()
        self.directory = directory
        dm = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(),
                             makeCode: { "424242" }, newMemberID: { "dm" })
        player1 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p1" })
        player2 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p2" })
    }

    func setUp() async throws {
        try await dm.create(name: "Night Below", yourName: "Dana")
        try await player1.join(code: code, yourName: "Sam", character: aria)
        try await player2.join(code: code, yourName: "Lee", character: bram)
        await dm.refresh()
    }

    func inventory(_ manager: CampaignManager, of playerID: String) -> [InventoryEntry] {
        manager.campaign(code: code)?.inventory(of: playerID) ?? []
    }
}

@MainActor
final class CampaignJoinWithCharacterTests: XCTestCase {
    func testJoiningRecordsTheChosenCharacter() async throws {
        let table = Table()
        try await table.setUp()
        let campaign = try XCTUnwrap(table.dm.campaign(code: table.code))
        XCTAssertEqual(campaign.player(id: "p1")?.character,
                       CampaignCharacter(id: aria.id, name: "Aria", summary: aria.summary))
        XCTAssertEqual(campaign.player(id: "p2")?.character?.name, "Bram")
        XCTAssertNil(campaign.dungeonMaster.character)
    }

    func testJoiningWithoutACharacterFails() async {
        let player = CampaignManager(directory: InMemoryCampaignDirectory.withSamples(),
                                     persistence: InMemoryCampaignPersistence(), newMemberID: { "p1" })
        do {
            try await player.join(code: InMemoryCampaignDirectory.sampleCode, yourName: "Sam", character: nil)
            XCTFail("expected noCharacterSelected")
        } catch {
            XCTAssertEqual(error as? CampaignError, .noCharacterSelected)
        }
        XCTAssertTrue(player.campaigns.isEmpty)
    }

    func testOldSavedCampaignsWithoutCharactersOrInventoryStillLoad() throws {
        let json = #"{"name":"Old","joinCode":"111111","dungeonMaster":{"id":"dm","name":"Dana"},"players":[{"id":"p1","name":"Sam"}]}"#
        let campaign = try JSONDecoder().decode(Campaign.self, from: Data(json.utf8))
        XCTAssertNil(campaign.players.first?.character)
        XCTAssertTrue(campaign.inventoryChanges.isEmpty)
    }
}

@MainActor
final class CampaignInventoryTests: XCTestCase {
    func testDMAddsItemsAndTheyStack() async throws {
        let table = Table()
        try await table.setUp()
        try await table.dm.addItem(itemID: "longsword", name: "Longsword", quantity: 1, to: "p1", inCampaign: table.code)
        try await table.dm.addItem(itemID: "longsword", name: "Longsword", quantity: 2, to: "p1", inCampaign: table.code)
        try await table.dm.addItem(itemID: "rope", name: "Rope, hempen (50 feet)", quantity: 1, to: "p1", inCampaign: table.code)
        XCTAssertEqual(table.inventory(table.dm, of: "p1"), [
            InventoryEntry(itemID: "longsword", name: "Longsword", quantity: 3),
            InventoryEntry(itemID: "rope", name: "Rope, hempen (50 feet)", quantity: 1)
        ])
        XCTAssertTrue(table.inventory(table.dm, of: "p2").isEmpty)

        // The player sees it after refreshing.
        await table.player1.refresh()
        XCTAssertEqual(table.inventory(table.player1, of: "p1").map(\.quantity), [3, 1])
    }

    func testPlayersCannotAdd() async throws {
        let table = Table()
        try await table.setUp()
        await assertThrows(.onlyDungeonMasterCanAdd) {
            try await table.player1.addItem(itemID: "longsword", name: "Longsword", quantity: 1, to: "p1", inCampaign: table.code)
        }
        XCTAssertTrue(table.inventory(table.player1, of: "p1").isEmpty)
    }

    func testPlayerRemovesFromTheirOwnInventory() async throws {
        let table = Table()
        try await table.setUp()
        try await table.dm.addItem(itemID: "potion-of-healing", name: "Potion of healing", quantity: 3, to: "p1", inCampaign: table.code)
        await table.player1.refresh()

        try await table.player1.removeItem(itemID: "potion-of-healing", from: "p1", inCampaign: table.code)
        XCTAssertEqual(table.inventory(table.player1, of: "p1").first?.quantity, 2)

        // Removing more than there are takes the rest and the line disappears.
        try await table.player1.removeItem(itemID: "potion-of-healing", quantity: 10, from: "p1", inCampaign: table.code)
        XCTAssertTrue(table.inventory(table.player1, of: "p1").isEmpty)
        await assertThrows(.itemNotInInventory) {
            try await table.player1.removeItem(itemID: "potion-of-healing", from: "p1", inCampaign: table.code)
        }
    }

    func testDMCanRemoveFromAnyone() async throws {
        let table = Table()
        try await table.setUp()
        try await table.dm.addItem(itemID: "dagger", name: "Dagger", quantity: 2, to: "p2", inCampaign: table.code)
        try await table.dm.removeItem(itemID: "dagger", from: "p2", inCampaign: table.code)
        XCTAssertEqual(table.inventory(table.dm, of: "p2").first?.quantity, 1)
    }

    func testPlayerCannotRemoveFromSomeoneElse() async throws {
        let table = Table()
        try await table.setUp()
        try await table.dm.addItem(itemID: "dagger", name: "Dagger", quantity: 2, to: "p2", inCampaign: table.code)
        await table.player1.refresh()
        await assertThrows(.notYourInventory) {
            try await table.player1.removeItem(itemID: "dagger", from: "p2", inCampaign: table.code)
        }
        XCTAssertEqual(table.inventory(table.dm, of: "p2").first?.quantity, 2)
    }

    func testQuantityAndPlayerValidation() async throws {
        let table = Table()
        try await table.setUp()
        await assertThrows(.invalidQuantity) {
            try await table.dm.addItem(itemID: "dagger", name: "Dagger", quantity: 0, to: "p1", inCampaign: table.code)
        }
        await assertThrows(.playerNotFound) {
            try await table.dm.addItem(itemID: "dagger", name: "Dagger", quantity: 1, to: "nobody", inCampaign: table.code)
        }
        await assertThrows(.campaignNotFound) {
            try await table.dm.addItem(itemID: "dagger", name: "Dagger", quantity: 1, to: "p1", inCampaign: "999999")
        }
    }

    /// Records written straight to the shared database (e.g. by an old app version) are checked against the rules too.
    func testInventoryIgnoresChangesTheRulesDontAllow() {
        let date = Date(timeIntervalSince1970: 100)
        var campaign = Campaign(name: "Night Below", joinCode: "424242",
                                dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Sam"))
        campaign.addPlayer(CampaignMember(id: "p2", name: "Lee"))
        campaign.apply(InventoryChange(playerID: "p1", itemID: "gold", itemName: "Gold", delta: 99, authorID: "p1", date: date))
        campaign.apply(InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: 2, authorID: "dm", date: date + 1))
        campaign.apply(InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: -1, authorID: "p2", date: date + 2))
        XCTAssertEqual(campaign.inventory(of: "p1"), [InventoryEntry(itemID: "rope", name: "Rope", quantity: 2)])
    }

    func testChangesApplyInDateOrderAndOnlyOnce() {
        let start = Date(timeIntervalSince1970: 100)
        var campaign = Campaign(name: "Night Below", joinCode: "424242",
                                dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        let add = InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: 1, authorID: "dm", date: start)
        let remove = InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: -1, authorID: "p1", date: start + 1)
        let addAgain = InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: 1, authorID: "dm", date: start + 2)
        // Arrive out of order, with a duplicate.
        campaign.apply(addAgain)
        campaign.apply(remove)
        campaign.apply(add)
        campaign.apply(add)
        XCTAssertEqual(campaign.inventoryChanges.map(\.id), [add.id, remove.id, addAgain.id])
        XCTAssertEqual(campaign.inventory(of: "p1").first?.quantity, 1)
    }

    func testSampleCampaignHasAStartingInventory() {
        let sample = InMemoryCampaignDirectory.sampleCampaigns[0]
        XCTAssertEqual(sample.inventory(of: "sample-player").first?.name, "Potion of healing")
    }

    private func assertThrows(
        _ expected: CampaignError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Any
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CampaignError, expected, file: file, line: line)
        }
    }
}
