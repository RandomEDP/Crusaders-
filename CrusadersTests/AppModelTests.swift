import XCTest
import CloudKit
import CrusadersKit
@testable import Crusaders

@MainActor
final class AppModelTests: XCTestCase {
    func testStartsWithNoCharactersOrCampaignsAndPlaceholderLibrary() {
        let model = AppModel()
        XCTAssertTrue(model.roster.characters.isEmpty)
        XCTAssertTrue(model.campaignBook.campaigns.isEmpty)
        XCTAssertFalse(model.libraryCategories.isEmpty)
    }

    func testAddAndDeleteCharacter() throws {
        let model = AppModel()
        try model.addCharacter(name: "Aria", race: "Elf", characterClass: "Wizard", level: 2)
        XCTAssertEqual(model.roster.characters.map(\.name), ["Aria"])
        model.deleteCharacters(atOffsets: IndexSet(integer: 0))
        XCTAssertTrue(model.roster.characters.isEmpty)
    }

    func testCreateCampaign() throws {
        let model = AppModel()
        let campaign = try model.createCampaign(name: "Night Below")
        XCTAssertEqual(campaign.role, .dungeonMaster)
        XCTAssertEqual(model.campaignBook.campaigns, [campaign])
    }

    func testJoinCampaignUsesDirectory() throws {
        let directory = InMemoryCampaignDirectory(campaigns: [Campaign(name: "Tomb", joinCode: "TMB234", role: .dungeonMaster)])
        let model = AppModel(campaignDirectory: directory)
        let joined = try model.joinCampaign(code: "tmb234")
        XCTAssertEqual(joined.name, "Tomb")
        XCTAssertEqual(joined.role, .player)
    }

    func testItemLibraryShipsWithSRDItemsAndIsViewOnlyByDefault() async {
        let model = AppModel()
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
}
