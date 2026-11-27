import XCTest
@testable import CrusadersKit

final class CharacterSheetAndLevelUpTests: XCTestCase {
    private func character(race: String, subrace: String? = nil, characterClass: String, level: Int = 1) throws -> PlayerCharacter {
        var draft = CharacterDraft(name: "Hero", level: level)
        draft.selectRace(race)
        if let subrace { draft.selectSubrace(subrace) }
        draft.selectClass(characterClass)
        draft.useStandardArray()
        return try draft.build()
    }

    // MARK: Sheet

    func testHillDwarfFighterSheet() throws {
        let sheet = CharacterSheet(character: try character(race: "dwarf", characterClass: "fighter"))
        XCTAssertEqual(sheet.abilityScores.con, 16)
        XCTAssertEqual(sheet.abilityScores.wis, 13)
        XCTAssertEqual(sheet.racialBonuses, [.con: 2, .wis: 1])
        XCTAssertEqual(sheet.proficiencyBonus, 2)
        XCTAssertEqual(sheet.maxHitPoints, 14, "10 + 3 Con + 1 Dwarven Toughness")
        XCTAssertEqual(sheet.hitPoints(atLevel: 2), 24)
        XCTAssertEqual(sheet.speed, 25)
        XCTAssertEqual(sheet.initiative, 1)
        XCTAssertTrue(sheet.isProficient(save: .str))
        XCTAssertEqual(sheet.savingThrow(.str), 4)
        XCTAssertEqual(sheet.savingThrow(.dex), 1)
        XCTAssertTrue(sheet.traits.contains { $0.name == "Dwarven Toughness" })
        XCTAssertEqual(sheet.features.map(\.rule.name), ["Fighting Style", "Second Wind"])
        XCTAssertFalse(sheet.canCastSpells)
        XCTAssertTrue(sheet.learnableSpells.isEmpty)
        XCTAssertNil(sheet.spellSaveDC)
        XCTAssertFalse(sheet.hasSubclass)
    }

    func testSkillModifiersAddProficiency() throws {
        var built = try character(race: "human", characterClass: "rogue")
        built.skillProficiencies = [.stealth]
        let sheet = CharacterSheet(character: built)
        XCTAssertEqual(sheet.abilityScores.dex, 16)
        XCTAssertEqual(sheet.skillModifier(.stealth), 5)
        XCTAssertEqual(sheet.skillModifier(.acrobatics), 3)
        XCTAssertEqual(sheet.passivePerception, 10 + sheet.skillModifier(.perception))
        XCTAssertEqual(sheet.counters.map(\.name), ["Sneak attack"])
        XCTAssertEqual(sheet.counters.first?.value, "1d6")
    }

    func testHighElfWizardSpellcasting() throws {
        let sheet = CharacterSheet(character: try character(race: "elf", characterClass: "wizard"))
        XCTAssertEqual(sheet.abilityScores.int, 16)
        XCTAssertEqual(sheet.spellcastingAbility, .int)
        XCTAssertEqual(sheet.spellSaveDC, 13)
        XCTAssertEqual(sheet.spellAttackBonus, 5)
        XCTAssertEqual(sheet.cantripLimit, 3)
        XCTAssertEqual(sheet.spellSlots.first, 2)
        XCTAssertEqual(sheet.highestSpellLevel, 1)
        XCTAssertTrue(sheet.canCastSpells)
        let learnable = Set(sheet.learnableSpells.map(\.id))
        XCTAssertTrue(learnable.contains("fire-bolt"))
        XCTAssertTrue(learnable.contains("magic-missile"))
        XCTAssertFalse(learnable.contains("fireball"))
        XCTAssertEqual(sheet.maxHitPoints, 8)
    }

    func testKnownSpells() throws {
        var wizard = try character(race: "human", characterClass: "wizard")
        wizard.toggleSpell("magic-missile")
        wizard.toggleSpell("fire-bolt")
        wizard.toggleSpell("shield")
        wizard.toggleSpell("shield")
        let sheet = CharacterSheet(character: wizard)
        XCTAssertEqual(sheet.knownSpells.map(\.id), ["fire-bolt", "magic-missile"])
        XCTAssertEqual(sheet.knownCantripCount, 1)
        XCTAssertEqual(sheet.knownLeveledSpellCount, 1)
    }

