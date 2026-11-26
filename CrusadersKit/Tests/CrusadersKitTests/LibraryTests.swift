import XCTest
@testable import CrusadersKit

final class LibraryTests: XCTestCase {
    private let categories = PlaceholderLibraryCatalog().categories()

    func testPlaceholderHasCoreCategories() {
        let names = categories.map(\.name)
        for expected in ["Creatures", "Weapons", "Armour"] {
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
        let creatures = try XCTUnwrap(categories.first { $0.id == "creatures" })
        XCTAssertEqual(creatures.items(matching: "GOBLIN").map(\.id), ["goblin"])
        XCTAssertEqual(creatures.items(matching: "fire").map(\.id), ["young-red-dragon"])
        XCTAssertTrue(creatures.items(matching: "zzz").isEmpty)
    }

    func testEmptySearchReturnsEverything() throws {
        let weapons = try XCTUnwrap(categories.first { $0.id == "weapons" })
        XCTAssertEqual(weapons.items(matching: "  "), weapons.items)
    }
}
