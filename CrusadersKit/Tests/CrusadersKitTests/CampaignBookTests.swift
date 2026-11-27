import XCTest
@testable import CrusadersKit

private let dm = CampaignMember(id: "dm-1", name: "Dana")
private let aria = CampaignMember(id: "player-1", name: "Aria")

final class CampaignModelTests: XCTestCase {
    func testRoles() {
        var campaign = Campaign(name: "Lost Mine", joinCode: "123456", dungeonMaster: dm)
        campaign.addPlayer(aria)
        XCTAssertEqual(campaign.role(of: "dm-1"), .dungeonMaster)
        XCTAssertEqual(campaign.role(of: "player-1"), .player)
        XCTAssertNil(campaign.role(of: "stranger"))
        XCTAssertEqual(campaign.id, "123456")
    }

    func testAddPlayerSkipsDMAndDuplicatesButUpdatesName() {
        var campaign = Campaign(name: "Lost Mine", joinCode: "123456", dungeonMaster: dm)
        campaign.addPlayer(dm)
        XCTAssertTrue(campaign.players.isEmpty)
        campaign.addPlayer(aria)
        campaign.addPlayer(CampaignMember(id: "player-1", name: "Aria the Bold"))
        XCTAssertEqual(campaign.players, [CampaignMember(id: "player-1", name: "Aria the Bold")])
    }

    func testRoleLabels() {
        XCTAssertEqual(Campaign.Role.dungeonMaster.label, "Dungeon Master")
        XCTAssertEqual(Campaign.Role.player.label, "Player")
    }

    func testBookUpsertAndLeave() {
        var book = CampaignBook()
        var campaign = Campaign(name: "Lost Mine", joinCode: "123456", dungeonMaster: dm)
        book.upsert(campaign)
        campaign.addPlayer(aria)
        book.upsert(campaign)
        XCTAssertEqual(book.campaigns, [campaign])
        XCTAssertTrue(book.contains(code: "123456"))
        book.leave(code: "123456")
        XCTAssertTrue(book.campaigns.isEmpty)
    }

    func testCleanName() throws {
        XCTAssertEqual(try CampaignBook.cleanName("  Night Below ", error: .emptyName), "Night Below")
        XCTAssertThrowsError(try CampaignBook.cleanName(" \n", error: .emptyPlayerName)) {
            XCTAssertEqual($0 as? CampaignError, .emptyPlayerName)
        }
    }
}

final class JoinCodeTests: XCTestCase {
    func testGeneratedCodesAreSixDigits() {
        for _ in 0..<500 {
            let code = JoinCode.generate()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber), code)
            XCTAssertEqual(JoinCode.normalize(code), code)
        }
    }

    func testGeneratedCodesVary() {
        let codes = Set((0..<200).map { _ in JoinCode.generate() })
        XCTAssertGreaterThan(codes.count, 190)
    }

    func testSeededGeneratorIsRepeatable() {
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        XCTAssertEqual(JoinCode.generate(using: &first), JoinCode.generate(using: &second))
    }

    func testNormalize() {
        XCTAssertEqual(JoinCode.normalize(" 042-917 "), "042917")
        XCTAssertEqual(JoinCode.normalize("000000"), "000000")
        for bad in ["", "12345", "1234567", "12345A", "ABCDEF", "١٢٣٤٥٦"] {
            XCTAssertNil(JoinCode.normalize(bad), bad)
        }
    }

    func testDisplay() {
        XCTAssertEqual(JoinCode.display("042917"), "042 917")
        XCTAssertEqual(JoinCode.display("12"), "12")
    }
}

final class InMemoryCampaignDirectoryTests: XCTestCase {
    func testPublishLookupAndAddPlayer() async throws {
        let directory = InMemoryCampaignDirectory()
        try await directory.publish(Campaign(name: "Lost Mine", joinCode: "123456", dungeonMaster: dm))
        let updated = try await directory.addPlayer(aria, toCampaignWithCode: "123456")
        XCTAssertEqual(updated.players, [aria])
        let fetched = try await directory.campaign(forJoinCode: "123456")
        XCTAssertEqual(fetched, updated)
        let missing = try await directory.campaign(forJoinCode: "999999")
        XCTAssertNil(missing)
    }

    func testPublishingATakenCodeFails() async throws {
        let directory = InMemoryCampaignDirectory()
        try await directory.publish(Campaign(name: "A", joinCode: "123456", dungeonMaster: dm))
        do {
            try await directory.publish(Campaign(name: "B", joinCode: "123456", dungeonMaster: aria))
            XCTFail("expected codeTaken")
        } catch {
            XCTAssertEqual(error as? CampaignError, .codeTaken)
        }
    }

    func testAddPlayerToUnknownCodeFails() async {
        let directory = InMemoryCampaignDirectory()
        do {
            _ = try await directory.addPlayer(aria, toCampaignWithCode: "123456")
            XCTFail("expected campaignNotFound")
        } catch {
            XCTAssertEqual(error as? CampaignError, .campaignNotFound)
        }
    }

    func testSampleCampaignUsesAValidCode() async throws {
        XCTAssertEqual(JoinCode.normalize(InMemoryCampaignDirectory.sampleCode), InMemoryCampaignDirectory.sampleCode)
        let sample = try await InMemoryCampaignDirectory.withSamples().campaign(forJoinCode: "123456")
        XCTAssertEqual(sample?.name, "The Sunken Citadel")
    }
}

final class ErrorMessageTests: XCTestCase {
    func testEveryErrorHasAFriendlyMessage() {
        let errors: [LocalizedError] = [
            CharacterError.emptyName, CharacterError.levelOutOfRange,
            CampaignError.emptyName, CampaignError.emptyPlayerName, CampaignError.invalidJoinCode,
            CampaignError.campaignNotFound, CampaignError.alreadyJoined,
            CampaignError.codeTaken, CampaignError.directoryUnavailable
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}

/// Small deterministic generator for repeatable tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
