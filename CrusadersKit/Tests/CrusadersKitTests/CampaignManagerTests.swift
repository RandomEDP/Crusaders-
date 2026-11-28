import XCTest
@testable import CrusadersKit

private let hero = PlayerCharacter(name: "Aria", race: "Elf", characterClass: "Wizard")

/// A directory that fails every call, like iCloud being offline.
private struct OfflineDirectory: CampaignDirectory {
    struct Offline: Error {}
    func publish(_ campaign: Campaign) async throws { throw Offline() }
    func campaign(forJoinCode code: String) async throws -> Campaign? { throw Offline() }
    func addPlayer(_ player: CampaignMember, toCampaignWithCode code: String) async throws -> Campaign { throw Offline() }
    func record(_ change: InventoryChange, inCampaignWithCode code: String) async throws -> Campaign { throw Offline() }
    func record(_ change: LoadoutChange, inCampaignWithCode code: String) async throws -> Campaign { throw Offline() }
}

/// Hands out codes from a list, so tests can force clashes.
private final class CodeSequence {
    private var codes: [String]
    init(_ codes: [String]) { self.codes = codes }
    func next() -> String { codes.isEmpty ? "999999" : codes.removeFirst() }
}

@MainActor
final class CampaignManagerTests: XCTestCase {
    private func manager(
        id: String,
        directory: CampaignDirectory,
        persistence: CampaignPersistence = InMemoryCampaignPersistence(),
        codes: [String]? = nil
    ) -> CampaignManager {
        if let codes {
            let sequence = CodeSequence(codes)
            return CampaignManager(directory: directory, persistence: persistence,
                                   makeCode: { sequence.next() }, newMemberID: { id })
        }
        return CampaignManager(directory: directory, persistence: persistence, newMemberID: { id })
    }

    func testCreatorIsTheDungeonMasterWithASixDigitCode() async throws {
        let dm = manager(id: "dm", directory: InMemoryCampaignDirectory())
        let campaign = try await dm.create(name: "  Night Below ", yourName: " Dana ")
        XCTAssertEqual(campaign.name, "Night Below")
        XCTAssertEqual(campaign.dungeonMaster, CampaignMember(id: "dm", name: "Dana"))
        XCTAssertTrue(campaign.players.isEmpty)
        XCTAssertEqual(JoinCode.normalize(campaign.joinCode), campaign.joinCode)
        XCTAssertEqual(dm.role(in: campaign), .dungeonMaster)
        XCTAssertEqual(dm.campaigns, [campaign])
        XCTAssertEqual(dm.me.name, "Dana")
    }

    func testAnotherPlayerJoinsWithTheCodeAndIsListedAsAPlayer() async throws {
        let shared = InMemoryCampaignDirectory()
        let dm = manager(id: "dm", directory: shared, codes: ["042917"])
        let player = manager(id: "p1", directory: shared)

        try await dm.create(name: "Night Below", yourName: "Dana")
        let joined = try await player.join(code: "042 917", yourName: "Aria", character: hero)

        XCTAssertEqual(joined.name, "Night Below")
        XCTAssertEqual(joined.dungeonMaster.name, "Dana")
        XCTAssertEqual(joined.players, [CampaignMember(id: "p1", name: "Aria", character: CampaignCharacter(hero))])
        XCTAssertEqual(player.role(in: joined), .player)

        // The DM sees the new player after refreshing.
        XCTAssertTrue(try XCTUnwrap(dm.campaign(code: "042917")).players.isEmpty)
        await dm.refresh()
        XCTAssertEqual(dm.campaign(code: "042917")?.players.map(\.name), ["Aria"])
        XCTAssertNil(dm.refreshError)
    }

    func testSeveralPlayersCanJoin() async throws {
        let shared = InMemoryCampaignDirectory()
        let dm = manager(id: "dm", directory: shared, codes: ["111111"])
        try await dm.create(name: "Night Below", yourName: "Dana")
        try await manager(id: "p1", directory: shared).join(code: "111111", yourName: "Aria", character: hero)
        let last = try await manager(id: "p2", directory: shared).join(code: "111111", yourName: "Bram", character: hero)
        XCTAssertEqual(last.players.map(\.name), ["Aria", "Bram"])
    }

    func testClashingCodesAreRetried() async throws {
        let shared = InMemoryCampaignDirectory()
        try await shared.publish(Campaign(name: "Taken", joinCode: "111111", dungeonMaster: CampaignMember(id: "x", name: "X")))
        let dm = manager(id: "dm", directory: shared, codes: ["111111", "111111", "222222"])
        let campaign = try await dm.create(name: "Fresh", yourName: "Dana")
        XCTAssertEqual(campaign.joinCode, "222222")
    }

