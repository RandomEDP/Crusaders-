import XCTest
@testable import CrusadersKit

final class HomeDestinationTests: XCTestCase {
    func testHomeOffersExactlyThreeOptionsInOrder() {
        XCTAssertEqual(HomeDestination.allCases, [.characters, .campaigns, .library])
    }

    func testTitles() {
        XCTAssertEqual(HomeDestination.characters.title, "Characters")
        XCTAssertEqual(HomeDestination.campaigns.title, "Campaigns")
        XCTAssertEqual(HomeDestination.library.title, "Library")
    }

    func testEveryDestinationHasSubtitleAndIcon() {
        for destination in HomeDestination.allCases {
            XCTAssertFalse(destination.subtitle.isEmpty, "\(destination) has no subtitle")
            XCTAssertFalse(destination.systemImage.isEmpty, "\(destination) has no icon")
        }
    }

    func testIdentifiersAreUnique() {
        let ids = HomeDestination.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
