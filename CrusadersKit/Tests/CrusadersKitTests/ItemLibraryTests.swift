import XCTest
@testable import CrusadersKit

private struct FailingStore: ItemOverrideStore {
    struct Failure: Error {}
    func loadOverrides() async throws -> [EquipmentItem] { throw Failure() }
    func save(_ item: EquipmentItem) async throws { throw Failure() }
    func remove(itemID: String) async throws { throw Failure() }
}

@MainActor
final class ItemLibraryTests: XCTestCase {
    private let club = EquipmentItem(id: "club", name: "Club", category: .weapons, group: "Simple Melee",
                                     weapon: WeaponStats(damage: "1d4", damageType: .bludgeoning))

    private func makeLibrary(creator: Bool, store: ItemOverrideStore = InMemoryItemOverrideStore()) async -> ItemLibrary {
        let library = ItemLibrary(baseItems: [club], store: store, creatorAccess: FixedCreatorAccess(isCreator: creator))
        await library.refresh()
        return library
    }

    func testRefreshLoadsCreatorEditsAndStatus() async {
        var edited = club
        edited.name = "Big Club"
        let library = await makeLibrary(creator: false, store: InMemoryItemOverrideStore(overrides: [edited]))
        XCTAssertEqual(library.catalog.item(id: "club")?.name, "Big Club")
        XCTAssertFalse(library.isCreator)
        XCTAssertNil(library.syncError)
        XCTAssertFalse(library.isLoading)
    }

    func testPlayersCannotEdit() async {
        let library = await makeLibrary(creator: false)
        var edited = club
        edited.name = "Hacked"
        do {
            try await library.save(edited)
            XCTFail("expected notCreator")
        } catch {
            XCTAssertEqual(error as? ItemLibraryError, .notCreator)
        }
        XCTAssertEqual(library.catalog.item(id: "club")?.name, "Club")
        do {
            try await library.revert(id: "club")
            XCTFail("expected notCreator")
        } catch {
            XCTAssertEqual(error as? ItemLibraryError, .notCreator)
        }
    }

    func testCreatorEditIsSavedAndShared() async throws {
        let store = InMemoryItemOverrideStore()
        let library = await makeLibrary(creator: true, store: store)
        var edited = club
        edited.weapon?.damage = "1d6"
        edited.name = " Spiked Club "
        let saved = try await library.save(edited)
        XCTAssertEqual(saved.name, "Spiked Club")
        XCTAssertEqual(library.catalog.item(id: "club")?.weapon?.damage, "1d6")

        // A second device (another player) picks up the edit.
        let other = await makeLibrary(creator: false, store: store)
        XCTAssertEqual(other.catalog.item(id: "club")?.name, "Spiked Club")
    }

    func testSavingOriginalValuesClearsTheEdit() async throws {
        var edited = club
        edited.name = "Big Club"
        let store = InMemoryItemOverrideStore(overrides: [edited])
        let library = await makeLibrary(creator: true, store: store)
        try await library.save(club)
        XCTAssertFalse(library.catalog.isEdited("club"))
        let remaining = try await store.loadOverrides()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRevert() async throws {
        var edited = club
        edited.name = "Big Club"
        let store = InMemoryItemOverrideStore(overrides: [edited])
        let library = await makeLibrary(creator: true, store: store)
        try await library.revert(id: "club")
        XCTAssertEqual(library.catalog.item(id: "club"), club)
        let remaining = try await store.loadOverrides()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInvalidEditIsRejectedAndNotStored() async throws {
        let store = InMemoryItemOverrideStore()
        let library = await makeLibrary(creator: true, store: store)
        var edited = club
        edited.name = ""
        do {
            try await library.save(edited)
            XCTFail("expected emptyName")
        } catch {
            XCTAssertEqual(error as? ItemValidationError, .emptyName)
        }
        let count = await store.saveCount
        XCTAssertEqual(count, 0)
    }

    func testUnknownItemIsRejected() async {
        let library = await makeLibrary(creator: true)
        let stranger = EquipmentItem(id: "nope", name: "Nope", category: .gear, group: "Gear")
        do {
            try await library.save(stranger)
            XCTFail("expected unknownItem")
        } catch {
            XCTAssertEqual(error as? ItemLibraryError, .unknownItem)
        }
    }

    func testStoreFailuresKeepBuiltInItems() async {
        let library = await makeLibrary(creator: true, store: FailingStore())
        XCTAssertNotNil(library.syncError)
        XCTAssertEqual(library.catalog.items, [club])
        var edited = club
        edited.name = "Big Club"
        do {
            try await library.save(edited)
            XCTFail("expected saveFailed")
        } catch {
            XCTAssertEqual(error as? ItemLibraryError, .saveFailed)
        }
        XCTAssertEqual(library.catalog.item(id: "club")?.name, "Club")
    }
}
