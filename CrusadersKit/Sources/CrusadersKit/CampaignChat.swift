import Foundation
import Observation

/// Where a chat message lives in a campaign.
public enum ChatChannel: Hashable, Codable, Sendable, Identifiable {
    /// The whole table: the DM and every player.
    case party
    /// Private between the DM and one player. No other player can read it.
    case whisper(playerID: String)

    public var id: String {
        switch self {
        case .party: return "party"
        case .whisper(let playerID): return "whisper-\(playerID)"
        }
    }

    /// The player in a private chat, or nil for the party chat.
    public var whisperPlayerID: String? {
        if case .whisper(let playerID) = self { return playerID }
        return nil
    }

    /// Turns `id` back into a channel.
    public init?(id: String) {
        if id == "party" {
            self = .party
        } else if id.hasPrefix("whisper-"), id.count > "whisper-".count {
            self = .whisper(playerID: String(id.dropFirst("whisper-".count)))
        } else {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let channel = ChatChannel(id: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown channel \(raw)"))
        }
        self = channel
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// One message in a campaign chat.
public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var channel: ChatChannel
    public var senderID: String
    public var senderName: String
    public var text: String
    /// The DM speaking as the story rather than as themselves, e.g. "You hear a voice in your head call your name."
    /// Shown in italics without a name. Only the DM can narrate.
    public var isNarration: Bool
    public var sentAt: Date

    public init(
        id: UUID = UUID(),
        channel: ChatChannel,
        senderID: String,
        senderName: String,
        text: String,
        isNarration: Bool = false,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.channel = channel
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.isNarration = isNarration
        self.sentAt = sentAt
    }
}

public enum ChatError: Error, Equatable, Sendable {
    case emptyMessage
    case messageTooLong
    /// The person isn't the DM or the player in this private chat (or isn't in the campaign at all).
    case notAllowed
    /// Only the DM can send narration.
    case onlyDungeonMasterCanNarrate
    /// The player opened their private chat before the DM's phone has set it up.
    case privateChatNotReady
    /// iCloud couldn't be reached.
    case unavailable
}

extension Campaign {
    /// Whether this person can read and write in a channel: everyone in the campaign can use
    /// the party chat, but a private chat is only for the DM and that one player.
    public func canUse(_ channel: ChatChannel, memberID: String) -> Bool {
        guard let role = role(of: memberID) else { return false }
        switch channel {
        case .party:
            return true
        case .whisper(let playerID):
            guard player(id: playerID) != nil else { return false }
            return role == .dungeonMaster || memberID == playerID
        }
    }

    /// The chats this person can see: the party chat, then one private chat per player for the DM,
    /// or just their own private chat with the DM for a player.
    public func chatChannels(for memberID: String) -> [ChatChannel] {
        switch role(of: memberID) {
        case .dungeonMaster:
            return [.party] + players.map { .whisper(playerID: $0.id) }
        case .player:
            return [.party, .whisper(playerID: memberID)]
        case nil:
            return []
        }
    }

    /// Whether this message obeys the rules: the sender may use the channel, and only the DM narrates.
    public func allows(_ message: ChatMessage) -> Bool {
        guard canUse(message.channel, memberID: message.senderID) else { return false }
        return !message.isNarration || message.senderID == dungeonMaster.id
    }

    /// A channel's title as this person sees it, e.g. "Party", "Private: Thorin (Sam)" or "Private with Dana (DM)".
    public func chatTitle(_ channel: ChatChannel, for memberID: String) -> String {
        switch channel {
        case .party:
            return "Party"
        case .whisper(let playerID):
            if memberID == dungeonMaster.id {
                guard let player = player(id: playerID) else { return "Private" }
                return "Private: " + (player.character.map { "\($0.name) (\(player.name))" } ?? player.name)
            }
            return "Private with \(dungeonMaster.name) (DM)"
        }
    }

    /// Who else can read a channel, for the note at the top of a chat.
    public func chatAudience(_ channel: ChatChannel, for memberID: String) -> String {
        switch channel {
        case .party:
            return "Everyone in the campaign can read the party chat."
        case .whisper(let playerID):
            if memberID == dungeonMaster.id {
                let name = player(id: playerID)?.name ?? "this player"
                return "Only you and \(name) can read this. The other players can't see it."
            }
            return "Only you and the Dungeon Master can read this. The other players can't see it."
        }
    }
}

/// Stores and fetches chat messages. The app uses CloudKit once iCloud is switched on
/// (the party chat in the public database, private chats in a CloudKit share between the DM and one player);
/// until then, and in tests, it uses `InMemoryChatService`.
///
/// Implementations must only return a private chat to the DM and that player.
public protocol ChatService: Sendable {
    /// Messages in a channel, as `viewer` is allowed to see them.
    func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async throws -> [ChatMessage]
    /// Saves a message the sender is allowed to send.
    func send(_ message: ChatMessage, campaign: Campaign) async throws
}

/// Keeps chats in memory and enforces the privacy rules, the way the CloudKit share does on the server.
public actor InMemoryChatService: ChatService {
    private var messages: [String: [ChatMessage]]

    public init(messages: [String: [ChatMessage]] = [:]) {
        self.messages = messages
    }

    public func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async throws -> [ChatMessage] {
        guard campaign.canUse(channel, memberID: viewer.id) else { throw ChatError.notAllowed }
        return messages[Self.key(campaign.joinCode, channel), default: []]
    }

    public func send(_ message: ChatMessage, campaign: Campaign) async throws {
        guard campaign.allows(message) else { throw ChatError.notAllowed }
        let key = Self.key(campaign.joinCode, message.channel)
        guard !messages[key, default: []].contains(where: { $0.id == message.id }) else { return }
        messages[key, default: []].append(message)
    }

    static func key(_ code: String, _ channel: ChatChannel) -> String {
        "\(code)/\(channel.id)"
    }

    /// A welcome message in the sample campaign's party chat, so the chat isn't empty when people try it.
    public static func withSamples() -> InMemoryChatService {
        let welcome = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            channel: .party, senderID: "sample-dm", senderName: "Sample DM",
            text: "Welcome to the Sunken Citadel! Say hello to the party here.",
            sentAt: Date(timeIntervalSince1970: 0)
        )
        return InMemoryChatService(messages: [key(InMemoryCampaignDirectory.sampleCode, .party): [welcome]])
    }
}

/// The chats in the user's campaigns: loading, sending and the rules about who sees what.
@MainActor
@Observable
public final class CampaignChat {
    /// Longest message, so one paste can't flood the table.
    public static let maxLength = 2000

