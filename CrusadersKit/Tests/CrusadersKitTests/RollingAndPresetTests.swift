import XCTest
@testable import CrusadersKit

final class RollingAndPresetTests: XCTestCase {
    private func fighterDraft() -> CharacterDraft {
        var draft = CharacterDraft.starter()
        draft.name = "Hero"
        return draft
    }

    // MARK: Dice

    func testSequenceRollerRepeatsAndClamps() {
        let roller = DiceRoller.sequence([3, 9, 0])
        XCTAssertEqual(roller.roll(3, d: 6), [3, 6, 1])
        XCTAssertEqual(roller.roll(6), 3)
    }

    func testRandomRollerStaysOnTheDie() {
        for _ in 0..<200 {
            XCTAssertTrue((1...8).contains(DiceRoller.random.roll(8)))
        }
    }

    func testAbilityRollDropsTheLowestDie() {
        XCTAssertEqual(AbilityRoll(dice: [6, 1, 4, 5]).total, 15)
        XCTAssertEqual(AbilityRoll(dice: [6, 1, 4, 5]).droppedIndex, 1)
        XCTAssertEqual(AbilityRoll(dice: [2, 2, 2, 2]).total, 6)
        XCTAssertEqual(AbilityRoll.roll(using: .sequence([6, 6, 6, 1])).total, 18)
    }

    // MARK: Point buy

    func testPointBuyCosts() {
        XCTAssertEqual(PointBuy.cost(of: 8), 0)
        XCTAssertEqual(PointBuy.cost(of: 13), 5)
        XCTAssertEqual(PointBuy.cost(of: 15), 9)
        XCTAssertNil(PointBuy.cost(of: 16))
        XCTAssertNil(PointBuy.cost(of: 7))
        XCTAssertEqual(PointBuy.spent(on: AbilityScores.standardArray(order: Ability.allCases)), 27)
    }

    func testPointBuyStaysInBudget() throws {
        var draft = fighterDraft()
        draft.selectAbilityMethod(.pointBuy)
        XCTAssertEqual(draft.pointBuyRemaining, 27)
        XCTAssertEqual(draft.baseAbilityScores.str, 8)
        XCTAssertFalse(draft.canAdjust(.str, by: -1))
        for _ in 0..<10 { draft.adjust(.str, by: 1) }
        XCTAssertEqual(draft.baseAbilityScores.str, 15, "point buy caps at 15")
        XCTAssertEqual(draft.pointBuyRemaining, 18)
        for _ in 0..<10 { draft.adjust(.dex, by: 1) }
        for _ in 0..<10 { draft.adjust(.con, by: 1) }
        XCTAssertEqual(draft.baseAbilityScores.dex, 15)
        XCTAssertEqual(draft.baseAbilityScores.con, 15, "the last 9 points")
        draft.adjust(.wis, by: 1)
        XCTAssertEqual(draft.baseAbilityScores.wis, 8, "no points left")
        XCTAssertEqual(draft.pointBuyRemaining, 0)
        XCTAssertNoThrow(try draft.build())
        draft.adjust(.str, by: -1)
        XCTAssertEqual(draft.pointBuyRemaining, 2)
    }

    func testPointBuyRejectsScoresOverBudget() {
        var draft = fighterDraft()
        draft.selectAbilityMethod(.pointBuy)
        draft.baseAbilityScores = AbilityScores(str: 15, dex: 15, con: 15, int: 10, wis: 8, cha: 8)
        XCTAssertFalse(draft.scoresFollowMethod)
        XCTAssertThrowsError(try draft.build()) { XCTAssertEqual($0 as? CharacterError, .invalidAbilityScore) }
    }

    // MARK: Rolled and standard array

