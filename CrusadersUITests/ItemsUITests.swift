import XCTest

/// Library > Items: collapsible headers, item details and creator editing.
final class ItemsUITests: XCTestCase {
    private func launch(creator: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        if creator { app.launchArguments.append("-creatorMode") }
        app.launch()
        app.buttons["home.library"].tap()
        let items = app.buttons["library.items"]
        XCTAssertTrue(items.waitForExistence(timeout: 5))
        items.tap()
        XCTAssertTrue(app.navigationBars["Items"].waitForExistence(timeout: 5))
        return app
    }

    func testHeadersStartCollapsedAndExpandOnTap() {
        let app = launch(creator: false)
        for id in ["weapons", "armour", "ammunition", "potions", "gear", "tools"] {
            XCTAssertTrue(app.buttons["items.header.\(id)"].exists, "missing \(id) header")
        }
        XCTAssertFalse(app.buttons["item.club"].exists)

        app.buttons["items.header.weapons"].tap()
        XCTAssertTrue(app.buttons["item.club"].waitForExistence(timeout: 5))

        app.buttons["items.header.weapons"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["item.club"])
        wait(for: [gone], timeout: 5)
    }

    func testSearchFindsItemsInCollapsedHeaders() {
        let app = launch(creator: false)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Healing")
        XCTAssertTrue(app.buttons["item.potion-of-healing"].waitForExistence(timeout: 5))
    }

    func testPlayerSeesDetailsButNoEditButton() {
        let app = launch(creator: false)
        app.buttons["items.header.armour"].tap()
        app.buttons["item.padded"].tap()
        XCTAssertTrue(app.navigationBars["Padded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["item.detail.ac"].exists)
        XCTAssertFalse(app.buttons["item.edit"].exists)
    }

    func testCreatorCanRenameAnItem() {
        let app = launch(creator: true)
        app.buttons["items.header.weapons"].tap()
        app.buttons["item.club"].tap()
        let edit = app.buttons["item.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let name = app.textFields["itemEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(" of Doom")
        app.buttons["itemEditor.save"].tap()

        XCTAssertTrue(app.navigationBars["Club of Doom"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["item.detail.edited"].exists)
    }
}
