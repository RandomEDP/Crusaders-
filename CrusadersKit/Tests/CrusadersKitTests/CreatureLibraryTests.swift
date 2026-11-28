import XCTest
@testable import CrusadersKit

@MainActor
final class CreatureLibraryTests: XCTestCase {
    private func makeLibrary(creator: Bool, store: InMemoryCreatureStore = InMemoryCreatureStore()) throws -> CreatureLibrary {
        CreatureLibrary(baseCreatures: try SRDCreatures.load(), store: store, creatorAccess: FixedCreatorAccess(isCreator: creator))
    }

    private func newCreature(_ name: String) -> Creature {
        var c = Creature.newCustom()
        c.name = name
        return c
    }

    func testRefreshLoadsSavedCreaturesAndCreatorStatus() async throws {
        var edited = try XCTUnwrap(try SRDCreatures.load().first { $0.id == "goblin" })
        edited.name = "Goblin Boss Man"
        let store = InMemoryCreatureStore(creatures: [edited, newCreature("Mire Toad")])
        let library = try makeLibrary(creator: true, store: store)
        XCTAssertFalse(library.isCreator)

        await library.refresh()
        XCTAssertTrue(library.isCreator)
        XCTAssertEqual(library.catalog.creature(id: "goblin")?.name, "Goblin Boss Man")
        XCTAssertEqual(library.catalog.customCreatures.map(\.name), ["Mire Toad"])
        XCTAssertNil(library.syncError)
    }

    func testCreatorAddsANewCreature() async throws {
        let store = InMemoryCreatureStore()
        let library = try makeLibrary(creator: true, store: store)
        await library.refresh()

        let saved = try await library.save(newCreature("  Ember Imp "))
        XCTAssertEqual(saved.name, "Ember Imp")
        XCTAssertEqual(library.catalog.creature(id: saved.id)?.name, "Ember Imp")
        XCTAssertTrue(library.catalog.isCustom(saved.id))
        let stored = try await store.loadCreatures()
        XCTAssertEqual(stored.map(\.id), [saved.id])
    }

    func testCreatorEditsAnSRDCreatureAndResetsIt() async throws {
        let store = InMemoryCreatureStore()
        let library = try makeLibrary(creator: true, store: store)
        await library.refresh()

        var owlbear = try XCTUnwrap(library.catalog.creature(id: "owlbear"))
        owlbear.hitPoints = 80
        try await library.save(owlbear)
        XCTAssertTrue(library.catalog.isEdited("owlbear"))
        let afterEdit = try await store.loadCreatures()
        XCTAssertEqual(afterEdit.count, 1)

        try await library.remove(id: "owlbear")
        XCTAssertEqual(library.catalog.creature(id: "owlbear")?.hitPoints, 59)
        let afterReset = try await store.loadCreatures()
        XCTAssertTrue(afterReset.isEmpty)
    }

    func testSavingAnUnchangedSRDCreatureClearsTheEdit() async throws {
        let store = InMemoryCreatureStore()
        let library = try makeLibrary(creator: true, store: store)
        await library.refresh()
        var goblin = try XCTUnwrap(library.catalog.creature(id: "goblin"))
        goblin.hitPoints = 9
        try await library.save(goblin)
        goblin.hitPoints = 7
        try await library.save(goblin)
        XCTAssertFalse(library.catalog.isEdited("goblin"))
        let stored = try await store.loadCreatures()
        XCTAssertTrue(stored.isEmpty)
    }

    func testCreatorDeletesTheirOwnCreature() async throws {
        let library = try makeLibrary(creator: true)
        await library.refresh()
        let saved = try await library.save(newCreature("Gloom Moth"))
        try await library.remove(id: saved.id)
        XCTAssertNil(library.catalog.creature(id: saved.id))
    }

    func testPlayersCannotAddEditOrDelete() async throws {
        let store = InMemoryCreatureStore()
        let library = try makeLibrary(creator: false, store: store)
        await library.refresh()
        do {
            try await library.save(newCreature("Sneaky"))
            XCTFail("players can't add")
        } catch {
            XCTAssertEqual(error as? CreatureLibraryError, .notCreator)
        }
        do {
            try await library.remove(id: "goblin")
            XCTFail("players can't reset")
        } catch {
            XCTAssertEqual(error as? CreatureLibraryError, .notCreator)
        }
        let saves = await store.saveCount
        XCTAssertEqual(saves, 0)
    }

    func testRejectsUnknownNonCustomIdsAndInvalidCreatures() async throws {
        let library = try makeLibrary(creator: true)
        await library.refresh()
        var stranger = Creature.newCustom(id: "not-in-srd")
        stranger.name = "Stranger"
        do {
            try await library.save(stranger)
            XCTFail("unknown id")
        } catch {
            XCTAssertEqual(error as? CreatureLibraryError, .unknownCreature)
        }
        do {
            try await library.save(newCreature(""))
            XCTFail("empty name")
        } catch {
            XCTAssertEqual(error as? CreatureValidationError, .emptyName)
        }
    }

    func testLoadFailureKeepsBuiltInCreaturesAndShowsBanner() async throws {
        let library = CreatureLibrary(baseCreatures: try SRDCreatures.load(), store: FailingCreatureStore(),
                                      creatorAccess: FixedCreatorAccess(isCreator: true))
        await library.refresh()
        XCTAssertNotNil(library.syncError)
        XCTAssertEqual(library.catalog.count, 334)
        do {
            try await library.save(newCreature("Doomed"))
            XCTFail("save should fail")
        } catch {
            XCTAssertEqual(error as? CreatureLibraryError, .saveFailed)
        }
    }
}

private struct FailingCreatureStore: CreatureStore {
    struct Failure: Error {}
    func loadCreatures() async throws -> [Creature] { throw Failure() }
    func save(_ creature: Creature) async throws { throw Failure() }
    func remove(creatureID: String) async throws { throw Failure() }
}
