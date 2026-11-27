import XCTest
@testable import CrusadersKit

final class CharacterRosterTests: XCTestCase {
    func testStartsEmpty() {
        XCTAssertTrue(CharacterRoster().characters.isEmpty)
    }

    func testAddTrimsAndStoresCharacter() throws {
        var roster = CharacterRoster()
        let character = try roster.add(name: "  Aria  ", race: " Elf ", characterClass: "Wizard ", level: 3)
        XCTAssertEqual(character.name, "Aria")
        XCTAssertEqual(character.race, "Elf")
        XCTAssertEqual(character.characterClass, "Wizard")
        XCTAssertEqual(roster.characters, [character])
    }

    func testAddRejectsBlankName() {
        var roster = CharacterRoster()
        XCTAssertThrowsError(try roster.add(name: "   ", race: "", characterClass: "", level: 1)) {
            XCTAssertEqual($0 as? CharacterError, .emptyName)
        }
        XCTAssertTrue(roster.characters.isEmpty)
    }

    func testAddRejectsLevelOutsideOneToTwenty() {
        var roster = CharacterRoster()
        for level in [0, 21, -1] {
            XCTAssertThrowsError(try roster.add(name: "Bob", race: "", characterClass: "", level: level)) {
                XCTAssertEqual($0 as? CharacterError, .levelOutOfRange)
            }
        }
        XCTAssertNoThrow(try roster.add(name: "Min", race: "", characterClass: "", level: 1))
        XCTAssertNoThrow(try roster.add(name: "Max", race: "", characterClass: "", level: 20))
    }

    func testRemoveById() throws {
        var roster = CharacterRoster()
        let a = try roster.add(name: "A", race: "", characterClass: "", level: 1)
        let b = try roster.add(name: "B", race: "", characterClass: "", level: 1)
        roster.remove(id: a.id)
        XCTAssertEqual(roster.characters, [b])
    }

    func testRemoveAtOffsetsIgnoresInvalidIndexes() throws {
        var roster = CharacterRoster()
        try roster.add(name: "A", race: "", characterClass: "", level: 1)
        let b = try roster.add(name: "B", race: "", characterClass: "", level: 1)
        try roster.add(name: "C", race: "", characterClass: "", level: 1)
        roster.remove(atOffsets: IndexSet([0, 2, 9]))
        XCTAssertEqual(roster.characters, [b])
    }

    func testSummary() {
        XCTAssertEqual(PlayerCharacter(name: "Aria", race: "Elf", characterClass: "Wizard", level: 3).summary, "Level 3 Elf Wizard")
        XCTAssertEqual(PlayerCharacter(name: "Nobody", race: "", characterClass: "", level: 1).summary, "Level 1")
    }
}
