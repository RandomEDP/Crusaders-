import XCTest
@testable import CrusadersKit

final class CoinPurseTests: XCTestCase {
    func testHouseRuleRates() {
        XCTAssertEqual(Coin.cp.copperValue, 1)
        XCTAssertEqual(Coin.sp.copperValue, 100, "1 sp = 100 cp")
        XCTAssertEqual(Coin.gp.copperValue, 100 * Coin.sp.copperValue, "1 gp = 100 sp")
        XCTAssertEqual(Coin.ep.copperValue * 2, Coin.gp.copperValue)
        XCTAssertEqual(Coin.pp.copperValue, 10 * Coin.gp.copperValue)
    }

    func testTotalsAndText() {
        let purse = CoinPurse([.gp: 2, .sp: 3, .cp: 4])
        XCTAssertEqual(purse.totalCopper, 20_304)
        XCTAssertEqual(purse.text, "2 gp, 3 sp, 4 cp")
        XCTAssertEqual(CoinPurse().text, "No coins")
        XCTAssertTrue(CoinPurse([.gp: 0]).isEmpty)
    }

    func testAddingNeverGoesNegative() {
        let purse = CoinPurse([.sp: 5])
        XCTAssertEqual(purse.adding([.sp: -5]), CoinPurse())
        XCTAssertNil(purse.adding([.sp: -6]))
    }

    func testChangeUsesGoldSilverAndCopper() {
        XCTAssertEqual(CoinPurse.change(forCopper: 10_000 + 250 + 7), [.gp: 1, .sp: 2, .cp: 57])
        XCTAssertEqual(CoinPurse.change(forCopper: 0), [:])
    }

    func testPayingWithTheRightCoin() {
        XCTAssertEqual(CoinPurse([.gp: 10]).payment(for: Cost(amount: 3, coin: .gp)), [.gp: -3])
    }

    func testPayingBreaksABiggerCoinAndGivesChange() {
        // 5 sp from a purse holding only 1 gp: pay the gold piece, get 95 sp back.
        XCTAssertEqual(CoinPurse([.gp: 1]).payment(for: Cost(amount: 5, coin: .sp)), [.gp: -1, .sp: 95])
    }

    func testPayingWithSmallerCoinsFirst() {
        // 1 gp from 50 sp + 1 gp: there's a gold piece, so it's used.
        XCTAssertEqual(CoinPurse([.sp: 50, .gp: 1]).payment(for: Cost(amount: 1, coin: .gp)), [.gp: -1])
        // 1 gp from 150 sp: 100 sp exactly.
        XCTAssertEqual(CoinPurse([.sp: 150]).payment(for: Cost(amount: 1, coin: .gp)), [.sp: -100])
        // 2 gp from 1 pp: break the platinum, 8 gp change.
        XCTAssertEqual(CoinPurse([.pp: 1]).payment(for: Cost(amount: 2, coin: .gp)), [.pp: -1, .gp: 8])
    }

    func testNotEnoughMoney() {
        XCTAssertNil(CoinPurse([.sp: 99]).payment(for: Cost(amount: 1, coin: .gp)))
        XCTAssertNil(CoinPurse([.gp: 5]).payment(for: Cost(amount: 0, coin: .gp)))
    }

    func testEveryPaymentKeepsTheBooksBalanced() {
        let purses = [CoinPurse([.gp: 3, .sp: 7]), CoinPurse([.pp: 2, .cp: 40]), CoinPurse([.ep: 3])]
        let costs = [Cost(amount: 1, coin: .cp), Cost(amount: 55, coin: .sp), Cost(amount: 1, coin: .gp), Cost(amount: 1, coin: .ep)]
        for purse in purses {
            for cost in costs {
                guard let deltas = purse.payment(for: cost) else { continue }
                let after = purse.adding(deltas)
                XCTAssertNotNil(after, "\(purse.text) paying \(cost.text)")
                XCTAssertEqual(purse.totalCopper - (after?.totalCopper ?? 0), cost.inCopper, "\(purse.text) paying \(cost.text)")
            }
        }
    }
}

