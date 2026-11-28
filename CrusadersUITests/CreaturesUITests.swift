import XCTest

/// Library > Creatures: type headers, stat blocks, and the creator adding and editing creatures.
final class CreaturesUITests: XCTestCase {
    private func launch(creator: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        if creator { app.launchArguments.append("-creatorMode") }
        app.launch()
        app.buttons["home.library"].tap()
        let creatures = app.buttons["library.creatures"]
        XCTAssertTrue(creatures.waitForExistence(timeout: 5))
        creatures.tap()
        XCTAssertTrue(app.navigationBars["Creatures"].waitForExistence(timeout: 5))
        return app
    }

    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    func testHeadersStartCollapsedAndExpandOnTap() {
        let app = launch(creator: false)
        XCTAssertTrue(app.buttons["creatures.header.aberration"].exists)
        XCTAssertFalse(app.buttons["creature.aboleth"].exists)

        app.buttons["creatures.header.aberration"].tap()
        XCTAssertTrue(app.buttons["creature.aboleth"].waitForExistence(timeout: 5))
    }

    func testPlayerSeesStatBlockButCannotAddOrEdit() {
        let app = launch(creator: false)
        XCTAssertFalse(app.buttons["creatures.add"].exists)
        search("Owlbear", in: app)
        let owlbear = app.buttons["creature.owlbear"]
        XCTAssertTrue(owlbear.waitForExistence(timeout: 5))
        owlbear.tap()

        XCTAssertTrue(app.navigationBars["Owlbear"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["creature.detail.ac"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["creature.detail.hp"].exists)
        XCTAssertFalse(app.buttons["creature.edit"].exists)
    }

    func testCreatorAddsANewCreature() {
        let app = launch(creator: true)
        let add = app.buttons["creatures.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let name = app.textFields["creatureEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ember Imp")
        app.buttons["creatureEditor.save"].tap()

        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: name)
        wait(for: [closed], timeout: 5)
        XCTAssertTrue(app.navigationBars["Creatures"].exists)
        search("Ember", in: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ember Imp")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Ember Imp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["creature.edit"].exists)
    }

    func testCreatorRenamesAnSRDCreature() {
        let app = launch(creator: true)
        search("Goblin", in: app)
        let goblin = app.buttons["creature.goblin"]
        XCTAssertTrue(goblin.waitForExistence(timeout: 5))
        goblin.tap()

        let edit = app.buttons["creature.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let name = app.textFields["creatureEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(" Chief")
        app.buttons["creatureEditor.save"].tap()

        XCTAssertTrue(app.navigationBars["Goblin Chief"].waitForExistence(timeout: 5))
    }
}
