import XCTest
@testable import CrusadersKit

private func event(_ kind: CombatEvent.Kind, player: String = "p1", author: String = "dm", at seconds: Double) -> CombatEvent {
    CombatEvent(playerID: player, kind: kind, authorID: author, date: Date(timeIntervalSince1970: seconds))
}

final class DiceExpressionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(DiceExpression("2d4+2"), DiceExpression(count: 2, sides: 4, bonus: 2))
        XCTAssertEqual(DiceExpression("10d4 + 20"), DiceExpression(count: 10, sides: 4, bonus: 20))
        XCTAssertEqual(DiceExpression("3d6"), DiceExpression(count: 3, sides: 6))
        XCTAssertEqual(DiceExpression("1d4-1"), DiceExpression(count: 1, sides: 4, bonus: -1))
        XCTAssertNil(DiceExpression("d6"))
        XCTAssertNil(DiceExpression("abc"))
        XCTAssertNil(DiceExpression("2d"))
    }

    func testTextAndRolling() {
        let dice = DiceExpression(count: 2, sides: 4, bonus: 2)
        XCTAssertEqual(dice.text, "2d4 + 2")
        XCTAssertEqual(DiceExpression(count: 1, sides: 4, bonus: -1).text, "1d4 − 1")
        XCTAssertEqual(dice.roll(using: .sequence([3, 4])), 9)
    }
}

final class CombatStateTests: XCTestCase {
    func testDamageTakesTemporaryHitPointsFirstAndNeverGoesBelowZero() {
        let state = CombatState(events: [
            event(.temporaryHitPoints(amount: 10), at: 1),
            event(.damage(amount: 12, type: .slashing), at: 2)
        ])
        XCTAssertEqual(state.health(maxHitPoints: 20), HealthState(current: 18, maximum: 20, temporary: 0))

        let dead = CombatState(events: [event(.damage(amount: 99, type: .fire), at: 1)])
        XCTAssertEqual(dead.health(maxHitPoints: 20).current, 0)
        XCTAssertTrue(dead.health(maxHitPoints: 20).isDown)
    }

    func testHealingStopsAtMaxAndTemporaryHitPointsDontStack() {
        let state = CombatState(events: [
            event(.damage(amount: 5, type: .none), at: 1),
            event(.healing(amount: 50), at: 2),
            event(.temporaryHitPoints(amount: 8), at: 3),
            event(.temporaryHitPoints(amount: 5), at: 4)
        ])
        XCTAssertEqual(state.health(maxHitPoints: 20), HealthState(current: 20, maximum: 20, temporary: 8))
        XCTAssertEqual(state.health(maxHitPoints: 20).text, "20 / 20 HP + 8 temp")
    }

    func testLongRestRestoresEverythingAndEndsEffects() {
        let haste = ActiveEffect(name: "Potion of Speed", startRound: 0, durationRounds: 10, modifiers: EffectModifiers())
        let state = CombatState(events: [
            event(.damage(amount: 15, type: .none), at: 1),
            event(.effectStarted(haste), at: 2),
            event(.longRest, at: 3)
        ])
        XCTAssertEqual(state.health(maxHitPoints: 20).current, 20)
        XCTAssertEqual(state.activeEffects, [])
    }

    func testEffectsWearOffAfterTheirRoundsOrWhenEnded() {
        let haste = ActiveEffect(name: "Potion of Speed", startRound: 2, durationRounds: 10, modifiers: EffectModifiers())
        let flying = ActiveEffect(name: "Potion of Flying", startRound: 2, durationRounds: 600, modifiers: EffectModifiers())
        let events = [event(.effectStarted(haste), at: 1), event(.effectStarted(flying), at: 2)]
        XCTAssertEqual(CombatState(round: 11, events: events).activeEffects.map(\.name), ["Potion of Speed", "Potion of Flying"])
        XCTAssertEqual(CombatState(round: 12, events: events).activeEffects.map(\.name), ["Potion of Flying"])
        XCTAssertEqual(haste.roundsLeft(atRound: 5), 7)

        let ended = events + [event(.effectEnded(effectID: flying.id), at: 3)]
        XCTAssertEqual(CombatState(round: 3, events: ended).activeEffects.map(\.name), ["Potion of Speed"])
    }

