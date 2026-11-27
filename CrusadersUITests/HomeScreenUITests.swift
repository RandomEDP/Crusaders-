import XCTest

/// Boots the real app in the simulator and walks the main screens.
final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAppBootsToHomeWithThreeOptions() {
        XCTAssertTrue(app.navigationBars["Crusaders"].waitForExistence(timeout: 10))
        for id in ["home.characters", "home.campaigns", "home.library"] {
            XCTAssertTrue(app.buttons[id].exists, "\(id) missing")
        }
    }

    func testCreateCharacterFromPlusButton() {
        app.buttons["home.characters"].tap()
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 5))
        app.buttons["characters.add"].tap()

        let name = app.textFields["newCharacter.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Aria")
        app.buttons["newCharacter.create"].tap()

        XCTAssertTrue(app.staticTexts["Aria"].waitForExistence(timeout: 5))
    }

    func testCampaignPlusOffersCreateAndJoin() {
        app.buttons["home.campaigns"].tap()
        XCTAssertTrue(app.navigationBars["Campaigns"].waitForExistence(timeout: 5))
        app.buttons["campaigns.add"].tap()
        XCTAssertTrue(app.buttons["Create campaign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Join campaign"].exists)
    }

    func testJoinSampleCampaign() {
        app.buttons["home.campaigns"].tap()
        app.buttons["campaigns.add"].tap()
        app.buttons["Join campaign"].tap()

        let field = app.textFields["campaignForm.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("CRUSAD")
        app.buttons["campaignForm.submit"].tap()

        XCTAssertTrue(app.staticTexts["The Sunken Citadel"].waitForExistence(timeout: 5))
    }

    func testLibraryShowsCategories() {
        app.buttons["home.library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Creatures"].exists)
        XCTAssertTrue(app.staticTexts["Weapons"].exists)
        XCTAssertTrue(app.staticTexts["Armour"].exists)
    }
}
