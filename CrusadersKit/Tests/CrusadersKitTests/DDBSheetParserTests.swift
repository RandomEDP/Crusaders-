import XCTest
@testable import CrusadersKit

/// Parser rules on hand-made pages: older "RACE" sheets, multiclass, missing sections and the text helpers.
final class DDBSheetParserTests: XCTestCase {
    private func field(_ name: String, _ value: String, y: Double = 0) -> PDFSheetPage.Field {
        PDFSheetPage.Field(name: name, value: value, x: 40, y: y, width: 100, height: 10)
    }

    private func corePage(_ extra: [PDFSheetPage.Field] = [], text: String = "RACE STRENGTH SAVING THROWS SKILLS WEAPON ATTACKS & CANTRIPS") -> PDFSheetPage {
        PDFSheetPage(index: 0, text: text, fields: [
            field("CharacterName", "Copy of Copy Cat"),
            field("CLASS  LEVEL", "Sorcerer 4 / Warlock 1"),
            field("RACE ", "Hill Dwarf"),
            field("STR", "-1"), field("STRmod", "8"),   // printed the wrong way round
            field("DEX", "13"), field("DEXmod ", "+1"),
            field("AC", "15"),
            field("Speed", "25 ft. (Walking), 30 ft. (Flying)"),
            field("Defenses", "Resistances - Fire, Cold\nImmunities - Poison"),
            field("EXPERIENCE POINTS", "--")
        ] + extra)
    }

    func testOlderRaceSheetsMulticlassAndSwappedAbilityPairs() {
        let result = DDBSheetParser.parse(pages: [corePage()])
        XCTAssertEqual(result.name, "Copy Cat")
        XCTAssertEqual(result.sheet.species, "Hill Dwarf")
        XCTAssertEqual(result.sheet.rulesEdition, "2014")
        XCTAssertEqual(result.sheet.classes.map(\.name), ["Sorcerer", "Warlock"])
        XCTAssertEqual(result.sheet.classes.map(\.level), [4, 1])
        XCTAssertEqual(result.sheet.totalLevel, 5)
        XCTAssertEqual(result.sheet.ability(.str)?.score, 8)
        XCTAssertEqual(result.sheet.ability(.str)?.modifier, -1)
        XCTAssertEqual(result.sheet.ability(.dex)?.score, 13)
        XCTAssertEqual(result.sheet.speeds, [.init(feet: 25, mode: "Walking"), .init(feet: 30, mode: "Flying")])
        XCTAssertEqual(result.sheet.resistances, ["Fire", "Cold"])
        XCTAssertEqual(result.sheet.immunities, ["Poison"])
        XCTAssertNil(result.sheet.experiencePoints, "-- means no value, not zero")

        let character = result.makeCharacter()
        XCTAssertEqual(character.level, 5)
        XCTAssertEqual(character.characterClass, "Sorcerer / Warlock")
        XCTAssertEqual(character.classID, "sorcerer")
        XCTAssertEqual(character.experiencePoints, Experience.minimumXP(forLevel: 5))
    }

    func testMissingSectionsAreFlaggedNotFatal() {
        let result = DDBSheetParser.parse(pages: [corePage()])
        let fields = Set(result.issues.map(\.field))
        for field in ["Constitution", "Max HP", "Initiative", "Features", "Coins", "Alignment", "Skills", "Saving throws"] {
            XCTAssertTrue(fields.contains(field), "\(field) should be flagged")
        }
        XCTAssertFalse(fields.contains("Name"))
        XCTAssertFalse(fields.contains("Armor Class"))
        XCTAssertEqual(result.sheet.armorClass, 15)
        XCTAssertTrue(result.sheet.coins.allSatisfy { $0.count == 0 })
    }

