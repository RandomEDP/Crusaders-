import XCTest
@testable import CrusadersKit

private let dm = CampaignMember(id: "dm", name: "Dana")
private let sam = CampaignMember(id: "p1", name: "Sam",
                                 character: CampaignCharacter(id: UUID(), name: "Thorin", summary: "Level 1 Hill Dwarf Fighter"))
private let lee = CampaignMember(id: "p2", name: "Lee")
private let stranger = CampaignMember(id: "x", name: "Nobody")
private let campaign = Campaign(name: "Night Below", joinCode: "424242", dungeonMaster: dm, players: [sam, lee])

final class ChatRulesTests: XCTestCase {
    func testEveryoneInTheCampaignCanUseThePartyChat() {
        XCTAssertTrue(campaign.canUse(.party, memberID: "dm"))
        XCTAssertTrue(campaign.canUse(.party, memberID: "p1"))
        XCTAssertTrue(campaign.canUse(.party, memberID: "p2"))
        XCTAssertFalse(campaign.canUse(.party, memberID: "x"))
    }

    func testPrivateChatIsOnlyForTheDMAndThatPlayer() {
        let samsChat = ChatChannel.whisper(playerID: "p1")
        XCTAssertTrue(campaign.canUse(samsChat, memberID: "dm"))
        XCTAssertTrue(campaign.canUse(samsChat, memberID: "p1"))
        XCTAssertFalse(campaign.canUse(samsChat, memberID: "p2"))
        XCTAssertFalse(campaign.canUse(samsChat, memberID: "x"))
        // No private chat for someone who isn't a player (including the DM).
        XCTAssertFalse(campaign.canUse(.whisper(playerID: "x"), memberID: "dm"))
        XCTAssertFalse(campaign.canUse(.whisper(playerID: "dm"), memberID: "dm"))
    }

    func testDMSeesOnePrivateChatPerPlayerAndPlayersSeeOnlyTheirOwn() {
        XCTAssertEqual(campaign.chatChannels(for: "dm"), [.party, .whisper(playerID: "p1"), .whisper(playerID: "p2")])
        XCTAssertEqual(campaign.chatChannels(for: "p1"), [.party, .whisper(playerID: "p1")])
        XCTAssertEqual(campaign.chatChannels(for: "p2"), [.party, .whisper(playerID: "p2")])
        XCTAssertEqual(campaign.chatChannels(for: "x"), [])
    }

    func testOnlyTheDMCanNarrate() {
        XCTAssertTrue(campaign.allows(ChatMessage(channel: .whisper(playerID: "p1"), senderID: "dm", senderName: "Dana",
                                                  text: "You hear a voice", isNarration: true)))
        XCTAssertFalse(campaign.allows(ChatMessage(channel: .party, senderID: "p1", senderName: "Sam",
                                                   text: "The DM says you win", isNarration: true)))
    }

    func testTitlesAndAudience() {
        let samsChat = ChatChannel.whisper(playerID: "p1")
        XCTAssertEqual(campaign.chatTitle(.party, for: "p1"), "Party")
        XCTAssertEqual(campaign.chatTitle(samsChat, for: "dm"), "Private: Thorin (Sam)")
        XCTAssertEqual(campaign.chatTitle(.whisper(playerID: "p2"), for: "dm"), "Private: Lee")
        XCTAssertEqual(campaign.chatTitle(samsChat, for: "p1"), "Private with Dana (DM)")
        XCTAssertTrue(campaign.chatAudience(samsChat, for: "dm").contains("Only you and Sam"))
    }

    func testChannelIDsRoundTrip() throws {
        for channel in [ChatChannel.party, .whisper(playerID: "ABC-123")] {
            XCTAssertEqual(ChatChannel(id: channel.id), channel)
            let data = try JSONEncoder().encode(channel)
            XCTAssertEqual(try JSONDecoder().decode(ChatChannel.self, from: data), channel)
        }
        XCTAssertNil(ChatChannel(id: "whisper-"))
        XCTAssertNil(ChatChannel(id: "general"))
    }
}

@MainActor
final class CampaignChatTests: XCTestCase {
    private let service = InMemoryChatService()

    /// Each person's phone has its own chat object; they share one service, like one iCloud.
    private func phone() -> CampaignChat { CampaignChat(service: service) }

    func testPartyMessagesReachEveryone() async throws {
        let dmPhone = phone(), samPhone = phone(), leePhone = phone()
        try await dmPhone.send("Welcome, adventurers!", in: .party, campaign: campaign, as: dm)
        try await samPhone.send("  Hello!  ", in: .party, campaign: campaign, as: sam)

        await leePhone.load(.party, campaign: campaign, viewer: lee)
        let texts = leePhone.messages(in: .party, campaign: campaign, viewer: lee).map(\.text)
        XCTAssertEqual(texts, ["Welcome, adventurers!", "Hello!"])
        XCTAssertEqual(leePhone.messages(in: .party, campaign: campaign, viewer: lee).first?.senderName, "Dana")
    }

