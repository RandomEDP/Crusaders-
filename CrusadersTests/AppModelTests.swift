import XCTest
import CloudKit
import CrusadersKit
@testable import Crusaders

@MainActor
final class AppModelTests: XCTestCase {
    /// A model whose campaigns live in memory, so tests never touch files saved by earlier runs.
    private func makeModel(directory: CampaignDirectory = InMemoryCampaignDirectory()) -> AppModel {
        AppModel(campaigns: CampaignManager(directory: directory, persistence: InMemoryCampaignPersistence()))
    }

    func testStartsWithNoCharactersOrCampaignsAndPlaceholderLibrary() {
        let model = makeModel()
        XCTAssertTrue(model.roster.characters.isEmpty)
        XCTAssertTrue(model.campaigns.campaigns.isEmpty)
        XCTAssertFalse(model.libraryCategories.isEmpty)
    }

    func testAddAndDeleteCharacter() throws {
        let model = makeModel()
        try model.addCharacter(name: "Aria", race: "Elf", characterClass: "Wizard", level: 2)
        XCTAssertEqual(model.roster.characters.map(\.name), ["Aria"])
        model.deleteCharacters(atOffsets: IndexSet(integer: 0))
        XCTAssertTrue(model.roster.characters.isEmpty)
    }

    func testCreateCampaignMakesYouTheDMWithASixDigitCode() async throws {
        let model = makeModel()
        let campaign = try await model.createCampaign(name: "Night Below", yourName: "Dana")
        XCTAssertEqual(model.campaigns.role(in: campaign), .dungeonMaster)
        XCTAssertEqual(campaign.dungeonMaster.name, "Dana")
        XCTAssertEqual(campaign.joinCode.count, 6)
        XCTAssertTrue(campaign.joinCode.allSatisfy(\.isNumber))
        XCTAssertEqual(model.campaigns.campaigns, [campaign])
    }

    func testFriendJoinsWithTheCodeAsAPlayer() async throws {
        let shared = InMemoryCampaignDirectory()
        let dm = makeModel(directory: shared)
        let friend = makeModel(directory: shared)
        var draft = CharacterDraft.starter(catalog: friend.rules)
        draft.name = "Thalia"
        let hero = try friend.createCharacter(from: draft)
        let campaign = try await dm.createCampaign(name: "Tomb", yourName: "Dana")
        let joined = try await friend.joinCampaign(code: campaign.joinCode, yourName: "Aria", characterID: hero.id)
        XCTAssertEqual(joined.player(id: friend.campaigns.me.id)?.character?.name, "Thalia")
        XCTAssertEqual(joined.name, "Tomb")
        XCTAssertEqual(friend.campaigns.role(in: joined), .player)
        XCTAssertEqual(joined.dungeonMaster.name, "Dana")
        XCTAssertEqual(joined.players.map(\.name), ["Aria"])
    }

    func testDefaultCampaignsWithoutICloudOfferTheSampleAndArentShared() async throws {
        let manager = CampaignManager.makeDefault(arguments: ["-inMemoryCampaigns"], cloudKitEnabled: false)
        XCTAssertFalse(manager.isShared)
        let joined = try await manager.join(code: InMemoryCampaignDirectory.sampleCode, yourName: "Aria",
                                            character: PlayerCharacter(name: "Thalia", race: "Human", characterClass: "Fighter"))
        XCTAssertEqual(joined.name, "The Sunken Citadel")
        XCTAssertEqual(manager.role(in: joined), .player)
    }

    func testDMGivesAnItemAndThePlayerUsesIt() async throws {
        let shared = InMemoryCampaignDirectory()
        let dm = makeModel(directory: shared)
        let friend = makeModel(directory: shared)
        var draft = CharacterDraft.starter(catalog: friend.rules)
        draft.name = "Thalia"
        let hero = try friend.createCharacter(from: draft)
        let campaign = try await dm.createCampaign(name: "Tomb", yourName: "Dana")
        try await friend.joinCampaign(code: campaign.joinCode, yourName: "Aria", characterID: hero.id)
        await dm.campaigns.refresh()

        let potion = try XCTUnwrap(dm.itemLibrary.catalog.item(id: "potion-of-healing"))
        let playerID = friend.campaigns.me.id
        try await dm.addItem(potion, quantity: 2, to: playerID, inCampaign: campaign.joinCode)
        await friend.campaigns.refresh()
        try await friend.removeItem("potion-of-healing", from: playerID, inCampaign: campaign.joinCode)
        XCTAssertEqual(friend.campaigns.campaign(code: campaign.joinCode)?.inventory(of: playerID).first?.quantity, 1)
        do {
            try await friend.addItem(potion, quantity: 1, to: playerID, inCampaign: campaign.joinCode)
            XCTFail("players can't add")
        } catch {
            XCTAssertEqual(error as? CampaignError, .onlyDungeonMasterCanAdd)
        }
    }