    /// Loaded messages, oldest first, by campaign code and channel.
    public private(set) var loaded: [String: [ChatMessage]] = [:]
    /// The last loading problem for each chat, shown above its messages.
    public private(set) var problems: [String: String] = [:]

    private let service: ChatService

    public init(service: ChatService) {
        self.service = service
    }

    private func key(_ campaign: Campaign, _ channel: ChatChannel) -> String {
        InMemoryChatService.key(campaign.joinCode, channel)
    }

    /// Messages already loaded for a chat that `viewer` may read. Empty for anyone else.
    public func messages(in channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) -> [ChatMessage] {
        guard campaign.canUse(channel, memberID: viewer.id) else { return [] }
        return loaded[key(campaign, channel), default: []]
    }

    public func problem(in channel: ChatChannel, campaign: Campaign) -> String? {
        problems[key(campaign, channel)]
    }

    /// Fetches the latest messages. Messages that break the rules are dropped, even if the server returned them.
    public func load(_ channel: ChatChannel, campaign: Campaign, viewer: CampaignMember) async {
        let key = key(campaign, channel)
        guard campaign.canUse(channel, memberID: viewer.id) else {
            loaded[key] = nil
            problems[key] = ChatError.notAllowed.localizedDescription
            return
        }
        do {
            let fetched = try await service.messages(in: channel, campaign: campaign, viewer: viewer)
            merge(fetched, into: key, campaign: campaign, channel: channel)
            problems[key] = nil
        } catch let error as ChatError {
            problems[key] = error.localizedDescription
        } catch {
            problems[key] = ChatError.unavailable.localizedDescription
        }
    }

    /// Sends a message. Narration (the DM speaking as the story) is only for the DM.
    @discardableResult
    public func send(
        _ rawText: String,
        narration: Bool = false,
        in channel: ChatChannel,
        campaign: Campaign,
        as sender: CampaignMember,
        now: Date = Date()
    ) async throws -> ChatMessage {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChatError.emptyMessage }
        guard text.count <= Self.maxLength else { throw ChatError.messageTooLong }
        guard campaign.canUse(channel, memberID: sender.id) else { throw ChatError.notAllowed }
        guard !narration || campaign.role(of: sender.id) == .dungeonMaster else { throw ChatError.onlyDungeonMasterCanNarrate }

        let name = campaign.role(of: sender.id) == .dungeonMaster ? campaign.dungeonMaster.name
            : (campaign.player(id: sender.id)?.name ?? sender.name)
        let message = ChatMessage(channel: channel, senderID: sender.id, senderName: name,
                                  text: text, isNarration: narration, sentAt: now)
        do {
            try await service.send(message, campaign: campaign)
        } catch let error as ChatError {
            throw error
        } catch {
            throw ChatError.unavailable
        }
        merge([message], into: key(campaign, channel), campaign: campaign, channel: channel)
        return message
    }

    private func merge(_ incoming: [ChatMessage], into key: String, campaign: Campaign, channel: ChatChannel) {
        var byID = Dictionary(loaded[key, default: []].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for message in incoming where message.channel == channel && campaign.allows(message) {
            byID[message.id] = message
        }
        loaded[key] = byID.values.sorted { ($0.sentAt, $0.id.uuidString) < ($1.sentAt, $1.id.uuidString) }
    }
}