    func testRollingPlacesBestScoresForTheClass() throws {
        var draft = fighterDraft()
        // Six rolls of four dice: totals 18, 16, 13, 10, 9, 7.
        let dice = [6, 6, 6, 1, 6, 5, 5, 2, 5, 4, 4, 1, 4, 3, 3, 2, 3, 3, 3, 1, 3, 2, 2, 1]
        draft.selectAbilityMethod(.rolled, roller: .sequence(dice))
        XCTAssertEqual(draft.abilityMethod, .rolled)
        XCTAssertEqual(draft.abilityRolls.map(\.total), [18, 16, 13, 10, 9, 7])
        XCTAssertEqual(draft.placeableScores, [18, 16, 13, 10, 9, 7])
        XCTAssertEqual(draft.baseAbilityScores.str, 18, "fighters want Strength first")
        XCTAssertEqual(draft.baseAbilityScores.con, 16)
        XCTAssertEqual(draft.baseAbilityScores.int, 7)
        draft.swapScores(.str, .int)
        XCTAssertEqual(draft.baseAbilityScores.str, 7)
        XCTAssertEqual(draft.baseAbilityScores.int, 18)
        XCTAssertNoThrow(try draft.build())

        draft.baseAbilityScores.wis = 18
        XCTAssertThrowsError(try draft.build(), "a score that wasn't rolled")
    }

    func testStandardArrayOnlyAllowsSwaps() throws {
        var draft = fighterDraft()
        XCTAssertEqual(draft.abilityMethod, .standardArray)
        XCTAssertFalse(draft.canAdjust(.str, by: 1))
        draft.adjust(.str, by: 1)
        XCTAssertEqual(draft.baseAbilityScores.str, 15)
        draft.swapScores(.str, .cha)
        XCTAssertEqual(draft.baseAbilityScores.cha, 15)
        XCTAssertNoThrow(try draft.build())
    }

    func testCustomScoresClampToTheBaseRange() throws {
        var draft = fighterDraft()
        draft.selectAbilityMethod(.custom)
        draft.baseAbilityScores.str = 18
        draft.adjust(.str, by: 1)
        XCTAssertEqual(draft.baseAbilityScores.str, 18)
        XCTAssertNoThrow(try draft.build())
    }

    // MARK: Hit points

    func testFixedHitPointsByDefault() throws {
        var draft = fighterDraft()
        draft.level = 3
        let character = try draft.build()
        XCTAssertEqual(character.hitPointMethod, .fixed)
        XCTAssertEqual(CharacterSheet(character: character).maxHitPoints, 12 + 8 + 8)
    }

    func testRolledHitPoints() throws {
        var draft = fighterDraft()
        draft.level = 3
        draft.selectHitPointMethod(.rolled, roller: .sequence([2, 9]))
        XCTAssertEqual(draft.hitPointRolls, [2, 9])
        let character = try draft.build()
        XCTAssertEqual(character.hitPointRolls, [2, 9])
        // Level 1: 10 + 2 Con. Level 2: 2 + 2. Level 3: 9 + 2.
        let sheet = CharacterSheet(character: character)
        XCTAssertEqual(sheet.maxHitPoints, 12 + 4 + 11)
        XCTAssertEqual(sheet.hitPointRoll(forLevel: 3), 9)
        XCTAssertNil(sheet.hitPointRoll(forLevel: 1))
    }

    func testHitPointRollsFollowLevelAndClass() {
        var draft = fighterDraft()
        draft.selectHitPointMethod(.rolled, roller: .sequence([10]))
        XCTAssertTrue(draft.hitPointRolls.isEmpty, "level 1 takes the full die")
        draft.level = 4
        draft.syncHitPointRolls(roller: .sequence([10]))
        XCTAssertEqual(draft.hitPointRolls, [10, 10, 10])
        draft.level = 2
        draft.syncHitPointRolls()
        XCTAssertEqual(draft.hitPointRolls, [10])
        draft.selectClass("wizard", roller: .sequence([10]))
        XCTAssertEqual(draft.hitPointRolls, [6], "rerolled on the wizard's d6")
        draft.selectHitPointMethod(.fixed)
        XCTAssertTrue(draft.hitPointRolls.isEmpty)
    }

    func testMissingHitPointRollsFailTheBuild() {
        var draft = fighterDraft()
        draft.selectHitPointMethod(.rolled)
        draft.level = 3
        XCTAssertThrowsError(try draft.build()) { XCTAssertEqual($0 as? CharacterError, .invalidHitPointRolls) }
    }