    func testDMTestCampaignLaunchArgument() {
        let manager = CampaignManager.makeDefault(arguments: ["-dmTestCampaign"], cloudKitEnabled: false)
        let campaign = manager.campaigns.first
        XCTAssertEqual(campaign?.name, "Test Table")
        XCTAssertEqual(campaign.flatMap { manager.role(in: $0) }, .dungeonMaster)
        XCTAssertEqual(campaign?.players.first?.character?.name, "Thorin")
    }

    func testCloudKitInventoryAndCharacterRecordsRoundTrip() {
        let change = InventoryChange(playerID: "p1", itemID: "rope", itemName: "Rope", delta: -1, authorID: "p1",
                                     date: Date(timeIntervalSince1970: 1_000))
        let record = CloudKitCampaignDirectory.inventoryRecord(change, code: "042917")
        XCTAssertEqual(record.recordType, "InventoryChange")
        XCTAssertEqual(record["joinCode"] as? String, "042917")
        XCTAssertEqual(CloudKitCampaignDirectory.inventoryChange(from: record), change)

        let player = CampaignMember(id: "p1", name: "Aria",
                                    character: CampaignCharacter(id: UUID(), name: "Thalia", summary: "Level 1 Human Fighter"))
        XCTAssertEqual(CloudKitCampaignDirectory.player(from: CloudKitCampaignDirectory.playerRecord(player, code: "042917")), player)
    }

    func testAppModelChatStaysOnThePhoneWhileICloudIsOff() async throws {
        let model = makeModel()
        let campaign = try await model.createCampaign(name: "Night Below", yourName: "Dana")
        try await model.chat.send("Welcome!", in: .party, campaign: campaign, as: model.campaigns.me)
        await model.chat.load(.party, campaign: campaign, viewer: model.campaigns.me)
        XCTAssertEqual(model.chat.messages(in: .party, campaign: campaign, viewer: model.campaigns.me).map(\.text), ["Welcome!"])
    }

    func testCloudKitChatRecordsRoundTrip() {
        let party = ChatMessage(channel: .party, senderID: "p1", senderName: "Sam", text: "Hello",
                                sentAt: Date(timeIntervalSince1970: 1_000))
        let partyRecord = CloudKitChatService.record(for: party, code: "042917", zoneID: nil)
        XCTAssertEqual(partyRecord.recordType, "ChatMessage")
        XCTAssertEqual(partyRecord.recordID.recordName, "chat-\(party.id.uuidString)")
        XCTAssertEqual(partyRecord.recordID.zoneID, CKRecordZone.default().zoneID)
        XCTAssertEqual(partyRecord["joinCode"] as? String, "042917")
        XCTAssertEqual(CloudKitChatService.message(from: partyRecord), party)

        // Private chats never go to the public database's default zone: they live in the DM's shared zone.
        let zoneID = CKRecordZone.ID(zoneName: CloudKitChatService.zoneName(code: "042917", playerID: "p1"),
                                     ownerName: CKCurrentUserDefaultName)
        XCTAssertEqual(zoneID.zoneName, "whisper-042917-p1")
        let whisper = ChatMessage(channel: .whisper(playerID: "p1"), senderID: "dm", senderName: "Dana",
                                  text: "You hear a voice in your head", isNarration: true,
                                  sentAt: Date(timeIntervalSince1970: 2_000))
        let whisperRecord = CloudKitChatService.record(for: whisper, code: "042917", zoneID: zoneID)
        XCTAssertEqual(whisperRecord.recordType, "WhisperMessage")
        XCTAssertEqual(whisperRecord.recordID.zoneID, zoneID)
        XCTAssertEqual(CloudKitChatService.message(from: whisperRecord), whisper)

        let url = URL(string: "https://www.icloud.com/share/abc")!
        let invite = CloudKitChatService.inviteRecord(code: "042917", playerID: "p1", shareURL: url)
        XCTAssertEqual(invite.recordType, "WhisperInvite")
        XCTAssertEqual(invite.recordID.recordName, "whisper-invite-042917-p1")
        XCTAssertEqual(CloudKitChatService.shareURL(from: invite), url)
        XCTAssertNil(CloudKitChatService.message(from: CKRecord(recordType: "ChatMessage")))
    }