    func testTimeLeftText() {
        XCTAssertEqual(ActiveEffect.timeLeftText(1), "1 round left")
        XCTAssertEqual(ActiveEffect.timeLeftText(8), "8 rounds left")
        XCTAssertEqual(ActiveEffect.timeLeftText(590), "59 min left")
        XCTAssertEqual(ActiveEffect.timeLeftText(1200), "2 h left")
    }

    func testLastStatusReportWins() {
        let state = CombatState(events: [
            event(.statusReport(maxHitPoints: 12, armorClass: 14), author: "p1", at: 1),
            event(.statusReport(maxHitPoints: 20, armorClass: 16), author: "p1", at: 2)
        ])
        XCTAssertEqual(state.lastReport?.maxHitPoints, 20)
        XCTAssertEqual(state.lastReport?.armorClass, 16)
        XCTAssertEqual(CombatState(events: [event(.damage(amount: 4, type: .none), at: 1)]).netDamage, 4)
    }
}

final class CampaignCombatRulesTests: XCTestCase {
    private func campaign() -> Campaign {
        var campaign = Campaign(name: "Keep", joinCode: "616161", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Sam"))
        campaign.addPlayer(CampaignMember(id: "p2", name: "Lee"))
        return campaign
    }

    func testOnlyTheDMMovesRoundsOn() {
        var table = campaign()
        table.apply(event(.roundsAdvanced(count: 3), player: "", author: "dm", at: 1))
        table.apply(event(.roundsAdvanced(count: 50), player: "", author: "p1", at: 2))
        XCTAssertEqual(table.round, 3)
    }

    func testPlayersOnlyAffectTheirOwnCharacter() {
        var table = campaign()
        table.apply(event(.damage(amount: 5, type: .none), player: "p1", author: "dm", at: 1))
        table.apply(event(.healing(amount: 5), player: "p1", author: "p1", at: 2))
        table.apply(event(.damage(amount: 9, type: .none), player: "p1", author: "p2", at: 3))
        table.apply(event(.longRest, player: "p1", author: "p1", at: 4))
        XCTAssertEqual(table.combatState(of: "p1").events.count, 2)
        XCTAssertEqual(table.combatState(of: "p1").health(maxHitPoints: 10).current, 10)
        XCTAssertEqual(table.combatState(of: "p2").events, [])
    }

    func testOldCampaignsWithoutCombatStillLoad() throws {
        let json = #"{"name":"Old","joinCode":"111111","dungeonMaster":{"id":"dm","name":"Dana"},"players":[]}"#
        let old = try JSONDecoder().decode(Campaign.self, from: Data(json.utf8))
        XCTAssertEqual(old.combatEvents, [])
        XCTAssertEqual(old.round, 0)

        var withEvents = campaign()
        let effect = ActiveEffect(name: "Potion of Growth", startRound: 0, durationRounds: 600,
                                  modifiers: EffectModifiers(weaponDamageDice: "1d4", notes: ["Enlarged"]))
        withEvents.apply(event(.effectStarted(effect), at: 1))
        withEvents.apply(event(.damage(amount: 3, type: .fire), at: 2))
        let roundTrip = try JSONDecoder().decode(Campaign.self, from: JSONEncoder().encode(withEvents))
        XCTAssertEqual(roundTrip, withEvents)
    }
}

final class PotionEffectTests: XCTestCase {
    func testEveryPotionInTheTableIsInTheLibrary() throws {
        let ids = Set(try SRDItems.load().map(\.id))
        for id in PotionEffect.table.keys {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testHealingPotionsRollTheirDice() {
        let events = PotionEffect.srd("potion-of-healing")!.events(
            itemName: "Potion of Healing", playerID: "p1", authorID: "p1", round: 0, roller: .sequence([3, 4]))
        XCTAssertEqual(events.map(\.kind), [.healing(amount: 9)])
        XCTAssertEqual(events.first?.note, "Potion of Healing: regained 9 HP (2d4 + 2)")
        XCTAssertNotNil(PotionEffect.srd("potion-of-supreme-healing")?.healing)
    }

    func testHeroismGivesTemporaryHitPointsAndBlessForAnHour() throws {
        let events = PotionEffect.srd("potion-of-heroism")!.events(
            itemName: "Potion of Heroism", playerID: "p1", authorID: "p1", round: 4, roller: .sequence([1]))
        XCTAssertEqual(events.first?.kind, .temporaryHitPoints(amount: 10))
        guard case .effectStarted(let effect) = try XCTUnwrap(events.last).kind else { return XCTFail("expected an effect") }
        XCTAssertEqual(effect.startRound, 4)
        XCTAssertEqual(effect.durationRounds, 600)
        XCTAssertEqual(effect.modifiers.attackAndSaveDice, "1d4")
    }

    func testGrowthRollsItsDurationInHours() throws {
        let events = PotionEffect.srd("potion-of-growth")!.events(
            itemName: "Potion of Growth", playerID: "p1", authorID: "p1", round: 0, roller: .sequence([3]))
        guard case .effectStarted(let effect) = try XCTUnwrap(events.first).kind else { return XCTFail("expected an effect") }
        XCTAssertEqual(effect.durationRounds, 3 * 600)
    }

    func testPoisonHurts() {
        let events = PotionEffect.srd("potion-of-poison")!.events(
            itemName: "Potion of Poison", playerID: "p1", authorID: "p1", round: 0, roller: .sequence([1, 2, 3]))
        XCTAssertEqual(events.first?.kind, .damage(amount: 6, type: .poison))
    }

    func testOnlyPotionsHaveEffects() {
        XCTAssertNil(PotionEffect.srd("longsword"))
        XCTAssertNotNil(PotionEffect.srd("potion-of-speed"))
    }
}

final class EffectsOnTheSheetTests: XCTestCase {
    private func fighter(str: Int = 10, dex: Int = 10) -> PlayerCharacter {
        PlayerCharacter(name: "Hero", race: "", characterClass: "", level: 1, classID: "fighter",
                        baseAbilityScores: AbilityScores(str: str, dex: dex))
    }

    private func sheet(_ character: PlayerCharacter, potion: String, round: Int = 0) -> CharacterSheet {
        let events = PotionEffect.srd(potion)!.events(itemName: potion, playerID: "p1", authorID: "p1", round: 0,
                                                      roller: .sequence([2]))
        return CharacterSheet(character: character, combat: CombatState(round: round, events: events))
    }

    func testGiantStrengthSetsStrength() {
        let weak = sheet(fighter(str: 8), potion: "potion-of-hill-giant-strength")
        XCTAssertEqual(weak.abilityScores.str, 21)
        XCTAssertEqual(weak.modifier(.str), 5)
        XCTAssertEqual(weak.attacks.first?.attackBonus, 7, "unarmed strike: +5 Str + 2 proficiency")

        let worn = sheet(fighter(str: 8), potion: "potion-of-hill-giant-strength", round: 600)
        XCTAssertEqual(worn.abilityScores.str, 8, "an hour later it has worn off")
    }

    func testSpeedPotionGivesHaste() {
        let hasted = sheet(fighter(dex: 14), potion: "potion-of-speed")
        XCTAssertEqual(hasted.armorClass, 12 + 2)
        XCTAssertEqual(hasted.speed, 60)
        XCTAssertEqual(hasted.armorClassParts.last?.name, "potion-of-speed")
        XCTAssertEqual(sheet(fighter(dex: 14), potion: "potion-of-speed", round: 10).speed, 30, "1 minute later")
    }

    func testHeroismAddsBlessAndTemporaryHitPoints() {
        let hero = sheet(fighter(), potion: "potion-of-heroism")
        XCTAssertEqual(hero.health.temporary, 10)
        XCTAssertEqual(hero.effectSaveNotes, ["+1d4 (potion-of-heroism)"])
        XCTAssertTrue(hero.attacks.first?.notes.contains("+1d4 to hit (potion-of-heroism)") ?? false)
    }

    func testFlyingAndGrowth() {
        XCTAssertEqual(sheet(fighter(), potion: "potion-of-flying").extraSpeeds, ["Fly 30 ft"])
        let grown = sheet(fighter(), potion: "potion-of-growth")
        XCTAssertTrue(grown.attacks.first?.notes.contains("+1d4 damage (potion-of-growth)") ?? false)
        let shrunk = sheet(fighter(), potion: "potion-of-diminution")
        XCTAssertTrue(shrunk.attacks.first?.notes.contains("−1d4 damage (potion-of-diminution)") ?? false)
        XCTAssertEqual(grown.activeEffects.first?.summary.first, "+1d4 weapon damage")
    }

    func testHealthOnTheSheetUsesMaxHitPoints() {
        let character = fighter()
        let hurt = CharacterSheet(character: character, combat: CombatState(events: [event(.damage(amount: 4, type: .none), at: 1)]))
        XCTAssertEqual(hurt.health.current, hurt.maxHitPoints - 4)
    }
}

/// A DM and two players sharing one directory.
@MainActor
private struct CombatTable {
    let dm: CampaignManager
    let player1: CampaignManager
    let player2: CampaignManager
    let code = "717171"

    init() {
        let directory = InMemoryCampaignDirectory()
        dm = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(),
                             makeCode: { "717171" }, newMemberID: { "dm" })
        player1 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p1" })
        player2 = CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence(), newMemberID: { "p2" })
    }