    func testLevellingUpRollsTheHitDie() throws {
        var draft = fighterDraft()
        draft.selectHitPointMethod(.rolled)
        var character = try draft.build()
        try character.addExperience(900)
        XCTAssertEqual(character.rollMissingHitPoints(hitDie: 10, roller: .sequence([7, 3])), [7, 3])
        XCTAssertEqual(character.hitPointRolls, [7, 3])
        let summary = LevelUpSummary(character: character, fromLevel: 1)
        XCTAssertEqual(summary.levels.map(\.hitPointRoll), [7, 3])
        XCTAssertEqual(summary.levels.map(\.hitPointIncrease), [9, 5])

        var fixed = try fighterDraft().build()
        try fixed.addExperience(300)
        XCTAssertEqual(fixed.rollMissingHitPoints(hitDie: 10), [])
        XCTAssertNil(LevelUpSummary(character: fixed, fromLevel: 1).levels.first?.hitPointRoll)
    }

    func testHitPointChoicesAreSaved() throws {
        var draft = fighterDraft()
        draft.level = 2
        draft.selectHitPointMethod(.rolled, roller: .sequence([4]))
        let character = try draft.build()
        let decoded = try CharacterCoding.decode(CharacterCoding.encode(character))
        XCTAssertEqual(decoded.hitPointMethod, .rolled)
        XCTAssertEqual(decoded.hitPointRolls, [4])
    }

    // MARK: Presets

    func testEveryClassHasThreeValidPresets() {
        for characterClass in RulesCatalog.srd.classes {
            let presets = characterClass.presets
            XCTAssertEqual(presets.count, 3, characterClass.name)
            XCTAssertEqual(Set(presets.map(\.name)).count, 3, characterClass.name)
            for preset in presets {
                XCTAssertEqual(Set(preset.abilityOrder), Set(Ability.allCases), preset.name)
                XCTAssertEqual(preset.abilityOrder.count, 6, preset.name)
                XCTAssertTrue(Set(preset.skills).isSubset(of: characterClass.skillChoices.from), preset.name)
                XCTAssertEqual(preset.skills.count, characterClass.skillChoices.count, preset.name)
                XCTAssertFalse(preset.summary.isEmpty, preset.name)
            }
        }
    }

    func testApplyingAPresetSetsScoresAndSkills() throws {
        var draft = fighterDraft()
        let archer = try XCTUnwrap(RulesCatalog.srd.characterClass(id: "fighter")?.presets.first { $0.name == "Archer" })
        draft.apply(archer)
        XCTAssertEqual(draft.baseAbilityScores.dex, 15)
        XCTAssertEqual(draft.baseAbilityScores.con, 14)
        XCTAssertEqual(draft.skills, [.perception, .survival])
        XCTAssertNoThrow(try draft.build())
    }

    func testPresetsUseTheRolledScoresWhenRolling() throws {
        var draft = fighterDraft()
        let dice = [6, 6, 6, 1, 6, 5, 5, 2, 5, 4, 4, 1, 4, 3, 3, 2, 3, 3, 3, 1, 3, 2, 2, 1]
        draft.selectAbilityMethod(.rolled, roller: .sequence(dice))
        let archer = try XCTUnwrap(RulesCatalog.srd.characterClass(id: "fighter")?.presets.first { $0.name == "Archer" })
        draft.apply(archer)
        XCTAssertEqual(draft.abilityMethod, .rolled)
        XCTAssertEqual(draft.baseAbilityScores.dex, 18)
        XCTAssertNoThrow(try draft.build())
    }

    func testPresetsWorkWithPointBuy() throws {
        var draft = fighterDraft()
        draft.selectAbilityMethod(.pointBuy)
        let tank = try XCTUnwrap(RulesCatalog.srd.characterClass(id: "fighter")?.presets.first)
        draft.apply(tank)
        XCTAssertEqual(draft.abilityMethod, .pointBuy)
        XCTAssertEqual(draft.pointBuyRemaining, 0)
        XCTAssertNoThrow(try draft.build())
    }

    func testPresetSkillsRespectRacialSkills() throws {
        var draft = fighterDraft()
        draft.selectRace("elf")
        let archer = try XCTUnwrap(RulesCatalog.srd.characterClass(id: "fighter")?.presets.first { $0.name == "Archer" })
        draft.apply(archer)
        XCTAssertEqual(draft.skills, [.survival], "elves already have Perception")
        XCTAssertNoThrow(try draft.build())
    }
}
