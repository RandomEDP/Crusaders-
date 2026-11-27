import XCTest
@testable import CrusadersKit

@MainActor
final class CharacterStoreTests: XCTestCase {
    private func wizard() throws -> PlayerCharacter {
        var draft = CharacterDraft(name: "Aria")
        draft.selectRace("elf")
        draft.selectClass("wizard")
        draft.useStandardArray()
        draft.toggleSkill(.arcana)
        var character = try draft.build()
        character.toggleSpell("fire-bolt")
        try character.addExperience(900)
        return character
    }

    func testEncodingRoundTripsEveryField() throws {
        let original = try wizard()
        let decoded = try CharacterCoding.decode(CharacterCoding.encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.level, 3)
        XCTAssertEqual(decoded.spellIDs, ["fire-bolt"])
        XCTAssertEqual(decoded.subraceID, "high-elf")
    }

    func testOldSavesWithMissingFieldsStillLoad() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Old","race":"Elf","characterClass":"Wizard","level":4}"#
        let character = try CharacterCoding.decode(Data(json.utf8))
        XCTAssertEqual(character.id, id)
        XCTAssertEqual(character.summary, "Level 4 Elf Wizard")
        XCTAssertEqual(character.experiencePoints, Experience.minimumXP(forLevel: 4))
        XCTAssertEqual(character.baseAbilityScores, AbilityScores())
        XCTAssertTrue(character.spellIDs.isEmpty)
        XCTAssertNil(character.classID)
    }

    func testDecodingClampsLevelAndNeedsAnID() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Odd","level":99}"#
        XCTAssertEqual(try CharacterCoding.decode(Data(json.utf8)).level, 20)
        XCTAssertThrowsError(try CharacterCoding.decode(Data(#"{"name":"No id"}"#.utf8)))
    }

    func testInMemoryStoreSavesReplacesAndDeletes() throws {
        let store = InMemoryCharacterStore()
        var hero = try wizard()
        try store.save(hero)
        hero.name = "Aria the Bold"
        try store.save(hero)
        let other = PlayerCharacter(name: "Bram", race: "", characterClass: "")
        try store.save(other)
        XCTAssertEqual(try store.loadCharacters().map(\.name), ["Aria the Bold", "Bram"])
        try store.delete(id: hero.id)
        XCTAssertEqual(try store.loadCharacters(), [other])
    }

    func testInMemoryStoreCanFail() {
        let store = InMemoryCharacterStore()
        store.failure = CharacterError.characterNotFound
        XCTAssertThrowsError(try store.loadCharacters())
        XCTAssertThrowsError(try store.save(PlayerCharacter(name: "A", race: "", characterClass: "")))
        XCTAssertThrowsError(try store.delete(id: UUID()))
    }
}
