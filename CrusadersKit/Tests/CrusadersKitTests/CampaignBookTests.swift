import XCTest
@testable import CrusadersKit

final class CampaignBookTests: XCTestCase {
    private let directory = InMemoryCampaignDirectory(campaigns: [
        Campaign(name: "Lost Mine", joinCode: "ABC234", role: .dungeonMaster)
    ])

    func testCreateMakesUserTheDungeonMaster() throws {
        var book = CampaignBook()
        let campaign = try book.create(name: "  Curse of the Moon ", joinCode: "MNP223")
        XCTAssertEqual(campaign.name, "Curse of the Moon")
        XCTAssertEqual(campaign.role, .dungeonMaster)
        XCTAssertEqual(campaign.joinCode, "MNP223")
        XCTAssertEqual(book.campaigns, [campaign])
    }

    func testCreateGeneratesValidJoinCodeByDefault() throws {
        var book = CampaignBook()
        let campaign = try book.create(name: "Anything")
        XCTAssertEqual(JoinCode.normalize(campaign.joinCode), campaign.joinCode)
    }

    func testCreateRejectsBlankName() {
        var book = CampaignBook()
        XCTAssertThrowsError(try book.create(name: " ")) {
            XCTAssertEqual($0 as? CampaignError, .emptyName)
        }
    }

    func testJoinWithValidCodeAddsCampaignAsPlayer() throws {
        var book = CampaignBook()
        let joined = try book.join(code: "abc-234", directory: directory)
        XCTAssertEqual(joined.name, "Lost Mine")
        XCTAssertEqual(joined.role, .player)
        XCTAssertEqual(book.campaigns.count, 1)
    }

    func testJoinRejectsMalformedCode() {
        var book = CampaignBook()
        for code in ["", "ABC", "ABC2345", "ABC23O"] {
            XCTAssertThrowsError(try book.join(code: code, directory: directory)) {
                XCTAssertEqual($0 as? CampaignError, .invalidJoinCode, "code: \(code)")
            }
        }
    }

    func testJoinUnknownCodeFails() {
        var book = CampaignBook()
        XCTAssertThrowsError(try book.join(code: "ZZZ999", directory: directory)) {
            XCTAssertEqual($0 as? CampaignError, .campaignNotFound)
        }
    }

    func testJoinTwiceFails() throws {
        var book = CampaignBook()
        try book.join(code: "ABC234", directory: directory)
        XCTAssertThrowsError(try book.join(code: "ABC234", directory: directory)) {
            XCTAssertEqual($0 as? CampaignError, .alreadyJoined)
        }
    }

    func testLeave() throws {
        var book = CampaignBook()
        let campaign = try book.create(name: "Short lived")
        book.leave(id: campaign.id)
        XCTAssertTrue(book.campaigns.isEmpty)
    }

    func testSampleDirectoryCodesAreValid() {
        for code in ["CRUSAD", "EMBER7"] {
            XCTAssertEqual(JoinCode.normalize(code), code)
            XCTAssertNotNil(InMemoryCampaignDirectory.sample.campaign(forJoinCode: code))
        }
    }
}

final class JoinCodeTests: XCTestCase {
    func testGeneratedCodesUseOnlyTheSafeAlphabet() {
        for _ in 0..<200 {
            let code = JoinCode.generate()
            XCTAssertEqual(code.count, JoinCode.length)
            XCTAssertTrue(code.allSatisfy { JoinCode.alphabet.contains($0) }, code)
        }
    }

    func testAlphabetExcludesLookAlikes() {
        for character in "01OIL" {
            XCTAssertFalse(JoinCode.alphabet.contains(character), "\(character) should be excluded")
        }
    }

    func testNormalize() {
        XCTAssertEqual(JoinCode.normalize(" ab c-234 "), "ABC234")
        XCTAssertNil(JoinCode.normalize("ABC23"))
        XCTAssertNil(JoinCode.normalize("ABC23!"))
    }
}

final class ErrorMessageTests: XCTestCase {
    func testEveryErrorHasAFriendlyMessage() {
        let errors: [LocalizedError] = [
            CharacterError.emptyName, CharacterError.levelOutOfRange,
            CampaignError.emptyName, CampaignError.invalidJoinCode,
            CampaignError.campaignNotFound, CampaignError.alreadyJoined
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}