    func testNoPagesAtAllStillGivesAnImportToFixUp() {
        let result = DDBSheetParser.parse(pages: [])
        XCTAssertEqual(result.name, "")
        XCTAssertTrue(result.issues.contains { $0.field == "Core sheet" })
        XCTAssertTrue(result.issues.contains { $0.field == "Name" })
        XCTAssertEqual(result.makeCharacter().level, 1)
    }

    func testMismatchedAbilityPairIsUncertain() {
        let page = corePage([field("CON", "14"), field("CONmod", "+5")])
        let result = DDBSheetParser.parse(pages: [page])
        XCTAssertTrue(result.issues.contains { $0.field == "Constitution" && $0.kind == .uncertain })
        XCTAssertEqual(result.sheet.ability(.con)?.score, 14)
        XCTAssertEqual(result.sheet.ability(.con)?.modifier, 2)
    }

    func testExpertiseMarker() {
        let page = corePage([field("Stealth", "+7"), field("StealthProf", "E"), field("Arcana", "+2"), field("ArcanaProf", "P")])
        let sheet = DDBSheetParser.parse(pages: [page]).sheet
        XCTAssertEqual(sheet.skill(.stealth)?.proficiency, .expertise)
        XCTAssertEqual(sheet.skill(.stealth)?.bonus, 7)
        XCTAssertEqual(sheet.skill(.arcana)?.proficiency, .proficient)
    }

    func testPagesAreFoundByLabelsInAnyOrderAndCount() {
        let spells = PDFSheetPage(index: 0, text: "SPELLCASTING ABILITY SPELL SAVE DC PREP SPELL NAME", fields: [
            field("spellHeader0", "=== 3rd LEVEL ===", y: 600), field("spellSlotHeader0", "2 Slots OO", y: 600),
            field("spellPrepared0", "O", y: 580), field("spellName0", "Fireball", y: 580)
        ])
        let core = PDFSheetPage(index: 1, text: corePage().text, fields: corePage().fields)
        let extraFeatures = PDFSheetPage(index: 2, text: "ADDITIONAL FEATURES & TRAITS ADDITIONAL EQUIPMENT", fields: [
            field("FeaturesTraits4", "=== FEATS ===\n* Lucky • PHB 167\n| 3 / Long Rest"),
            field("Eq Name30", "Torch"), field("Eq Qty30", "2")
        ])
        XCTAssertEqual([spells, core, extraFeatures].map(DDBSheetParser.kind(of:)), [.spells, .core, .additionalFeatures])
        let sheet = DDBSheetParser.parse(pages: [spells, core, extraFeatures]).sheet
        XCTAssertEqual(sheet.spells(atLevel: 3).map(\.name), ["Fireball"])
        XCTAssertEqual(sheet.slots(atLevel: 3), 2)
        XCTAssertEqual(sheet.feats, ["Lucky"])
        XCTAssertEqual(sheet.resource(named: "Lucky")?.uses, 3)
        XCTAssertEqual(sheet.equipment(named: "Torch")?.quantity, 2)
    }

    func testPagesWithoutReadableLabelsFallBackToTheirBoxes() {
        let page = PDFSheetPage(index: 0, text: "", fields: [field("STR", "10"), field("AC", "12")])
        XCTAssertEqual(DDBSheetParser.kind(of: page), .core)
        let spells = PDFSheetPage(index: 1, text: "", fields: [field("spellName0", "Light")])
        XCTAssertEqual(DDBSheetParser.kind(of: spells), .spells)
    }

    func testNumbers() {
        XCTAssertEqual(SheetText.number("6,140"), 6140)
        XCTAssertEqual(SheetText.number("+3"), 3)
        XCTAssertEqual(SheetText.number("-1"), -1)
        XCTAssertEqual(SheetText.number("\u{2212}2"), -2)
        XCTAssertEqual(SheetText.number("78 lb."), 78)
        XCTAssertNil(SheetText.number("--"))
        XCTAssertNil(SheetText.number(""))
        XCTAssertNil(SheetText.number("DEX 12"))
    }

