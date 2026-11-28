import XCTest
import CrusadersKit
@testable import Crusaders

/// Import from D&D Beyond: reading a PDF opens the review screen, and saving goes through the normal
/// character store (so it syncs through CD_StoredCharacter like any other character).
@MainActor
final class SheetImportAppTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ddb-ominakna-thirke-2024", withExtension: "pdf"))
    }

    private func makeModel(store: CharacterStore) -> AppModel {
        AppModel(campaigns: CampaignManager(directory: InMemoryCampaignDirectory(), persistence: InMemoryCampaignPersistence()),
                 characterStore: store)
    }

    func testOpeningTheSamplePDFShowsItForReview() throws {
        let model = makeModel(store: InMemoryCharacterStore())
        model.openSheetPDF(at: try fixtureURL())
        XCTAssertNil(model.importProblem)
        let pending = try XCTUnwrap(model.pendingImport)
        XCTAssertEqual(pending.result.name, "Ominakna Thirke")
        XCTAssertEqual(pending.result.sheet.armorClass, 13)
        XCTAssertTrue(model.roster.characters.isEmpty, "Nothing is saved until the player taps Save")
    }

    func testSavingTheReviewedImportStoresTheCharacterWithItsSheet() throws {
        let store = InMemoryCharacterStore()
        let model = makeModel(store: store)
        model.openSheetPDF(at: try fixtureURL())
        var result = try XCTUnwrap(model.pendingImport).result
        result.name = "Omi"   // fixed on the review screen
        let character = try model.saveImport(result)

        XCTAssertNil(model.pendingImport)
        XCTAssertEqual(model.roster.characters.map(\.name), ["Omi"])
        let saved = try XCTUnwrap(store.characters.first)
        XCTAssertEqual(saved.id, character.id)
        XCTAssertEqual(saved.importedSheet?.maxHitPoints, 30)
        XCTAssertEqual(saved.importedSheet?.coins(.gp), 44)
        // The stored payload decodes back with the printed sheet intact.
        let payload = try CharacterCoding.encode(saved)
        XCTAssertEqual(try CharacterCoding.decode(payload).importedSheet, saved.importedSheet)
    }

    func testAFileThatIsNotACharacterSheetShowsAProblem() throws {
        let model = makeModel(store: InMemoryCharacterStore())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-sheet-\(UUID().uuidString).pdf")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.openSheetPDF(at: url)
        XCTAssertNil(model.pendingImport)
        XCTAssertEqual(model.importProblem, PDFSheetError.unreadable.localizedDescription)
    }

    func testEmptyNameCantBeSaved() throws {
        let model = makeModel(store: InMemoryCharacterStore())
        let result = SheetImport(sheet: ImportedSheet(), name: "  ", issues: [])
        XCTAssertThrowsError(try model.saveImport(result))
        XCTAssertTrue(model.roster.characters.isEmpty)
    }
}
