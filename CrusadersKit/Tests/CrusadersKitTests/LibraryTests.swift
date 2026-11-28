import XCTest
@testable import CrusadersKit

final class LibraryTests: XCTestCase {
    private let categories = PlaceholderLibraryCatalog().categories()

    func testPlaceholderHasCoreCategories() {
        let names = categories.map(\.name)
        for expected in ["Spells", "Magic Items"] {
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }
    }

    func testEveryCategoryHasItemsAndUniqueIds() {
        XCTAssertEqual(Set(categories.map(\.id)).count, categories.count)
        for category in categories {
            XCTAssertFalse(category.items.isEmpty, "\(category.name) is empty")
            XCTAssertEqual(Set(category.items.map(\.id)).count, category.items.count, "duplicate ids in \(category.name)")
        }
    }

    func testSearchMatchesNameAndSummaryCaseInsensitively() throws {
        let spells = try XCTUnwrap(categories.first { $0.id == "spells" })
        XCTAssertEqual(spells.items(matching: "FIRE BOLT").map(\.id), ["fire-bolt"])
        XCTAssertEqual(spells.items(matching: "heal").map(\.id), ["cure-wounds"])
        XCTAssertTrue(spells.items(matching: "zzz").isEmpty)
    }

    func testEmptySearchReturnsEverything() throws {
        let spells = try XCTUnwrap(categories.first { $0.id == "spells" })
        XCTAssertEqual(spells.items(matching: "  "), spells.items)
    }

    func testEquipmentMovedOutOfPlaceholderIntoItems() {
        let ids = Set(categories.map(\.id))
        XCTAssertFalse(ids.contains("weapons"))
        XCTAssertFalse(ids.contains("armour"))
    }

    func testCreaturesMovedOutOfPlaceholderIntoTheirOwnSection() {
        XCTAssertFalse(categories.map(\.id).contains("creatures"))
    }
}