    func testScoreAndModifierPairing() {
        XCTAssertEqual(SheetText.scoreAndModifier(15, 2)?.score, 15)
        XCTAssertEqual(SheetText.scoreAndModifier(2, 15)?.score, 15)
        XCTAssertEqual(SheetText.scoreAndModifier(-1, 8)?.score, 8)
        XCTAssertEqual(SheetText.scoreAndModifier(9, -1)?.modifier, -1)
        XCTAssertNil(SheetText.scoreAndModifier(14, 5))
    }

    func testDamageAndSpellHeaders() {
        XCTAssertEqual(SheetText.damage("1d6-1 Piercing").dice, "1d6-1")
        XCTAssertEqual(SheetText.damage("1d6-1 Piercing").type, "Piercing")
        XCTAssertEqual(SheetText.damage("2d6 Fire + 1d6 Cold").type, "Fire + 1d6 Cold")
        XCTAssertNil(SheetText.damage("--").dice)
        XCTAssertEqual(SheetText.spellLevel("=== CANTRIPS ==="), 0)
        XCTAssertEqual(SheetText.spellLevel("=== 1st LEVEL ==="), 1)
        XCTAssertEqual(SheetText.spellLevel("=== 9th LEVEL ==="), 9)
        XCTAssertEqual(SheetText.slotCount("4 Slots OOOO"), 4)
        XCTAssertNil(SheetText.slotCount("(At Will)"))
    }

    func testFeatureText() {
        let text = """
        === WARLOCK FEATURES ===
        * Pact Magic • PHB-2024 153
        * Warlock Subclass • PHB-2024 154
           | Fiend Patron
        * Dark One's Blessing • PHB-2024 158
        Uses equal to 3 times per Short Rest.
        * Fey Step • PHB 23
           | Fey Step (Misty) •
        Teleport.
              | 2 / Short or Long Rest • 1 Bonus Action
           | Fey Step: Teleport: 1 Bonus Action
        """
        let result = FeatureText.parse(text)
        XCTAssertEqual(result.subclasses.first?.0, "Warlock")
        XCTAssertEqual(result.subclasses.first?.1, "Fiend Patron")
        XCTAssertEqual(result.resources.first { $0.name == "Fey Step" }?.uses, 2)
        XCTAssertEqual(result.resources.first { $0.name == "Fey Step" }?.recharge, "Short or Long Rest")
        XCTAssertEqual(result.resources.first { $0.name == "Dark One's Blessing" }?.uses, 3)
        XCTAssertEqual(result.features.first { $0.name == "Fey Step" }?.options, ["Fey Step (Misty)"])
        XCTAssertTrue(result.feats.isEmpty, "Features in a class section aren't feats")
    }

    func testImportedSheetDecodesWithCharacterAndOldCharactersHaveNone() throws {
        var sheet = ImportedSheet(importedAt: Date(timeIntervalSince1970: 1_000))
        sheet.background = "Sage"
        sheet.coins = [.init(coin: .gp, count: 3)]
        let character = PlayerCharacter(name: "A", race: "Elf", characterClass: "Wizard", importedSheet: sheet)
        let decoded = try CharacterCoding.decode(CharacterCoding.encode(character))
        XCTAssertEqual(decoded.importedSheet?.background, "Sage")
        XCTAssertEqual(decoded.importedSheet?.coinPurse.text, "3 gp")

        let old = try CharacterCoding.decode(Data(#"{"id":"\#(UUID().uuidString)","name":"Old"}"#.utf8))
        XCTAssertNil(old.importedSheet)
        XCTAssertFalse(old.isImported)

        // A sheet this version can't read never stops the character loading.
        let broken = try CharacterCoding.decode(Data(#"{"id":"\#(UUID().uuidString)","name":"B","importedSheet":{"source":5}}"#.utf8))
        XCTAssertEqual(broken.name, "B")
        XCTAssertNil(broken.importedSheet)
    }
}