    func testPaladinGetsSpellsAtLevelTwo() throws {
        XCTAssertFalse(CharacterSheet(character: try character(race: "human", characterClass: "paladin")).canCastSpells)
        let level2 = CharacterSheet(character: try character(race: "human", characterClass: "paladin", level: 2))
        XCTAssertTrue(level2.canCastSpells)
        XCTAssertTrue(level2.learnableSpells.allSatisfy { $0.level == 1 })
        XCTAssertFalse(level2.learnableSpells.isEmpty)
    }

    func testClericDomainSpells() throws {
        let cleric = CharacterSheet(character: try character(race: "human", characterClass: "cleric", level: 3))
        XCTAssertTrue(cleric.hasSubclass)
        XCTAssertEqual(Set(cleric.subclassSpells.map(\.id)), ["bless", "cure-wounds", "lesser-restoration", "spiritual-weapon"])
    }

    func testLevelProgress() throws {
        var hero = try character(race: "human", characterClass: "fighter")
        XCTAssertEqual(CharacterSheet(character: hero).levelProgress, 0)
        try hero.addExperience(150)
        XCTAssertEqual(CharacterSheet(character: hero).levelProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(CharacterSheet(character: hero).nextLevelXP, 300)
        try hero.addExperience(400_000)
        XCTAssertEqual(CharacterSheet(character: hero).levelProgress, 1)
        XCTAssertNil(CharacterSheet(character: hero).nextLevelXP)
    }

    func testCharacterWithoutRulesStillHasASheet() {
        let legacy = PlayerCharacter(name: "Old", race: "Elf", characterClass: "Wizard", level: 5)
        let sheet = CharacterSheet(character: legacy)
        XCTAssertNil(sheet.characterClass)
        XCTAssertEqual(sheet.proficiencyBonus, 3)
        XCTAssertEqual(sheet.maxHitPoints, 8 + 5 * 4)
        XCTAssertTrue(sheet.features.isEmpty)
        XCTAssertEqual(legacy.experiencePoints, 6_500)
    }

    // MARK: Experience

    func testAddExperienceLevelsUp() throws {
        var hero = try character(race: "human", characterClass: "fighter")
        XCTAssertNil(try hero.addExperience(299))
        XCTAssertEqual(hero.level, 1)
        XCTAssertEqual(try hero.addExperience(1), 2...2)
        XCTAssertEqual(try hero.addExperience(6_200), 3...5)
        XCTAssertEqual(hero.level, 5)
        XCTAssertEqual(hero.experiencePoints, 6_500)
    }

    func testAddExperienceRejectsZeroAndNegative() throws {
        var hero = try character(race: "human", characterClass: "fighter")
        for amount in [0, -100] {
            XCTAssertThrowsError(try hero.addExperience(amount)) {
                XCTAssertEqual($0 as? CharacterError, .invalidExperience)
            }
        }
        XCTAssertEqual(hero.experiencePoints, 0)
    }

    func testLevelNeverGoesDown() throws {
        var hero = PlayerCharacter(name: "A", race: "", characterClass: "", level: 5, experiencePoints: 0)
        XCTAssertNil(try hero.addExperience(10))
        XCTAssertEqual(hero.level, 5)
    }

    // MARK: Ability Score Improvements

    func testSpendingImprovementPoints() throws {
        var fighter = try character(race: "human", characterClass: "fighter")
        XCTAssertThrowsError(try fighter.spendImprovementPoint(on: .str)) {
            XCTAssertEqual($0 as? CharacterError, .noImprovementPoints)
        }
        try fighter.addExperience(Experience.minimumXP(forLevel: 4))
        XCTAssertEqual(CharacterSheet(character: fighter).unspentImprovementPoints, 2)
        try fighter.spendImprovementPoint(on: .str)
        try fighter.spendImprovementPoint(on: .str)
        let sheet = CharacterSheet(character: fighter)
        XCTAssertEqual(sheet.abilityScores.str, 18)
        XCTAssertEqual(sheet.unspentImprovementPoints, 0)
        XCTAssertThrowsError(try fighter.spendImprovementPoint(on: .dex))
    }

    func testImprovementPointsStopAtTwenty() throws {
        var fighter = try character(race: "human", characterClass: "fighter", level: 4)
        fighter.baseAbilityScores.str = 18
        try fighter.spendImprovementPoint(on: .str)
        XCTAssertEqual(CharacterSheet(character: fighter).abilityScores.str, 20)
        XCTAssertThrowsError(try fighter.spendImprovementPoint(on: .str)) {
            XCTAssertEqual($0 as? CharacterError, .abilityAtMaximum)
        }
        XCTAssertNoThrow(try fighter.spendImprovementPoint(on: .dex))
    }

    // MARK: Level-up summary

    func testWizardLevelOneToFiveUnlocks() throws {
        var wizard = try character(race: "human", characterClass: "wizard")
        try wizard.addExperience(6_500)
        let summary = LevelUpSummary(character: wizard, fromLevel: 1)
        XCTAssertEqual(summary.fromLevel, 1)
        XCTAssertEqual(summary.toLevel, 5)
        XCTAssertEqual(summary.levels.map(\.level), [2, 3, 4, 5])

        let level2 = summary.levels[0]
        XCTAssertEqual(level2.subclass?.name, "Evocation")
        XCTAssertFalse(level2.features.isEmpty)
        XCTAssertTrue(level2.features.contains { $0.source == "Evocation" })
        XCTAssertEqual(level2.hitPointIncrease, 6, "d6 fixed 4 + 2 Con")

        XCTAssertEqual(summary.levels[1].newSpellLevel, 2)
        XCTAssertEqual(summary.levels[2].abilityScoreImprovement, true)
        XCTAssertEqual(summary.levels[2].cantripsGained, 1)

        let level5 = summary.levels[3]
        XCTAssertEqual(level5.proficiencyBonus, 3)
        XCTAssertEqual(level5.newSpellLevel, 3)
        XCTAssertTrue(level5.newlyAvailableSpells.contains { $0.id == "fireball" })
        XCTAssertTrue(level5.newlyAvailableSpells.allSatisfy { $0.level == 3 })
        XCTAssertTrue(level5.spellSlotChanges.contains(LevelUpChange(name: "3rd-level slots", from: "0", to: "2")))
    }

    func testFighterUnlocksFeaturesAndSubclass() throws {
        var fighter = try character(race: "human", characterClass: "fighter")
        try fighter.addExperience(900)
        let summary = LevelUpSummary(character: fighter, fromLevel: 1)
        XCTAssertEqual(summary.levels[0].features.map(\.rule.name), ["Action Surge (1 use)"])
        XCTAssertNil(summary.levels[0].subclass)
        XCTAssertEqual(summary.levels[1].subclass?.name, "Champion")
        XCTAssertTrue(summary.levels[1].features.contains { $0.rule.name == "Improved Critical" })
        XCTAssertTrue(summary.levels[0].newlyAvailableSpells.isEmpty)
    }

    func testRogueCounterChanges() throws {
        var rogue = try character(race: "human", characterClass: "rogue", level: 2)
        try rogue.addExperience(Experience.minimumXP(forLevel: 3) - rogue.experiencePoints)
        let level3 = try XCTUnwrap(LevelUpSummary(character: rogue, fromLevel: 2).levels.first)
        XCTAssertTrue(level3.counterChanges.contains(LevelUpChange(name: "Sneak attack", from: "1d6", to: "2d6")))
    }

    func testClericGainsDomainSpellsAtThree() throws {
        var cleric = try character(race: "human", characterClass: "cleric", level: 2)
        try cleric.addExperience(Experience.minimumXP(forLevel: 3) - cleric.experiencePoints)
        let level3 = try XCTUnwrap(LevelUpSummary(character: cleric, fromLevel: 2).levels.first)
        XCTAssertEqual(Set(level3.subclassSpells.map(\.id)), ["lesser-restoration", "spiritual-weapon"])
    }

    func testPaladinUnlocksFirstLevelSpellsAtTwo() throws {
        var paladin = try character(race: "human", characterClass: "paladin")
        try paladin.addExperience(300)
        let level2 = try XCTUnwrap(LevelUpSummary(character: paladin, fromLevel: 1).levels.first)
        XCTAssertEqual(level2.newSpellLevel, 1)
        XCTAssertTrue(level2.newlyAvailableSpells.contains { $0.id == "bless" })
    }

    func testCharacterWithoutRulesOnlyGainsHitPoints() {
        let legacy = PlayerCharacter(name: "Old", race: "", characterClass: "", level: 2)
        let summary = LevelUpSummary(character: legacy, fromLevel: 1)
        XCTAssertEqual(summary.levels.count, 1)
        XCTAssertEqual(summary.levels[0].hitPointIncrease, 5)
        XCTAssertTrue(summary.levels[0].isHitPointsOnly)
    }

    func testNoLevelsWhenNothingWasGained() throws {
        let hero = try character(race: "human", characterClass: "fighter")
        XCTAssertTrue(LevelUpSummary(character: hero, fromLevel: 1).levels.isEmpty)
    }
}
