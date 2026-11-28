import SwiftUI
import CrusadersKit

/// One campaign chat: the party chat, or a private chat between the DM and one player.
/// The DM can also narrate: send a line as the story, with no name, e.g. "You hear a voice in your head call your name."
struct CampaignChatView: View {
    let code: String
    let channel: ChatChannel

    /// How often an open chat checks for new messages.
    static let refreshInterval: Duration = .seconds(10)

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var narrate = false
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        let manager = model.campaigns
        if let campaign = manager.campaign(code: code), campaign.canUse(channel, memberID: manager.me.id) {
            let me = manager.me
            let messages = model.chat.messages(in: channel, campaign: campaign, viewer: me)
            ScrollViewReader { proxy in
                List {
                    ThemedSection {
                        Label(campaign.chatAudience(channel, for: me.id),
                              systemImage: channel == .party ? "person.3" : "lock")
                            .font(.serif(.footnote))
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityIdentifier("chat.audience")
                        if let problem = model.chat.problem(in: channel, campaign: campaign) {
                            Text(problem)
                                .font(.serif(.footnote))
                                .foregroundStyle(Theme.crimson)
                                .accessibilityIdentifier("chat.problem")
                        }
                    }

                    if messages.isEmpty {
                        Text("No messages yet.")
                            .foregroundStyle(Theme.inkSoft)
                            .parchmentRow()
                    }
                    ForEach(messages) { message in
                        ChatMessageRow(message: message, isMine: message.senderID == me.id)
                            .id(message.id)
                            .parchmentRow()
                    }
                }
                .onChange(of: messages.last?.id) {
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer(campaign: campaign, me: me)
            }
            .navigationTitle(campaign.chatTitle(channel, for: me.id))
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.chat.load(channel, campaign: campaign, viewer: me) }
            .task(id: channel) {
                while !Task.isCancelled {
                    await model.chat.load(channel, campaign: campaign, viewer: me)
                    try? await Task.sleep(for: Self.refreshInterval)
                }
            }
        } else {
            ContentUnavailableView("Chat not available", systemImage: "lock",
                                   description: Text(ChatError.notAllowed.localizedDescription))
                .parchmentScreen()
        }
    }

    private func composer(campaign: Campaign, me: CampaignMember) -> some View {
        let isDM = campaign.role(of: me.id) == .dungeonMaster
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
        return VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.serif(.footnote))
                    .foregroundStyle(Theme.crimson)
                    .accessibilityIdentifier("chat.error")
            }
            if isDM {
                Button {
                    narrate.toggle()
                } label: {
                    Label(narrate ? "Narrating: sent as the story, no name" : "Narrate",
                          systemImage: narrate ? "scroll.fill" : "scroll")
                        .font(.serif(.subheadline))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("chat.narrate")
                .accessibilityAddTraits(narrate ? .isSelected : [])
            }
            HStack(spacing: 8) {
                TextField(narrate ? "What do they see, hear or feel?" : "Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await send(campaign: campaign, me: me) } }
                    .accessibilityIdentifier("chat.field")
                Button {
                    Task { await send(campaign: campaign, me: me) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat.send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Theme.parchment.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule.opacity(0.5)).frame(height: 1)
        }
    }

    private func send(campaign: Campaign, me: CampaignMember) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await model.chat.send(draft, narration: narrate, in: channel, campaign: campaign, as: me)
            draft = ""
            narrate = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One message: the sender's name and text, or narration in italics with no name.
struct ChatMessageRow: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        if message.isNarration {
            VStack(alignment: .leading, spacing: 2) {
                Text("Narration")
                    .font(.serif(.caption))
                    .foregroundStyle(Theme.inkSoft)
                Text(message.text)
                    .font(.serifItalic(.body))
                    .accessibilityIdentifier("chat.narration")
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(isMine ? "You" : message.senderName)
                        .font(.serifBold(.subheadline))
                        .foregroundStyle(isMine ? Theme.crimson : Theme.ink)
                    Spacer()
                    Text(message.sentAt, style: .time)
                        .font(.serif(.caption))
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(message.text)
                    .accessibilityIdentifier("chat.message")
            }
        }
    }
}