    func testOtherPlayersCantReadAPrivateChat() async throws {
        let dmPhone = phone(), samPhone = phone(), leePhone = phone()
        let samsChat = ChatChannel.whisper(playerID: "p1")
        try await dmPhone.send("You hear a voice in your head call out your name.", narration: true,
                               in: samsChat, campaign: campaign, as: dm)
        try await samPhone.send("Who's there?", in: samsChat, campaign: campaign, as: sam)

        await samPhone.load(samsChat, campaign: campaign, viewer: sam)
        let seenBySam = samPhone.messages(in: samsChat, campaign: campaign, viewer: sam)
        XCTAssertEqual(seenBySam.map(\.text), ["You hear a voice in your head call out your name.", "Who's there?"])
        XCTAssertEqual(seenBySam.first?.isNarration, true)

        await dmPhone.load(samsChat, campaign: campaign, viewer: dm)
        XCTAssertEqual(dmPhone.messages(in: samsChat, campaign: campaign, viewer: dm).count, 2)

        // Lee can't load it, and nothing leaks into Lee's own chats.
        await leePhone.load(samsChat, campaign: campaign, viewer: lee)
        XCTAssertTrue(leePhone.messages(in: samsChat, campaign: campaign, viewer: lee).isEmpty)
        XCTAssertNotNil(leePhone.problem(in: samsChat, campaign: campaign))
        await leePhone.load(.party, campaign: campaign, viewer: lee)
        await leePhone.load(.whisper(playerID: "p2"), campaign: campaign, viewer: lee)
        XCTAssertTrue(leePhone.messages(in: .party, campaign: campaign, viewer: lee).isEmpty)
        XCTAssertTrue(leePhone.messages(in: .whisper(playerID: "p2"), campaign: campaign, viewer: lee).isEmpty)

        // Even a service that ignores the rules can't make Lee see it.
        do {
            _ = try await service.messages(in: samsChat, campaign: campaign, viewer: lee)
            XCTFail("expected notAllowed")
        } catch {
            XCTAssertEqual(error as? ChatError, .notAllowed)
        }
    }

    func testPlayersCantPostInSomeoneElsesPrivateChat() async {
        await assertThrows(.notAllowed) {
            try await self.phone().send("Psst", in: .whisper(playerID: "p1"), campaign: campaign, as: lee)
        }
        await assertThrows(.notAllowed) {
            try await self.phone().send("Hi", in: .party, campaign: campaign, as: stranger)
        }
    }

    func testOnlyTheDMCanSendNarration() async {
        await assertThrows(.onlyDungeonMasterCanNarrate) {
            try await self.phone().send("A dragon appears", narration: true, in: .party, campaign: campaign, as: sam)
        }
    }

    func testEmptyAndOverlongMessagesAreRejected() async {
        await assertThrows(.emptyMessage) {
            try await self.phone().send("   \n", in: .party, campaign: campaign, as: sam)
        }
        await assertThrows(.messageTooLong) {
            try await self.phone().send(String(repeating: "a", count: CampaignChat.maxLength + 1),
                                        in: .party, campaign: campaign, as: sam)
        }
    }

    func testMessagesThatBreakTheRulesAreDroppedOnLoad() async throws {
        // A service with a forged message in it: Lee posing in Sam's private chat, and a player narrating.
        let forged = ChatMessage(channel: .whisper(playerID: "p1"), senderID: "p2", senderName: "Lee", text: "Forged")
        let fakeNarration = ChatMessage(channel: .party, senderID: "p1", senderName: "Sam", text: "Fake", isNarration: true)
        let leaky = LeakyChatService(messages: [forged, fakeNarration])
        let samPhone = CampaignChat(service: leaky)
        await samPhone.load(.whisper(playerID: "p1"), campaign: campaign, viewer: sam)
        await samPhone.load(.party, campaign: campaign, viewer: sam)
        XCTAssertTrue(samPhone.messages(in: .whisper(playerID: "p1"), campaign: campaign, viewer: sam).isEmpty)
        XCTAssertTrue(samPhone.messages(in: .party, campaign: campaign, viewer: sam).isEmpty)
    }

    func testMessagesAreInOrderAndNotDuplicated() async throws {
        let samPhone = phone()
        let later = Date(timeIntervalSince1970: 2_000)
        let earlier = Date(timeIntervalSince1970: 1_000)
        try await samPhone.send("Second", in: .party, campaign: campaign, as: sam, now: later)
        try await samPhone.send("First", in: .party, campaign: campaign, as: sam, now: earlier)
        await samPhone.load(.party, campaign: campaign, viewer: sam)
        await samPhone.load(.party, campaign: campaign, viewer: sam)
        XCTAssertEqual(samPhone.messages(in: .party, campaign: campaign, viewer: sam).map(\.text), ["First", "Second"])
    }

    func testFailuresShowAProblemAndKeepLoadedMessages() async throws {
        let failing = FailingChatService()
        let samPhone = CampaignChat(service: failing)
        await samPhone.load(.party, campaign: campaign, viewer: sam)
        XCTAssertEqual(samPhone.problem(in: .party, campaign: campaign), ChatError.unavailable.localizedDescription)
        await assertThrows(.unavailable) {
            try await samPhone.send("Hi", in: .party, campaign: campaign, as: sam)
        }
    }

    func testSampleCampaignHasAWelcomeMessage() async throws {
        let sample = try XCTUnwrap(InMemoryCampaignDirectory.sampleCampaigns.first)
        var joined = sample
        joined.addPlayer(sam)
        let chat = CampaignChat(service: InMemoryChatService.withSamples())
        await chat.load(.party, campaign: joined, viewer: sam)
        XCTAssertEqual(chat.messages(in: .party, campaign: joined, viewer: sam).first?.senderName, "Sample DM")
    }

    private func assertThrows(_ expected: ChatError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ChatError, expected, file: file, line: line)
        }
    }
}

/// Returns whatever it holds, ignoring the rules, to check the chat drops bad messages itself.
private struct LeakyChatService: ChatService {
    let messages: [ChatMessage]
    func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async throws -> [ChatMessage] {
        messages.filter { $0.channel == channel }
    }
    func send(_ message: ChatMessage, campaign: Campaign) async throws {}
}

private struct FailingChatService: ChatService {
    struct Offline: Error {}
    func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async throws -> [ChatMessage] {
        throw Offline()
    }
    func send(_ message: ChatMessage, campaign: Campaign) async throws { throw Offline() }
}
