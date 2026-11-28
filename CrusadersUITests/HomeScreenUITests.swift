import XCTest

/// Boots the real app in the simulator and walks the main screens.
final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Start every test with no saved characters or campaigns.
        app.launchArguments = ["-resetCharacters", "-inMemoryCampaigns"]
        app.launch()
    }

    func testCharactersAreStillThereAfterTheAppRestarts() {
        createCharacter(named: "Dara")
        XCTAssertTrue(app.descendants(matching: .any)["characters.storage"].exists)
        app.terminate()

        app.launchArguments = []
        app.launch()
        app.buttons["home.characters"].tap()
        XCTAssertTrue(characterRow(named: "Dara").waitForExistence(timeout: 5))
    }

    func testAppBootsToHomeWithThreeOptions() {
        XCTAssertTrue(app.navigationBars["Crusaders"].waitForExistence(timeout: 10))
        for id in ["home.characters", "home.campaigns", "home.library"] {
            XCTAssertTrue(app.buttons[id].exists, "\(id) missing")
        }
    }

    func testHomeShowsTheCrusadersLogo() {
        let logo = app.images["home.logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 10))
        XCTAssertEqual(logo.label, "Crusaders")
        XCTAssertGreaterThan(logo.frame.width, 150, "logo should be big enough to read")
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

    func testImportFromDDBeyondOpensTheFilePicker() {
        app.buttons["home.characters"].tap()
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 5))
        let importButton = app.buttons["characters.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertEqual(importButton.label, "Import from D&D Beyond")
        importButton.tap()
        // The system file picker (only PDFs) appears; cancelling goes back to the list.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 5))
    }

    func testEditingLanguagesAndFeatsAndOpeningLore() {
        createCharacter(named: "Dara")
        characterRow(named: "Dara").tap()
        XCTAssertTrue(app.navigationBars["Dara"].waitForExistence(timeout: 5))

        let edit = app.buttons["sheet.editDetails"]
        for _ in 0..<20 where !(edit.exists && edit.isHittable) {
            app.swipeUp()
        }
        edit.tap()
        // Multi-line fields show up as text views, so look them up by identifier only.
        let languages = app.descendants(matching: .any)["details.languages"]
        XCTAssertTrue(languages.waitForExistence(timeout: 5))
        languages.tap()
        languages.typeText("Common, Elvish")
        let feats = app.descendants(matching: .any)["details.feats"]
        feats.tap()
        feats.typeText("Alert")
        app.buttons["details.save"].tap()

        XCTAssertTrue(element(labelContaining: "Common, Elvish").waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContaining: "Alert").exists)

        let lore = app.buttons["sheet.lore"]
        for _ in 0..<10 where !(lore.exists && lore.isHittable) {
            app.swipeUp()
        }
        lore.tap()
        XCTAssertTrue(app.navigationBars["Lore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["lore.Religion"].waitForExistence(timeout: 5))
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

        // Fighters can't cast, so the picker opens on All spells. Fire Bolt is among the first cantrips,
        // but bigger text can push it below the fold, and the list only builds rows that are on screen.
        let row = app.buttons["spells.row.fire-bolt"]
        // Short drags rather than swipes: a swipe flings the list straight past the row.
        for _ in 0..<15 where !(row.exists && row.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(row.value as? String, "Known")
        app.buttons["spells.done"].tap()

        XCTAssertTrue(element(labelContaining: "Fire Bolt").waitForExistence(timeout: 5))
    }

    func testPointBuyAndClassPreset() {
        app.buttons["home.characters"].tap()
        app.buttons["characters.add"].tap()
        let field = app.textFields["newCharacter.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // Return closes the keyboard so the drags below scroll the form instead of landing on keys.
        field.typeText("Esme\n")

        let points = app.segmentedControls["newCharacter.abilityMethod"].buttons["Points"]
        scrollUntilHittable(points)
        points.tap()
        XCTAssertTrue(element(textContaining: "27 of 27").waitForExistence(timeout: 5))

        let presets = app.buttons["newCharacter.presets"]
        scrollUntilHittable(presets)
        presets.tap()
        let archer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archer")).firstMatch
        XCTAssertTrue(archer.waitForExistence(timeout: 5))
        archer.tap()
        XCTAssertTrue(element(textContaining: "0 of 27").waitForExistence(timeout: 5))

        app.buttons["newCharacter.create"].tap()
        XCTAssertTrue(characterRow(named: "Esme").waitForExistence(timeout: 5))
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        // Short drags rather than swipes, so the form doesn't fling past the control.
        for _ in 0..<20 where !(element.exists && element.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
    }

    private func element(textContaining text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch
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
        let shownCode = code.label
        XCTAssertNotNil(shownCode.range(of: #"^\d{3} \d{3}$"#, options: .regularExpression), shownCode)
        app.buttons["campaignForm.done"].tap()

        let row = campaignRow(named: "Night Below")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Dungeon Master"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["campaign.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["campaign.code"].label, shownCode)
        XCTAssertTrue(app.staticTexts["Dana"].exists)
        XCTAssertTrue(app.staticTexts["No players yet. Share the code to invite your party."].exists)
    }

    func testJoinSampleCampaignWithYourCharacter() {
        createCharacter(named: "Thalia")
        goHome()
        openCampaignForm("Join campaign")
        fill("campaignForm.field", with: "123456")
        fill("campaignForm.yourName", with: "Aria")
        let character = app.buttons["campaignForm.character"].firstMatch
        XCTAssertTrue(character.waitForExistence(timeout: 5))
        XCTAssertTrue(character.label.hasPrefix("Thalia"), character.label)
        XCTAssertEqual(character.value as? String, "Selected")
        app.buttons["campaignForm.submit"].tap()

        let row = campaignRow(named: "The Sunken Citadel")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Player"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["Sample DM"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Aria"].exists)
        XCTAssertTrue(element(labelContaining: "Thalia, Level 1").exists)

        // Players see their own inventory but can't add to it.
        app.buttons["Inventory"].tap()
        XCTAssertTrue(app.staticTexts["No items yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory.add"].exists)
        XCTAssertFalse(app.staticTexts["inventory.item.potion-of-healing"].exists, "should not see other players' items")
    }

    func testJoiningNeedsACharacter() {
        openCampaignForm("Join campaign")
        XCTAssertTrue(app.staticTexts["campaignForm.noCharacters"].exists)
        fill("campaignForm.field", with: "123456")
        fill("campaignForm.yourName", with: "Aria")
        app.buttons["campaignForm.submit"].tap()
        let error = app.staticTexts["campaignForm.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "Pick one of your characters to join with.")
    }

    func testJoinWithUnknownCodeShowsError() {
        createCharacter(named: "Thalia")
        goHome()
        openCampaignForm("Join campaign")
        fill("campaignForm.field", with: "000001")
        fill("campaignForm.yourName", with: "Aria")
        app.buttons["campaignForm.submit"].tap()
        let error = app.staticTexts["campaignForm.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "No campaign uses that code.")
    }

    func testDMAddsAndRemovesInventoryItems() {
        app.terminate()
        app.launchArguments = ["-resetCharacters", "-dmTestCampaign"]
        app.launch()

        app.buttons["home.campaigns"].tap()
        let row = campaignRow(named: "Test Table")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element(labelContaining: "Thorin, Level 1").waitForExistence(timeout: 5))

        app.buttons["Inventory"].tap()
        let add = app.buttons["inventory.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        app.buttons["itemPicker.quantity-Increment"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Longsword")
        let longsword = app.buttons["itemPicker.item.longsword"]
        XCTAssertTrue(longsword.waitForExistence(timeout: 5))
        longsword.tap()

        let item = app.staticTexts["inventory.item.longsword"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertEqual(item.label, "Longsword ×2")

        app.buttons["inventory.remove.longsword"].tap()
        XCTAssertTrue(app.staticTexts["Longsword ×1"].waitForExistence(timeout: 5))
        app.buttons["inventory.remove.longsword"].tap()
        XCTAssertTrue(app.staticTexts["No items yet."].waitForExistence(timeout: 5))
    }

    func testEquippingArmourAndAWeaponFromTheInventory() {
        app.terminate()
        app.launchArguments = ["-resetCharacters", "-dmTestCampaign"]
        app.launch()

        app.buttons["home.campaigns"].tap()
        let row = campaignRow(named: "Test Table")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["Inventory"].tap()

        for (query, id) in [("Chain Mail", "chain-mail"), ("Greatsword", "greatsword")] {
            let add = app.buttons["inventory.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText(query)
            let item = app.buttons["itemPicker.item.\(id)"]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
            XCTAssertTrue(app.staticTexts["inventory.item.\(id)"].waitForExistence(timeout: 5))
        }

        app.buttons["inventory.equip.chain-mail"].tap()
        let wear = app.buttons["Wear"]
        XCTAssertTrue(wear.waitForExistence(timeout: 5))
        wear.tap()
        let armourStatus = app.staticTexts["inventory.status.chain-mail"]
        XCTAssertTrue(armourStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(armourStatus.label, "Worn")

        app.buttons["inventory.equip.greatsword"].tap()
        let hold = app.buttons["Hold in both hands"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        hold.tap()
        let weaponStatus = app.staticTexts["inventory.status.greatsword"]
        XCTAssertTrue(weaponStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(weaponStatus.label, "Both hands")

        app.buttons["inventory.equip.chain-mail"].tap()
        let takeOff = app.buttons["Take off"]
        XCTAssertTrue(takeOff.waitForExistence(timeout: 5))
        takeOff.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: armourStatus)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    func testDMDealsDamageAndMovesRoundsOn() {
        app.terminate()
        app.launchArguments = ["-resetCharacters", "-dmTestCampaign"]
        app.launch()

        app.buttons["home.campaigns"].tap()
        let row = campaignRow(named: "Test Table")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["Combat"].tap()

        let round = app.staticTexts["combat.round"]
        XCTAssertTrue(round.waitForExistence(timeout: 5))
        XCTAssertEqual(round.label, "Round 0")
        app.buttons["combat.nextRound"].tap()
        XCTAssertTrue(app.staticTexts["Round 1"].waitForExistence(timeout: 5))

        let damage = app.buttons["combat.damage.ui-test-player"]
        XCTAssertTrue(damage.waitForExistence(timeout: 5))
        damage.tap()
        let amount = app.textFields["combat.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("7")
        app.buttons["combat.apply"].tap()

        let hp = app.staticTexts["combat.hp.ui-test-player"]
        XCTAssertTrue(hp.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["7 damage taken"].waitForExistence(timeout: 5), hp.label)
    }

    func testDMChatsWithThePartyAndWhispersToOnePlayer() {
        app.terminate()
        app.launchArguments = ["-resetCharacters", "-dmTestCampaign"]
        app.launch()

        app.buttons["home.campaigns"].tap()
        let row = campaignRow(named: "Test Table")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let chatTab = app.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 5))
        chatTab.tap()

        // Party chat.
        let party = app.buttons["chat.channel.party"]
        XCTAssertTrue(party.waitForExistence(timeout: 5))
        party.tap()
        XCTAssertTrue(app.staticTexts["No messages yet."].waitForExistence(timeout: 5))
        sendChat("Welcome to the table!")
        XCTAssertTrue(app.staticTexts["Welcome to the table!"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Private chat with Sam's character: narration only Sam sees.
        let whisper = app.buttons["chat.channel.whisper-ui-test-player"]
        XCTAssertTrue(whisper.waitForExistence(timeout: 5))
        whisper.tap()
        XCTAssertTrue(element(labelContaining: "Only you and Sam can read this").waitForExistence(timeout: 5))
        let narrate = app.buttons["chat.narrate"]
        XCTAssertTrue(narrate.waitForExistence(timeout: 5))
        narrate.tap()
        sendChat("You hear a voice in your head call out your name.")
        let narration = app.staticTexts["chat.narration"]
        XCTAssertTrue(narration.waitForExistence(timeout: 5))
        XCTAssertEqual(narration.label, "You hear a voice in your head call out your name.")
        XCTAssertFalse(app.staticTexts["Welcome to the table!"].exists, "party messages don't show in a private chat")
    }

    private func sendChat(_ text: String) {
        let field = app.textFields["chat.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["chat.send"].tap()
    }

    /// Back to the home screen from one level down.
    private func goHome() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home.campaigns"].waitForExistence(timeout: 5))
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