    func testGivesUpWhenEveryCodeIsTaken() async throws {
        let shared = InMemoryCampaignDirectory()
        try await shared.publish(Campaign(name: "Taken", joinCode: "111111", dungeonMaster: CampaignMember(id: "x", name: "X")))
        let codes = Array(repeating: "111111", count: CampaignManager.maxCodeAttempts)
        let dm = manager(id: "dm", directory: shared, codes: codes)
        await assertThrows(.codeTaken) { try await dm.create(name: "Fresh", yourName: "Dana") }
        XCTAssertTrue(dm.campaigns.isEmpty)
    }

    func testCreateValidation() async {
        let dm = manager(id: "dm", directory: InMemoryCampaignDirectory())
        await assertThrows(.emptyName) { try await dm.create(name: " ", yourName: "Dana") }
        await assertThrows(.emptyPlayerName) { try await dm.create(name: "Night Below", yourName: "") }
        XCTAssertTrue(dm.campaigns.isEmpty)
    }

    func testJoinValidation() async throws {
        let shared = InMemoryCampaignDirectory.withSamples()
        let player = manager(id: "p1", directory: shared)
        for bad in ["", "12345", "1234567", "12345A"] {
            await assertThrows(.invalidJoinCode) { try await player.join(code: bad, yourName: "Aria", character: hero) }
        }
        await assertThrows(.emptyPlayerName) { try await player.join(code: "123456", yourName: " ", character: hero) }
        await assertThrows(.campaignNotFound) { try await player.join(code: "654321", yourName: "Aria", character: hero) }
        XCTAssertTrue(player.campaigns.isEmpty)
    }

    func testJoiningTwiceFails() async throws {
        let player = manager(id: "p1", directory: InMemoryCampaignDirectory.withSamples())
        try await player.join(code: "123456", yourName: "Aria", character: hero)
        await assertThrows(.alreadyJoined) { try await player.join(code: "123456", yourName: "Aria", character: hero) }
        XCTAssertEqual(player.campaigns.count, 1)
    }

    func testDMCannotJoinTheirOwnCampaign() async throws {
        let shared = InMemoryCampaignDirectory()
        let persistence = InMemoryCampaignPersistence()
        let dm = manager(id: "dm", directory: shared, persistence: persistence, codes: ["333333"])
        try await dm.create(name: "Night Below", yourName: "Dana")
        dm.leave(code: "333333")
        await assertThrows(.alreadyJoined) { try await dm.join(code: "333333", yourName: "Dana", character: hero) }
        let remote = try await shared.campaign(forJoinCode: "333333")
        XCTAssertEqual(remote?.players, [])
    }

    func testOfflineErrorsAreFriendly() async {
        let player = manager(id: "p1", directory: OfflineDirectory())
        await assertThrows(.directoryUnavailable) { try await player.create(name: "Night Below", yourName: "Aria") }
        await assertThrows(.directoryUnavailable) { try await player.join(code: "123456", yourName: "Aria", character: hero) }
    }

    func testRefreshProblemIsReportedAndSavedCampaignsKept() async throws {
        let campaign = Campaign(name: "Saved", joinCode: "123456", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        let persistence = InMemoryCampaignPersistence(
            SavedCampaigns(me: CampaignMember(id: "dm", name: "Dana"), book: CampaignBook(campaigns: [campaign]))
        )
        let dm = manager(id: "unused", directory: OfflineDirectory(), persistence: persistence)
        await dm.refresh()
        XCTAssertNotNil(dm.refreshError)
        XCTAssertEqual(dm.campaigns, [campaign])
    }

    func testIdentityAndCampaignsArePersisted() async throws {
        let shared = InMemoryCampaignDirectory()
        let persistence = InMemoryCampaignPersistence()
        let first = manager(id: "dm", directory: shared, persistence: persistence)
        let campaign = try await first.create(name: "Night Below", yourName: "Dana")

        let reopened = manager(id: "someone-new", directory: shared, persistence: persistence)
        XCTAssertEqual(reopened.me, CampaignMember(id: "dm", name: "Dana"))
        XCTAssertEqual(reopened.campaigns, [campaign])

        reopened.leave(code: campaign.joinCode)
        XCTAssertEqual(persistence.load()?.book.campaigns, [])
    }

    func testFirstLaunchSavesANewIdentity() {
        let persistence = InMemoryCampaignPersistence()
        _ = manager(id: "fresh", directory: InMemoryCampaignDirectory(), persistence: persistence)
        XCTAssertEqual(persistence.load()?.me.id, "fresh")
    }

    func testFilePersistenceRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("campaigns.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileCampaignPersistence(url: url)
        XCTAssertNil(store.load())

        var campaign = Campaign(name: "Night Below", joinCode: "042917", dungeonMaster: CampaignMember(id: "dm", name: "Dana"))
        campaign.addPlayer(CampaignMember(id: "p1", name: "Aria"))
        let saved = SavedCampaigns(me: CampaignMember(id: "dm", name: "Dana"), book: CampaignBook(campaigns: [campaign]))
        try store.save(saved)
        XCTAssertEqual(store.load(), saved)
    }

    private func assertThrows(
        _ expected: CampaignError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Any
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CampaignError, expected, file: file, line: line)
        }
    }
}