@MainActor
final class CampaignCoinTests: XCTestCase {
    private func table() async throws -> (dm: CampaignManager, player: CampaignManager, other: CampaignManager) {
        let directory = InMemoryCampaignDirectory()
        let dm = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(),
                                 makeCode: { "818181" }, newMemberID: { "dm" })
        let player = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p1" })
        let other = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p2" })
        try await dm.create(name: "Market", yourName: "Dana")
        try await player.join(code: "818181", yourName: "Sam", character: PlayerCharacter(name: "Aria", race: "", characterClass: ""))
        try await other.join(code: "818181", yourName: "Lee", character: PlayerCharacter(name: "Bram", race: "", characterClass: ""))
        await dm.refresh()
        return (dm, player, other)
    }

    func testDMGivesCoinsAndThePlayerSpendsThem() async throws {
        let (dm, player, _) = try await table()
        try await dm.giveCoins(2, of: .gp, to: "p1", inCampaign: "818181")
        await player.refresh()
        try await player.spend(Cost(amount: 30, coin: .sp), for: "p1", inCampaign: "818181")
        XCTAssertEqual(player.campaign(code: "818181")?.purse(of: "p1"), CoinPurse([.gp: 1, .sp: 70]))
    }

    func testPlayersCantGiveThemselvesCoinsOrSpendOthers() async throws {
        let (dm, player, other) = try await table()
        try await dm.giveCoins(5, of: .gp, to: "p1", inCampaign: "818181")
        await player.refresh()
        await other.refresh()
        do {
            try await player.giveCoins(100, of: .pp, to: "p1", inCampaign: "818181")
            XCTFail("players can't make money")
        } catch {
            XCTAssertEqual(error as? CoinError, .onlyDungeonMasterCanGive)
        }
        do {
            try await other.spend(Cost(amount: 1, coin: .gp), for: "p1", inCampaign: "818181")
            XCTFail("not their purse")
        } catch {
            XCTAssertEqual(error as? CoinError, .notYourPurse)
        }
        do {
            try await player.spend(Cost(amount: 6, coin: .gp), for: "p1", inCampaign: "818181")
            XCTFail("too expensive")
        } catch {
            XCTAssertEqual(error as? CoinError, .notEnoughMoney)
        }
    }

    func testPurseIgnoresChangesTheRulesDontAllow() {
        var campaign = Campaign(name: "Market", joinCode: "818181", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Sam"))
        let start = Date(timeIntervalSince1970: 0)
        campaign.apply(CoinChange(playerID: "p1", deltas: [.gp: 3], authorID: "dm", date: start))
        campaign.apply(CoinChange(playerID: "p1", deltas: [.pp: 10], authorID: "p1", date: start + 1))
        campaign.apply(CoinChange(playerID: "p1", deltas: [.gp: -9], authorID: "dm", date: start + 2))
        campaign.apply(CoinChange(playerID: "p1", deltas: [.gp: -1, .sp: 100], authorID: "p1", date: start + 3))
        XCTAssertEqual(campaign.purse(of: "p1"), CoinPurse([.gp: 2, .sp: 100]),
                       "player-made money and overdrafts are ignored; a fair exchange is fine")
    }

    func testOldCampaignsWithoutCoinsStillLoad() throws {
        let json = #"{"name":"Old","joinCode":"111111","dungeonMaster":{"id":"dm","name":"Dana"},"players":[]}"#
        let campaign = try JSONDecoder().decode(Campaign.self, from: Data(json.utf8))
        XCTAssertEqual(campaign.coinChanges, [])
        var rich = campaign
        rich.apply(CoinChange(playerID: "p1", deltas: [.gp: 3, .cp: 1], authorID: "dm"))
        XCTAssertEqual(try JSONDecoder().decode(Campaign.self, from: JSONEncoder().encode(rich)), rich)
    }
}
