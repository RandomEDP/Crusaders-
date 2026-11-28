#if canImport(PDFKit)
import XCTest
@testable import CrusadersKit

/// Runs the sample D&D Beyond export (Ominakna Thirke, level 4 Sorcerer, 2024 rules) through the importer
/// and checks every value the sheet prints.
final class DDBImportFixtureTests: XCTestCase {
    private static var cached: SheetImport?

    private func imported() throws -> SheetImport {
        if let cached = Self.cached { return cached }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ddb-ominakna-thirke-2024", withExtension: "pdf", subdirectory: "Fixtures"))
        let result = try DDBSheetParser.parse(pdf: Data(contentsOf: url))
        Self.cached = result
        return result
    }

    private var sheet: ImportedSheet { get throws { try imported().sheet } }

    func testReaderFindsTheValueBoxesAndTellsPagesApartByLabel() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ddb-ominakna-thirke-2024", withExtension: "pdf", subdirectory: "Fixtures"))
        let pages = try PDFSheetReader.pages(from: Data(contentsOf: url))
        XCTAssertEqual(pages.count, 5)
        XCTAssertEqual(pages.map(DDBSheetParser.kind(of:)), [.core, .features, .additionalFeatures, .details, .spells])
        XCTAssertEqual(pages[0].value("AC"), "13")
        XCTAssertEqual(pages[0].value("MaxHP"), "30")
    }

    func testIdentity() throws {
        let result = try imported()
        let sheet = result.sheet
        XCTAssertEqual(result.name, "Ominakna Thirke")
        XCTAssertEqual(sheet.classes, [.init(name: "Sorcerer", level: 4, subclass: "Draconic Sorcery")])
        XCTAssertEqual(sheet.species, "Dragonborn")
        XCTAssertEqual(sheet.ancestry, "Black Dragon")
        XCTAssertEqual(sheet.background, "Criminal")
        XCTAssertEqual(sheet.experiencePoints, 6140)
        XCTAssertEqual(sheet.alignment, "Chaotic Evil")
        XCTAssertEqual(sheet.size, "Medium")
        XCTAssertEqual(sheet.playerName, "ethan568238170d")
        XCTAssertEqual(sheet.rulesEdition, "2024")
    }

    func testAbilityScoresAndModifiers() throws {
        let sheet = try sheet
        let expected: [(Ability, Int, Int)] = [(.str, 8, -1), (.dex, 13, 1), (.con, 14, 2), (.int, 10, 0), (.wis, 12, 1), (.cha, 15, 2)]
        XCTAssertEqual(sheet.abilities.count, 6)
        for (ability, score, modifier) in expected {
            XCTAssertEqual(sheet.ability(ability)?.score, score, ability.name)
            XCTAssertEqual(sheet.ability(ability)?.modifier, modifier, ability.name)
        }
    }

    func testSavingThrows() throws {
        let sheet = try sheet
        let expected: [(Ability, Int, Bool)] = [(.str, -1, false), (.dex, 1, false), (.con, 4, true), (.int, 0, false), (.wis, 1, false), (.cha, 4, true)]
        for (ability, bonus, proficient) in expected {
            XCTAssertEqual(sheet.savingThrow(ability)?.bonus, bonus, ability.name)
            XCTAssertEqual(sheet.savingThrow(ability)?.proficient, proficient, ability.name)
        }
    }

    func testCombatNumbers() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.armorClass, 13)
        XCTAssertEqual(sheet.initiative, 3)
        XCTAssertEqual(sheet.speeds, [.init(feet: 30, mode: "Walking")])
        XCTAssertEqual(sheet.maxHitPoints, 30)
        XCTAssertEqual(sheet.hitDice, "4d6")
        XCTAssertEqual(sheet.proficiencyBonus, 2)
    }

    func testSkills() throws {
        let sheet = try sheet
        let expected: [Skill: (Int, ImportedSheet.Proficiency)] = [
            .acrobatics: (1, .none), .animalHandling: (1, .none), .arcana: (0, .none), .athletics: (-1, .none),
            .deception: (4, .proficient), .history: (0, .none), .insight: (1, .none), .intimidation: (4, .proficient),
            .investigation: (0, .none), .medicine: (1, .none), .nature: (0, .none), .perception: (1, .none),
            .performance: (2, .none), .persuasion: (2, .none), .religion: (0, .none), .sleightOfHand: (3, .proficient),
            .stealth: (3, .proficient), .survival: (1, .none)
        ]
        XCTAssertEqual(sheet.skills.count, 18)
        for skill in Skill.allCases {
            let (bonus, proficiency) = try XCTUnwrap(expected[skill])
            XCTAssertEqual(sheet.skill(skill)?.bonus, bonus, skill.name)
            XCTAssertEqual(sheet.skill(skill)?.proficiency, proficiency, skill.name)
        }
        XCTAssertEqual(Set(sheet.skills.filter { $0.proficiency != .none }.map(\.skill)),
                       [.deception, .intimidation, .sleightOfHand, .stealth])
    }

    func testPassivesSensesAndDefenses() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.passivePerception, 11)
        XCTAssertEqual(sheet.passiveInsight, 11)
        XCTAssertEqual(sheet.passiveInvestigation, 10)
        XCTAssertEqual(sheet.senses, ["Darkvision 60 ft."])
        XCTAssertEqual(sheet.resistances, ["Acid"])
        XCTAssertTrue(sheet.immunities.isEmpty)
    }

    func testProficienciesAndLanguages() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.languages, ["Common", "Draconic", "Elvish"])
        XCTAssertEqual(sheet.weaponProficiencies, ["Simple Weapons"])
        XCTAssertEqual(sheet.toolProficiencies, ["Thieves' Tools"])
        XCTAssertTrue(sheet.armorProficiencies.isEmpty)
    }

    func testAttacks() throws {
        let attacks = try sheet.attacks
        XCTAssertEqual(attacks.map(\.name), ["Dagger", "Spear", "Whip", "Ray of Frost", "Unarmed Strike"])
        XCTAssertEqual(attacks.map(\.attackBonus), [3, 1, 1, 4, 1])
        XCTAssertEqual(attacks.map(\.damage), ["1d4+1", "1d6-1", "1d4+1", "1d8", "0"])
        XCTAssertEqual(attacks.map(\.damageType), ["Piercing", "Piercing", "Slashing", "Cold", "Bludgeoning"])
    }

    func testCurrency() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.coins(.gp), 44)
        for coin in [Coin.cp, .sp, .ep, .pp] {
            XCTAssertEqual(sheet.coins(coin), 0, coin.rawValue)
        }
        XCTAssertEqual(sheet.coinPurse.text, "44 gp")
    }

    func testSpellcasting() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.spellcasting, [.init(className: "Sorcerer", ability: .cha, saveDC: 12, attackBonus: 4)])
        XCTAssertEqual(sheet.spellSlots, [.init(level: 1, slots: 4), .init(level: 2, slots: 3)])
        XCTAssertEqual(sheet.slots(atLevel: 1), 4)
        XCTAssertEqual(sheet.slots(atLevel: 2), 3)
    }

    func testSpellsByLevelWithAlwaysPreparedMerged() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.spells(atLevel: 0).map(\.name), ["Acid Splash", "Mage Hand", "Minor Illusion", "Ray of Frost", "Elementalism"])
        XCTAssertEqual(sheet.spells(atLevel: 1).map(\.name),
                       ["Sleep", "Charm Person", "Ice Knife", "Magic Missile", "Ray of Sickness", "False Life", "Chromatic Orb", "Command"])
        XCTAssertEqual(sheet.spells(atLevel: 1).filter(\.alwaysPrepared).map(\.name), ["Chromatic Orb", "Command"])
        XCTAssertEqual(sheet.spells(atLevel: 2).map(\.name), ["Dragon's Breath", "Alter Self"])
        XCTAssertTrue(sheet.spells(atLevel: 2).allSatisfy(\.alwaysPrepared))
        XCTAssertEqual(sheet.spells.filter { $0.name == "Dragon's Breath" }.count, 1)
        XCTAssertEqual(sheet.spells.count, 15)
        XCTAssertTrue(sheet.spells(atLevel: 0).allSatisfy { !$0.alwaysPrepared })
        let ray = try XCTUnwrap(sheet.spells.first { $0.name == "Ray of Frost" })
        XCTAssertEqual(ray.saveOrAttack, "+4")
        XCTAssertEqual(ray.range, "60 ft.")
        XCTAssertEqual(ray.srdID, "ray-of-frost")
    }

    func testResources() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.resources.count, 4)
        let sorcery = try XCTUnwrap(sheet.resource(named: "Sorcery Points"))
        XCTAssertEqual(sorcery.uses, 4)
        XCTAssertEqual(sorcery.recharge, "Long Rest")
        let breath = try XCTUnwrap(sheet.resource(named: "Breath Weapon"))
        XCTAssertEqual(breath.uses, 2)
        XCTAssertEqual(breath.recharge, "Long Rest")
        XCTAssertEqual(breath.saveDC, 12)
        XCTAssertEqual(breath.saveAbility, "Dex")
        XCTAssertEqual(breath.damage, "1d10")
        XCTAssertEqual(breath.damageType, "Acid")
        XCTAssertEqual(breath.detailText, "DC 12 Dex, 1d10 Acid")
        let innate = try XCTUnwrap(sheet.resource(named: "Innate Sorcery"))
        XCTAssertEqual(innate.uses, 2)
        XCTAssertEqual(innate.recharge, "Long Rest")
        let flight = try XCTUnwrap(sheet.resource(named: "Draconic Flight"))
        XCTAssertEqual(flight.uses, 1)
        XCTAssertEqual(flight.recharge, "Long Rest")
    }

    func testFeatsMetamagicAndFeatures() throws {
        let sheet = try sheet
        XCTAssertEqual(sheet.feats, ["Skilled", "Alert"])
        XCTAssertEqual(sheet.metamagic, ["Empowered Spell", "Seeking Spell"])
        let names = sheet.features.map(\.name)
        XCTAssertTrue(names.contains("Font of Magic"))
        XCTAssertTrue(names.contains("Draconic Resilience"))
        XCTAssertTrue(names.contains("Darkvision"))
        let innate = try XCTUnwrap(sheet.features.first { $0.name == "Innate Sorcery" })
        XCTAssertEqual(innate.section, "Sorcerer Features")
        XCTAssertEqual(innate.source, "PHB-2024 140")
        XCTAssertTrue(innate.text.hasPrefix("Twice per Long Rest"))
        XCTAssertEqual(sheet.features.first { $0.name == "Alert" }?.section, "Feats")
    }

    func testEquipmentMergesRepeatedRows() throws {
        let sheet = try sheet
        let expected: [(String, Int)] = [
            ("Dagger", 4), ("Spear", 1), ("Whip", 1), ("Thieves' Tools", 1), ("Rations", 10), ("Torch", 10),
            ("Caltrops", 20), ("Crowbar", 2), ("Pouch", 2), ("Scroll of approval", 2), ("Oil", 2)
        ]
        for (name, quantity) in expected {
            XCTAssertEqual(sheet.equipment(named: name)?.quantity, quantity, name)
        }
        XCTAssertEqual(sheet.equipment.filter { $0.name == "Dagger" }.count, 1)
        XCTAssertEqual(sheet.equipment(named: "Dagger")?.weight, "1 lb.")
        XCTAssertNil(sheet.equipment(named: "Scroll of approval")?.weight)
    }

    func testRawTextIsKeptForReparsing() throws {
        let raw = try sheet.rawText
        XCTAssertTrue(raw.contains("ARMOR"))
        XCTAssertTrue(raw.contains("[MaxHP] 30"))
        XCTAssertTrue(raw.contains("Draconic Flight"))
        XCTAssertTrue(raw.contains("--- Page 5 ---"))
    }

    func testNothingIsMissingFromTheSample() throws {
        let issues = try imported().issues
        XCTAssertEqual(issues, [], issues.map(\.message).joined(separator: "\n"))
    }

    func testCharacterFromImport() throws {
        let character = try imported().makeCharacter()
        XCTAssertEqual(character.name, "Ominakna Thirke")
        XCTAssertEqual(character.race, "Dragonborn")
        XCTAssertEqual(character.characterClass, "Sorcerer")
        XCTAssertEqual(character.classID, "sorcerer")
        XCTAssertNil(character.raceID, "Printed scores already include species bonuses")
        XCTAssertEqual(character.level, 4)
        XCTAssertEqual(character.experiencePoints, 6140)
        XCTAssertEqual(character.baseAbilityScores, AbilityScores(str: 8, dex: 13, con: 14, int: 10, wis: 12, cha: 15))
        XCTAssertEqual(character.skillProficiencies, [.deception, .intimidation, .sleightOfHand, .stealth])
        XCTAssertEqual(character.spellIDs, ["acid-splash", "mage-hand", "minor-illusion", "ray-of-frost", "sleep",
                                            "charm-person", "magic-missile", "false-life", "command", "alter-self"])
        XCTAssertTrue(character.isImported)
        // The printed sheet survives the trip through storage (CD_StoredCharacter's payload).
        let decoded = try CharacterCoding.decode(CharacterCoding.encode(character))
        XCTAssertEqual(decoded.importedSheet, character.importedSheet)
        XCTAssertEqual(decoded, character)
    }
}
#endif
