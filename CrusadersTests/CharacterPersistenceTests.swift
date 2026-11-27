import XCTest
import SwiftData
import CrusadersKit
@testable import Crusaders

@MainActor
final class CharacterPersistenceTests: XCTestCase {
    private func makeStore() throws -> SwiftDataCharacterStore {
        let setup = try CharacterPersistence.inMemory(reason: nil)
        return try XCTUnwrap(setup.store as? SwiftDataCharacterStore)
    }

    private func hero(_ name: String) throws -> PlayerCharacter {
        var draft = CharacterDraft.starter()
        draft.name = name
        return try draft.build()
    }

    // MARK: SwiftData store

    func testSwiftDataStoreSavesAndLoadsInOrder() throws {
        let store = try makeStore()
        let aria = try hero("Aria")
        let bram = try hero("Bram")
        try store.save(aria)
        try store.save(bram)
        XCTAssertEqual(try store.loadCharacters(), [aria, bram])
    }

    func testSwiftDataStoreUpdatesInsteadOfDuplicating() throws {
        let store = try makeStore()
        var aria = try hero("Aria")
        try store.save(aria)
        try aria.addExperience(300)
        try store.save(aria)
        let loaded = try store.loadCharacters()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.level, 2)
        XCTAssertEqual(try store.container.mainContext.fetch(FetchDescriptor<StoredCharacter>()).count, 1)
    }

    func testSwiftDataStoreDeletes() throws {
        let store = try makeStore()
        let aria = try hero("Aria")
        let bram = try hero("Bram")
        try store.save(aria)
        try store.save(bram)
        try store.delete(id: aria.id)
        XCTAssertEqual(try store.loadCharacters(), [bram])
        XCTAssertNoThrow(try store.delete(id: UUID()))
    }

    func testDuplicateRecordsFromTwoDevicesKeepTheNewest() throws {
        let store = try makeStore()
        var aria = try hero("Aria")
        let context = store.container.mainContext
        let older = StoredCharacter(characterID: aria.id, payload: try CharacterCoding.encode(aria), createdAt: Date(timeIntervalSince1970: 100))
        aria.name = "Aria (newer)"
        let newer = StoredCharacter(characterID: aria.id, payload: try CharacterCoding.encode(aria), createdAt: Date(timeIntervalSince1970: 200))
        context.insert(older)
        context.insert(newer)
        try context.save()
        XCTAssertEqual(try store.loadCharacters().map(\.name), ["Aria (newer)"])
    }

    func testUnreadableRecordsAreSkipped() throws {
        let store = try makeStore()
        store.container.mainContext.insert(StoredCharacter(characterID: UUID(), payload: Data("nope".utf8)))
        try store.container.mainContext.save()
        let aria = try hero("Aria")
        try store.save(aria)
        XCTAssertEqual(try store.loadCharacters(), [aria])
    }

    // MARK: Picking a store

    func testInMemoryArgumentKeepsCharactersInMemory() {
        let setup = CharacterPersistence.makeDefault(arguments: [CharacterPersistence.inMemoryArgument], cloudKitEnabled: true)
        XCTAssertEqual(setup.mode, .memory(reason: nil))
    }

    func testWithoutICloudCharactersAreSavedOnTheDevice() {
        let setup = CharacterPersistence.makeDefault(arguments: [], cloudKitEnabled: false)
        XCTAssertEqual(setup.mode, .device)
    }

    func testDebugBuildsOnlyUseICloudWhenAsked() {
        // Tests run a Debug build, so CloudKit stays off without -useCloudKit.
        let setup = CharacterPersistence.makeDefault(arguments: [], cloudKitEnabled: true)
        XCTAssertEqual(setup.mode, .device)
    }

    func testResetArgumentClearsSavedCharacters() throws {
        let first = CharacterPersistence.makeDefault(arguments: [], cloudKitEnabled: false)
        try first.store.save(try hero("Temp"))
        let reset = CharacterPersistence.makeDefault(arguments: [CharacterPersistence.resetArgument], cloudKitEnabled: false)
        XCTAssertEqual(try reset.store.loadCharacters(), [])
    }

    // MARK: App model

    func testModelLoadsSavedCharactersOnStart() throws {
        let aria = try hero("Aria")
        let store = InMemoryCharacterStore(characters: [aria])
        let model = AppModel(characterStore: store)
        XCTAssertEqual(model.roster.characters, [aria])
    }

    func testEveryChangeIsSaved() throws {
        let store = InMemoryCharacterStore()
        let model = AppModel(characterStore: store)
        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        let bram = try model.createCharacter(from: draft)
        XCTAssertEqual(store.characters.map(\.id), [bram.id])

        try model.addExperience(2_700, to: bram.id)
        XCTAssertEqual(store.characters.first?.level, 4)

        model.toggleSpell("fire-bolt", for: bram.id)
        XCTAssertEqual(store.characters.first?.spellIDs, ["fire-bolt"])

        try model.spendImprovementPoint(on: .con, for: bram.id)
        XCTAssertEqual(store.characters.first?.improvementPoints, [.con])

        try model.addCharacter(name: "Quick", race: "", characterClass: "", level: 1)
        XCTAssertEqual(store.characters.count, 2)

        model.deleteCharacters(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(store.characters.map(\.name), ["Quick"])
    }

    func testModelPicksUpChangesFromOtherDevices() throws {
        let store = InMemoryCharacterStore()
        let model = AppModel(characterStore: store)
        try store.save(try hero("From iPad"))
        XCTAssertTrue(model.roster.characters.isEmpty)
        model.reloadCharacters()
        XCTAssertEqual(model.roster.characters.map(\.name), ["From iPad"])
    }

    func testStorageProblemsAreShownNotThrown() throws {
        let store = InMemoryCharacterStore()
        store.failure = CharacterError.characterNotFound
        let model = AppModel(characterStore: store)
        XCTAssertNotNil(model.characterStorageProblem)

        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        XCTAssertNoThrow(try model.createCharacter(from: draft))
        XCTAssertEqual(model.roster.characters.count, 1, "the character still exists for this session")
        XCTAssertNotNil(model.characterStorageProblem)

        store.failure = nil
        model.reloadCharacters()
        XCTAssertNil(model.characterStorageProblem)
    }
}