    func setUp() async throws {
        try await dm.create(name: "Tomb", yourName: "Dana")
        try await player1.join(code: code, yourName: "Sam", character: PlayerCharacter(name: "Aria", race: "", characterClass: ""))
        try await player2.join(code: code, yourName: "Lee", character: PlayerCharacter(name: "Bram", race: "", characterClass: ""))
        await dm.refresh()
    }

    func state(_ manager: CampaignManager, of playerID: String) -> CombatState {
        manager.campaign(code: code)?.combatState(of: playerID) ?? .none
    }
}

@MainActor
final class CampaignCombatTests: XCTestCase {
    func testDMDealsDamageHealsAndGivesTemporaryHitPoints() async throws {
        let table = CombatTable()
        try await table.setUp()
        try await table.dm.giveTemporaryHitPoints(5, to: "p1", inCampaign: table.code)
        try await table.dm.dealDamage(8, type: .fire, to: "p1", inCampaign: table.code)
        try await table.dm.heal(1, for: "p1", inCampaign: table.code)
        await table.player1.refresh()
        let health = table.state(table.player1, of: "p1").health(maxHitPoints: 12)
        XCTAssertEqual(health, HealthState(current: 10, maximum: 12, temporary: 0))
        XCTAssertEqual(table.state(table.player1, of: "p1").events.map(\.note),
                       ["5 temporary HP", "Took 8 fire damage", "Regained 1 HP"])

        try await table.dm.longRest("p1", inCampaign: table.code)
        XCTAssertEqual(table.state(table.dm, of: "p1").health(maxHitPoints: 12).current, 12)
    }

