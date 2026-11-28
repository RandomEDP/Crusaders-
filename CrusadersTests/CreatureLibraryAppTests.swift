import XCTest
import CloudKit
import CrusadersKit
@testable import Crusaders

/// Library > Creatures as the app sets it up.
@MainActor
final class CreatureLibraryAppTests: XCTestCase {
    func testAppShipsWithSRDCreaturesAndIsViewOnlyByDefault() async {
        let model = AppModel(campaigns: CampaignManager(directory: InMemoryCampaignDirectory(), persistence: InMemoryCampaignPersistence()))
        XCTAssertEqual(model.creatureLibrary.catalog.count, 334)
        await model.creatureLibrary.refresh()
        XCTAssertFalse(model.creatureLibrary.isCreator)
        XCTAssertNotNil(model.creatureLibrary.catalog.creature(id: "owlbear"))
    }

    func testCreatorModeLetsTheCreatorAddAndEditCreatures() async throws {
        let library = CreatureLibrary.makeDefault(arguments: ["-creatorMode"])
        await library.refresh()
        XCTAssertTrue(library.isCreator)

        var imp = Creature.newCustom()
        imp.name = "Ember Imp"
        imp.type = .fiend
        let saved = try await library.save(imp)
        XCTAssertTrue(library.catalog.isCustom(saved.id))
        XCTAssertEqual(library.catalog.count, 335)

        var goblin = try XCTUnwrap(library.catalog.creature(id: "goblin"))
        goblin.armorClass = 16
        try await library.save(goblin)
        XCTAssertTrue(library.catalog.isEdited("goblin"))
    }

    func testWithoutICloudCreatureEditingIsOffAndExplained() async {
        let library = CreatureLibrary.makeDefault(arguments: [], cloudKitEnabled: false)
        await library.refresh()
        XCTAssertFalse(library.isCreator)
        XCTAssertNotNil(library.creatorStatus.problem)
    }

    func testItemsAndCreaturesFollowTheSameCreatorRules() async {
        for arguments in [[], ["-creatorMode"]] {
            let items = ItemLibrary.makeDefault(arguments: arguments, cloudKitEnabled: false)
            let creatures = CreatureLibrary.makeDefault(arguments: arguments, cloudKitEnabled: false)
            await items.refresh()
            await creatures.refresh()
            XCTAssertEqual(items.creatorStatus, creatures.creatorStatus, "\(arguments)")
        }
    }

    func testCloudKitRecordEncodingRoundTrips() throws {
        let dragon = try XCTUnwrap(CreatureLibrary.makeDefault(arguments: []).catalog.creature(id: "adult-red-dragon"))
        let record = CKRecord(recordType: CloudKitCreatureStore.recordType,
                              recordID: CloudKitCreatureStore.recordID(for: dragon.id))
        record["payload"] = try CloudKitCreatureStore.encode(dragon) as CKRecordValue
        XCTAssertEqual(CloudKitCreatureStore.recordType, "CreatureEntry")
        XCTAssertEqual(record.recordID.recordName, "creature-adult-red-dragon")
        XCTAssertEqual(CloudKitCreatureStore.decode(record), dragon)
        XCTAssertNil(CloudKitCreatureStore.decode(CKRecord(recordType: CloudKitCreatureStore.recordType)))
    }
}