    func testCloudKitCampaignRecordsRoundTrip() {
        let campaign = Campaign(name: "Night Below", joinCode: "042917",
                                dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        let record = CloudKitCampaignDirectory.record(for: campaign)
        XCTAssertEqual(record.recordType, "Campaign")
        XCTAssertEqual(record.recordID.recordName, "campaign-042917")
        XCTAssertEqual(CloudKitCampaignDirectory.campaign(from: record), campaign)

        let aria = CampaignMember(id: "p1", name: "Aria")
        let playerRecord = CloudKitCampaignDirectory.playerRecord(aria, code: "042917")
        XCTAssertEqual(playerRecord.recordType, "CampaignPlayer")
        XCTAssertEqual(playerRecord.recordID.recordName, "player-042917-p1")
        XCTAssertEqual(playerRecord["joinCode"] as? String, "042917")
        XCTAssertEqual(CloudKitCampaignDirectory.player(from: playerRecord), aria)

        XCTAssertNil(CloudKitCampaignDirectory.campaign(from: CKRecord(recordType: "Campaign")))
    }

    func testItemLibraryShipsWithSRDItemsAndIsViewOnlyByDefault() async {
        let model = makeModel()
        XCTAssertGreaterThan(model.itemLibrary.catalog.baseItems.count, 250)
        await model.itemLibrary.refresh()
        XCTAssertFalse(model.itemLibrary.isCreator)
    }

    func testCreatorModeLaunchArgumentUnlocksEditingInDebug() async throws {
        let library = ItemLibrary.makeDefault(arguments: ["-creatorMode"])
        await library.refresh()
        XCTAssertTrue(library.isCreator)
        var club = try XCTUnwrap(library.catalog.item(id: "club"))
        club.name = "Big Club"
        try await library.save(club)
        XCTAssertEqual(library.catalog.item(id: "club")?.name, "Big Club")
    }

    func testWithoutICloudEditingIsOffAndExplained() async {
        let library = ItemLibrary.makeDefault(arguments: [], cloudKitEnabled: false)
        await library.refresh()
        XCTAssertFalse(library.isCreator)
        XCTAssertNotNil(library.creatorStatus.problem)
        XCTAssertGreaterThan(library.catalog.items.count, 250)
    }

    func testThisBuildHasICloudSwitchedOff() {
        XCTAssertFalse(ItemLibrary.cloudKitEnabledInBuild)
    }

    func testCloudKitRecordEncodingRoundTrips() throws {
        let item = try XCTUnwrap(ItemLibrary.makeDefault(arguments: []).catalog.item(id: "longsword"))
        let record = CKRecord(recordType: CloudKitItemOverrideStore.recordType,
                              recordID: CloudKitItemOverrideStore.recordID(for: item.id))
        record["payload"] = try CloudKitItemOverrideStore.encode(item) as CKRecordValue
        XCTAssertEqual(record.recordID.recordName, "item-longsword")
        XCTAssertEqual(CloudKitItemOverrideStore.decode(record), item)
    }

    func testCreateCharacterFromDraftUsesSRDRules() throws {
        let model = makeModel()
        var draft = CharacterDraft.starter(catalog: model.rules)
        draft.name = "Bram"
        let hero = try model.createCharacter(from: draft)
        XCTAssertEqual(hero.summary, "Level 1 Human Fighter")
        XCTAssertEqual(model.sheet(for: hero.id)?.maxHitPoints, 12)
        XCTAssertNil(model.sheet(for: UUID()))
    }

    func testCreateCharacterRejectsBlankName() {
        let model = makeModel()
        XCTAssertThrowsError(try model.createCharacter(from: CharacterDraft.starter())) {
            XCTAssertEqual($0 as? CharacterError, .emptyName)
        }
        XCTAssertTrue(model.roster.characters.isEmpty)
    }

    func testAddExperienceReturnsLevelUpSummaryOnlyWhenLevelling() throws {
        let model = makeModel()
        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        let hero = try model.createCharacter(from: draft)
        XCTAssertNil(try model.addExperience(100, to: hero.id))
        let summary = try XCTUnwrap(try model.addExperience(800, to: hero.id))
        XCTAssertEqual(summary.fromLevel, 1)
        XCTAssertEqual(summary.toLevel, 3)
        XCTAssertEqual(summary.levels.map(\.level), [2, 3])
        XCTAssertEqual(model.character(id: hero.id)?.experiencePoints, 900)
        XCTAssertThrowsError(try model.addExperience(0, to: hero.id))
    }

    func testToggleSpellAndSpendImprovementPoint() throws {
        let model = makeModel()
        var draft = CharacterDraft.starter()
        draft.name = "Bram"
        draft.level = 4
        let hero = try model.createCharacter(from: draft)
        model.toggleSpell("fire-bolt", for: hero.id)
        XCTAssertEqual(model.character(id: hero.id)?.spellIDs, ["fire-bolt"])
        model.toggleSpell("fire-bolt", for: hero.id)
        XCTAssertEqual(model.character(id: hero.id)?.spellIDs, [])

        try model.spendImprovementPoint(on: .con, for: hero.id)
        XCTAssertEqual(model.sheet(for: hero.id)?.unspentImprovementPoints, 1)
    }

    func testLevelUpRollsHitDiceForCharactersThatRoll() throws {
        let model = AppModel(diceRoller: .sequence([7]))
        var draft = CharacterDraft.starter()
        draft.name = "Roller"
        draft.selectHitPointMethod(.rolled)
        let hero = try model.createCharacter(from: draft)
        let summary = try XCTUnwrap(try model.addExperience(300, to: hero.id))
        XCTAssertEqual(model.character(id: hero.id)?.hitPointRolls, [7])
        XCTAssertEqual(summary.levels.first?.hitPointRoll, 7)
        XCTAssertEqual(summary.levels.first?.hitPointIncrease, 9)
    }
}