    func testPlayersCantDealDamageOrMoveRounds() async throws {
        let table = CombatTable()
        try await table.setUp()
        await assertThrows(CombatError.onlyDungeonMaster) {
            try await table.player1.dealDamage(3, to: "p2", inCampaign: table.code)
        }
        await assertThrows(CombatError.onlyDungeonMaster) {
            try await table.player1.advanceRounds(inCampaign: table.code)
        }
        await assertThrows(CombatError.invalidAmount) {
            try await table.dm.dealDamage(0, to: "p1", inCampaign: table.code)
        }
        await assertThrows(CampaignError.playerNotFound) {
            try await table.dm.dealDamage(3, to: "nobody", inCampaign: table.code)
        }
    }

    func testDrinkingAPotionUsesItUpAndApplies() async throws {
        let table = CombatTable()
        try await table.setUp()
        try await table.dm.addItem(itemID: "potion-of-healing", name: "Potion of Healing", quantity: 2, to: "p1", inCampaign: table.code)
        try await table.dm.dealDamage(10, to: "p1", inCampaign: table.code)
        await table.player1.refresh()

        try await table.player1.usePotion(itemID: "potion-of-healing", for: "p1", inCampaign: table.code, roller: .sequence([1, 1]))
        XCTAssertEqual(table.player1.campaign(code: table.code)?.inventory(of: "p1").first?.quantity, 1)
        XCTAssertEqual(table.state(table.player1, of: "p1").health(maxHitPoints: 20).current, 14)

        await assertThrows(CombatError.notYourCharacter) {
            try await table.player2.usePotion(itemID: "potion-of-healing", for: "p1", inCampaign: table.code)
        }
        await assertThrows(CampaignError.itemNotInInventory) {
            try await table.player1.usePotion(itemID: "potion-of-speed", for: "p1", inCampaign: table.code)
        }
        await assertThrows(CombatError.cantUseItem) {
            try await table.player1.usePotion(itemID: "rope", for: "p1", inCampaign: table.code)
        }
    }

