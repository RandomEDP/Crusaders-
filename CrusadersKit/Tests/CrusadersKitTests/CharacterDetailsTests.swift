import XCTest
@testable import CrusadersKit

/// Feats, languages, proficiencies, limited uses and lore, kept on every character.
final class CharacterDetailsTests: XCTestCase {
    func testResourcesAreSpentAndComeBackOnTheRightRest() {
        let points = CharacterResource(name: "Sorcery Points", uses: 2)
        let wildShape = CharacterResource(name: "Wild Shape", uses: 1, recharge: "Short Rest")
        var character = PlayerCharacter(name: "A", race: "Elf", characterClass: "Sorcerer", resources: [points, wildShape])

        XCTAssertTrue(character.useResource(points.id))
        XCTAssertTrue(character.useResource(points.id))
        XCTAssertFalse(character.useResource(points.id), "No uses left")
        XCTAssertTrue(character.useResource(wildShape.id))
        XCTAssertEqual(character.resources.map(\.remaining), [0, 0])

        character.restoreResource(points.id)
        XCTAssertEqual(character.resources[0].remaining, 1)

        character.rest(long: false)
        XCTAssertEqual(character.resources.map(\.remaining), [1, 1], "A short rest only restores short-rest uses")
        character.rest(long: true)
        XCTAssertEqual(character.resources.map(\.remaining), [2, 1])
    }

    func testResourceUsesStayInRange() {
        let resource = CharacterResource(name: "X", uses: 2, used: 5)
        XCTAssertEqual(resource.used, 2)
        XCTAssertEqual(CharacterResource(name: "Y", uses: -3).uses, 0)
    }

    func testDetailsAndLoreRoundTripAndOldSavesGetDefaults() throws {
        var character = PlayerCharacter(name: "Omi", race: "Dragonborn", characterClass: "Sorcerer",
                                        background: "Criminal", alignment: "Chaotic Evil",
                                        languages: ["Common", "Draconic"], feats: ["Alert"],
                                        armorProficiencies: ["Light Armor"], weaponProficiencies: ["Simple Weapons"],
                                        toolProficiencies: ["Thieves' Tools"],
                                        resources: [CharacterResource(name: "Breath Weapon", uses: 2, detail: "DC 12 Dex")])
        character.lore.religion = "The Dragon Queen"
        character.lore.bodyShape = "Tall and scaled, with a short tail"
        character.lore.backstory = "Grew up in the sewers."
        let decoded = try CharacterCoding.decode(CharacterCoding.encode(character))
        XCTAssertEqual(decoded, character)
        XCTAssertEqual(decoded.lore.filled.map(\.label), ["Backstory", "Religion", "Body shape"])

        let old = try CharacterCoding.decode(Data(#"{"id":"\#(UUID().uuidString)","name":"Old","lore":{"religion":"Pelor"}}"#.utf8))
        XCTAssertEqual(old.background, "")
        XCTAssertTrue(old.languages.isEmpty)
        XCTAssertTrue(old.resources.isEmpty)
        XCTAssertEqual(old.lore.religion, "Pelor")
        XCTAssertEqual(old.lore.backstory, "")
    }

    func testListFromText() {
        XCTAssertEqual(PlayerCharacter.list(from: "Common, Draconic\n Elvish ,,"), ["Common", "Draconic", "Elvish"])
        XCTAssertEqual(PlayerCharacter.list(from: "  "), [])
    }

    func testImportedDetailsGoIntoLore() {
        var sheet = ImportedSheet()
        sheet.backstory = "Born in a storm."
        sheet.otherDetails = [.init(label: "Faith", text: "Bahamut"), .init(label: "Height", text: "6'2\""),
                              .init(label: "Additional notes", text: "A"), .init(label: "More notes", text: "B")]
        let character = SheetImport(sheet: sheet, name: "Kri", issues: []).makeCharacter()
        XCTAssertEqual(character.lore.backstory, "Born in a storm.")
        XCTAssertEqual(character.lore.religion, "Bahamut")
        XCTAssertEqual(character.lore.height, "6'2\"")
        XCTAssertEqual(character.lore.notes, "A\n\nB")
    }
}
