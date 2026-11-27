import XCTest

/// Boots the real app in the simulator and walks the main screens.
final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-inMemoryCampaigns")
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

        XCTAssertTrue(characterRow(named: "Aria").waitForExistence(timeout: 5))
    }

    func testAddingExperienceShowsLevelUpUnlocks() {
        createCharacter(named: "Bram")
        characterRow(named: "Bram").tap()
        XCTAssertTrue(app.navigationBars["Bram"].waitForExistence(timeout: 5))

        app.buttons["sheet.addXP"].tap()
        let amount = app.textFields["xp.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("300")
        app.buttons["xp.submit"].tap()

        let title = app.staticTexts["levelUp.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Bram reached level 2!")
        XCTAssertTrue(element(labelContaining: "Action Surge").exists)
        app.buttons["levelUp.done"].tap()

        XCTAssertTrue(app.staticTexts["Level 2 Human Fighter"].waitForExistence(timeout: 5))
    }

    func testLearningASpellFromTheCharacterSheet() {
        createCharacter(named: "Cass")
        characterRow(named: "Cass").tap()
        XCTAssertTrue(app.navigationBars["Cass"].waitForExistence(timeout: 5))

        let addSpells = app.buttons["sheet.spells"]
        for _ in 0..<15 where !(addSpells.exists && addSpells.isHittable) {
            app.swipeUp()
        }
        addSpells.tap()

        // Fighters can't cast, so the picker opens on All spells. Fire Bolt is near the top of the cantrips.
        let row = app.buttons["spells.row.fire-bolt"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(row.value as? String, "Known")
        app.buttons["spells.done"].tap()

        XCTAssertTrue(element(labelContaining: "Fire Bolt").waitForExistence(timeout: 5))
    }

    private func createCharacter(named name: String) {
        app.buttons["home.characters"].tap()
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 5))
        app.buttons["characters.add"].tap()
        let field = app.textFields["newCharacter.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["newCharacter.create"].tap()
        XCTAssertTrue(characterRow(named: name).waitForExistence(timeout: 5))
    }

    private func element(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A character's row in the list. Its texts are merged into one button label.
    private func characterRow(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func testCampaignPlusOffersCreateAndJoin() {
        app.buttons["home.campaigns"].tap()
        XCTAssertTrue(app.navigationBars["Campaigns"].waitForExistence(timeout: 5))
        app.buttons["campaigns.add"].tap()
        XCTAssertTrue(app.buttons["Create campaign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Join campaign"].exists)
    }

    func testCreateCampaignGivesSixDigitCodeAndMakesYouTheDM() {
        openCampaignForm("Create campaign")
        fill("campaignForm.field", with: "Night Below")
        fill("campaignForm.yourName", with: "Dana")
        app.buttons["campaignForm.submit"].tap()

        let code = app.staticTexts["campaignForm.createdCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertNotNil(code.label.range(of: #"^\d{3} \d{3}$"#, options: .regularExpression), code.label)
        app.buttons["campaignForm.done"].tap()

        let row = campaignRow(named: "Night Below")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Dungeon Master"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["campaign.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["campaign.code"].label, code.label)
        XCTAssertTrue(app.staticTexts["Dana"].exists)
        XCTAssertTrue(app.staticTexts["No players yet. Share the code to invite your party."].exists)
    }

    func testJoinSampleCampaignAsAPlayer() {
        openCampaignForm("Join campaign")
        fill("campaignForm.field", with: "123456")
        fill("campaignForm.yourName", with: "Aria")
        app.buttons["campaignForm.submit"].tap()

        let row = campaignRow(named: "The Sunken Citadel")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Player"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["Sample DM"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Aria"].exists)
    }

    func testJoinWithUnknownCodeShowsError() {
        openCampaignForm("Join campaign")
        fill("campaignForm.field", with: "000001")
        fill("campaignForm.yourName", with: "Aria")
        app.buttons["campaignForm.submit"].tap()
        let error = app.staticTexts["campaignForm.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "No campaign uses that code.")
    }

    private func openCampaignForm(_ option: String) {
        app.buttons["home.campaigns"].tap()
        XCTAssertTrue(app.navigationBars["Campaigns"].waitForExistence(timeout: 5))
        app.buttons["campaigns.add"].tap()
        let button = app.buttons[option]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.textFields["campaignForm.field"].waitForExistence(timeout: 5))
    }

    private func fill(_ id: String, with text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    /// A campaign's row. Its texts are merged into one button label.
    private func campaignRow(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func testLibraryShowsCategories() {
        app.buttons["home.library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.items"].exists)
        XCTAssertTrue(app.staticTexts["Creatures"].exists)
    }
}