    func testPotionEffectsCountDownAsTheDMMovesRoundsOn() async throws {
        let table = CombatTable()
        try await table.setUp()
        try await table.dm.addItem(itemID: "potion-of-speed", name: "Potion of Speed", quantity: 1, to: "p1", inCampaign: table.code)
        try await table.dm.advanceRounds(2, inCampaign: table.code)
        await table.player1.refresh()
        try await table.player1.usePotion(itemID: "potion-of-speed", for: "p1", inCampaign: table.code)
        let effect = try XCTUnwrap(table.state(table.player1, of: "p1").activeEffects.first)
        XCTAssertEqual(effect.startRound, 2)

        await table.dm.refresh()
        try await table.dm.advanceRounds(9, inCampaign: table.code)
        XCTAssertEqual(table.state(table.dm, of: "p1").activeEffects.count, 1, "1 round left")
        try await table.dm.advanceRounds(1, inCampaign: table.code)
        XCTAssertEqual(table.dm.campaign(code: table.code)?.round, 12)
        XCTAssertEqual(table.state(table.dm, of: "p1").activeEffects, [])
    }

    func testEndingAnEffectEarly() async throws {
        let table = CombatTable()
        try await table.setUp()
        try await table.dm.addItem(itemID: "potion-of-flying", name: "Potion of Flying", quantity: 1, to: "p1", inCampaign: table.code)
        await table.player1.refresh()
        try await table.player1.usePotion(itemID: "potion-of-flying", for: "p1", inCampaign: table.code)
        let effect = try XCTUnwrap(table.state(table.player1, of: "p1").activeEffects.first)
        try await table.player1.endEffect(effect.id, for: "p1", inCampaign: table.code)
        XCTAssertEqual(table.state(table.player1, of: "p1").activeEffects, [])
    }

    func testStatusReportsOnlySendChanges() async throws {
        let table = CombatTable()
        try await table.setUp()
        let first = try await table.player1.reportStatus(maxHitPoints: 12, armorClass: 15, inCampaign: table.code)
        let same = try await table.player1.reportStatus(maxHitPoints: 12, armorClass: 15, inCampaign: table.code)
        let changed = try await table.player1.reportStatus(maxHitPoints: 12, armorClass: 17, inCampaign: table.code)
        let fromDM = try await table.dm.reportStatus(maxHitPoints: 1, armorClass: 1, inCampaign: table.code)
        XCTAssertNotNil(first)
        XCTAssertNil(same)
        XCTAssertNotNil(changed)
        XCTAssertNil(fromDM, "the DM has no character")
        await table.dm.refresh()
        XCTAssertEqual(table.state(table.dm, of: "p1").lastReport?.armorClass, 17)
    }

    private func assertThrows<E: Error & Equatable>(
        _ expected: E,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Any
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expected, file: file, line: line)
        }
    }
}

final class CombatErrorMessageTests: XCTestCase {
    func testMessages() {
        XCTAssertEqual(CombatError.onlyDungeonMaster.localizedDescription, "Only the Dungeon Master can do that.")
        XCTAssertEqual(CombatError.cantUseItem.localizedDescription, "That item can't be used from here.")
    }
}
