import XCTest
@testable import CrusadersKit

final class RulesCatalogTests: XCTestCase {
    private let catalog = RulesCatalog.srd

    func testLoadsEverySRDRaceClassAndSpell() {
        XCTAssertEqual(catalog.races.map(\.name), [
            "Dwarf", "Elf", "Halfling", "Human", "Dragonborn", "Gnome", "Half-Elf", "Half-Orc", "Tiefling"
        ])
        XCTAssertEqual(catalog.classes.map(\.name), [
            "Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk",
            "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"
        ])
        XCTAssertEqual(catalog.spells.count, 319)
    }

    func testSubraces() {
        XCTAssertEqual(catalog.races.flatMap(\.subraces).map(\.name), [
            "Hill Dwarf", "High Elf", "Lightfoot Halfling", "Rock Gnome"
        ])
        XCTAssertEqual(catalog.race(id: "dwarf")?.subrace(id: "hill-dwarf")?.abilityBonuses, [.wis: 1])
    }

    func testRaceDetails() throws {
        let dwarf = try XCTUnwrap(catalog.race(id: "dwarf"))
        XCTAssertEqual(dwarf.speed, 25)
        XCTAssertEqual(dwarf.abilityBonuses, [.con: 2])
        XCTAssertTrue(dwarf.traits.contains { $0.name == "Darkvision" && !$0.description.isEmpty })

        let halfElf = try XCTUnwrap(catalog.race(id: "half-elf"))
        XCTAssertEqual(halfElf.abilityBonusChoice?.count, 2)
        XCTAssertEqual(halfElf.abilityBonusChoice?.bonus, 1)
        XCTAssertFalse(halfElf.abilityBonusChoice?.from.contains(.cha) ?? true)
        XCTAssertEqual(halfElf.extraSkillChoices, 2)
        XCTAssertEqual(catalog.race(id: "elf")?.grantedSkills, [.perception])
        XCTAssertEqual(catalog.race(id: "half-orc")?.grantedSkills, [.intimidation])
    }

    func testEveryClassHasTwentyLevelsAndASubclass() {
        for characterClass in catalog.classes {
            XCTAssertEqual(characterClass.levels.map(\.level), Array(1...20), characterClass.name)
            XCTAssertFalse(characterClass.subclass.name.isEmpty, characterClass.name)
            XCTAssertFalse(characterClass.subclass.features.isEmpty, characterClass.name)
            XCTAssertEqual(characterClass.savingThrows.count, 2, characterClass.name)
            XCTAssertFalse(characterClass.skillChoices.from.isEmpty, characterClass.name)
            XCTAssertEqual(Set(characterClass.suggestedAbilityOrder).count, 6, characterClass.name)
        }
    }

    func testClassDetails() throws {
        let fighter = try XCTUnwrap(catalog.characterClass(id: "fighter"))
        XCTAssertEqual(fighter.hitDie, 10)
        XCTAssertEqual(fighter.savingThrows, [.str, .con])
        XCTAssertEqual(fighter.subclass.name, "Champion")
        XCTAssertEqual(fighter.subclassLevel, 3)
        XCTAssertNil(fighter.spellcastingAbility)

        let wizard = try XCTUnwrap(catalog.characterClass(id: "wizard"))
        XCTAssertEqual(wizard.spellcastingAbility, .int)
        XCTAssertEqual(wizard.level(1)?.spellSlots, [2, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(wizard.level(5)?.highestSpellLevel, 3)
        XCTAssertEqual(wizard.level(1)?.cantripsKnown, 3)

        let cleric = try XCTUnwrap(catalog.characterClass(id: "cleric"))
        XCTAssertEqual(cleric.subclassLevel, 1)
        XCTAssertEqual(cleric.subclass.bonusSpellIDs(atLevel: 1), ["bless", "cure-wounds"])
        XCTAssertEqual(cleric.subclass.bonusSpellIDs(upToLevel: 3).count, 4)
    }

    func testAbilityScoreImprovementLevels() {
        XCTAssertEqual(catalog.characterClass(id: "wizard")?.levels.filter(\.abilityScoreImprovement).map(\.level), [4, 8, 12, 16, 19])
        XCTAssertEqual(catalog.characterClass(id: "fighter")?.levels.filter(\.abilityScoreImprovement).map(\.level), [4, 6, 8, 12, 14, 16, 19])
    }

    func testSpellDetails() throws {
        let fireball = try XCTUnwrap(catalog.spell(id: "fireball"))
        XCTAssertEqual(fireball.level, 3)
        XCTAssertEqual(fireball.school, "Evocation")
        XCTAssertEqual(fireball.subtitle, "3rd-level evocation")
        XCTAssertEqual(fireball.components, ["V", "S", "M"])
        XCTAssertNotNil(fireball.higherLevel)
        XCTAssertEqual(Set(fireball.classes), ["sorcerer", "wizard"])
        XCTAssertEqual(catalog.spell(id: "fire-bolt")?.subtitle, "Evocation cantrip")
        XCTAssertNil(catalog.spell(id: "not-a-spell"))
    }

    func testSpellsAreSortedByLevelThenName() {
        let keys = catalog.spells.map { "\($0.level)-\($0.name)" }
        let sorted = catalog.spells.sorted { ($0.level, $0.name) < ($1.level, $1.name) }.map { "\($0.level)-\($0.name)" }
        XCTAssertEqual(keys, sorted)
    }

    func testEverySpellReferenceResolves() {
        let classIDs = Set(catalog.classes.map(\.id))
        for spell in catalog.spells {
            XCTAssertFalse(spell.classes.isEmpty, spell.name)
            XCTAssertTrue(Set(spell.classes).isSubset(of: classIDs), spell.name)
            XCTAssertTrue((0...9).contains(spell.level), spell.name)
        }
        for characterClass in catalog.classes {
            for ids in characterClass.subclass.bonusSpells.values {
                XCTAssertEqual(catalog.spells(ids: ids).count, ids.count, characterClass.subclass.name)
            }
        }
    }

    func testSpellsForClassFiltersByLevel() {
        let wizardLowLevel = catalog.spells(forClass: "wizard", levels: 0...1)
        XCTAssertTrue(wizardLowLevel.contains { $0.id == "magic-missile" })
        XCTAssertTrue(wizardLowLevel.contains { $0.id == "fire-bolt" })
        XCTAssertFalse(wizardLowLevel.contains { $0.id == "fireball" })
        XCTAssertFalse(catalog.spells(forClass: "fighter").contains { _ in true })
    }

    func testSpellLabels() {
        XCTAssertEqual(Spell.label(forLevel: 0), "Cantrips")
        XCTAssertEqual(Spell.label(forLevel: 2), "2nd level")
        XCTAssertEqual(Spell.ordinal(1), "1st")
        XCTAssertEqual(Spell.ordinal(3), "3rd")
        XCTAssertEqual(Spell.ordinal(9), "9th")
    }

    func testAttributionNamesTheSRDAndLicence() {
        XCTAssertTrue(RulesCatalog.srdAttribution.contains("System Reference Document 5.1"))
        XCTAssertTrue(RulesCatalog.srdAttribution.contains("Creative Commons Attribution 4.0"))
    }

    func testCustomJSONCatalog() throws {
        let catalog = try RulesCatalog(racesJSON: "[]", classesJSON: "[]", spellsJSON: "[]")
        XCTAssertTrue(catalog.races.isEmpty)
        XCTAssertThrowsError(try RulesCatalog(racesJSON: "nope", classesJSON: "[]", spellsJSON: "[]"))
    }
}
