import SwiftUI
import CrusadersKit

/// One campaign, in three tabs: Party (code, DM, players and their characters), Inventory and Chat.
struct CampaignDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case party = "Party"
        case inventory = "Inventory"
        case chat = "Chat"
        var id: String { rawValue }
    }

    let code: String
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .party
    @State private var addingTo: CampaignMember?
    @State private var errorMessage: String?

    var body: some View {
        let manager = model.campaigns
        if let campaign = manager.campaign(code: code) {
            List {
                Section {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("campaign.tabs")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.crimson)
                        .accessibilityIdentifier("campaign.error")
                        .parchmentRow()
                }

                switch tab {
                case .party: party(campaign, manager: manager)
                case .inventory: inventory(campaign, manager: manager)
                case .chat: chats(campaign, manager: manager)
                }
            }
            .navigationTitle(campaign.name)
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await manager.refresh() }
            .sheet(item: $addingTo) { player in
                InventoryItemPicker(player: player) { item, quantity in
                    _ = try await model.addItem(item, quantity: quantity, to: player.id, inCampaign: code)
                }
            }
        } else {
            ContentUnavailableView("Campaign not found", systemImage: "map")
                .parchmentScreen()
        }
    }

    // MARK: - Party

    @ViewBuilder
    private func party(_ campaign: Campaign, manager: CampaignManager) -> some View {
        ThemedSection {
            VStack(spacing: 8) {
                Text("Join code").font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
                Text(JoinCode.display(campaign.joinCode))
                    .font(.joinCode)
                    .accessibilityIdentifier("campaign.code")
                ShareLink(
                    item: "Join my Crusaders campaign \"\(campaign.name)\" with code \(campaign.joinCode)",
                    preview: SharePreview(campaign.name)
                ) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } footer: {
            Text(manager.role(in: campaign) == .dungeonMaster
                 ? "Players enter this code in Join campaign."
                 : "You joined as a player.")
        }

        ThemedSection("Dungeon Master") {
            memberRow(campaign.dungeonMaster, isMe: campaign.dungeonMaster.id == manager.me.id)
        }

        ThemedSection("Players") {
            if campaign.players.isEmpty {
                Text("No players yet. Share the code to invite your party.")
                    .foregroundStyle(Theme.inkSoft)
            }
            ForEach(campaign.players) { player in
                memberRow(player, isMe: player.id == manager.me.id)
            }
        }

        if !manager.isShared {
            ThemedSection {
                Text("Until iCloud is switched on, campaigns stay on this phone, so friends can't join yet. Try joining the sample campaign with code \(JoinCode.display(InMemoryCampaignDirectory.sampleCode)).")
                    .font(.serif(.footnote))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func memberRow(_ member: CampaignMember, isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(member.name)
                if isMe {
                    Text("(you)").foregroundStyle(Theme.inkSoft)
                }
            }
            if let character = member.character {
                Text("\(character.name), \(character.summary)")
                    .font(.serif(.subheadline))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    // MARK: - Chat

    /// The party chat, then the private chats this person can see (one per player for the DM; their own for a player).
    @ViewBuilder
    private func chats(_ campaign: Campaign, manager: CampaignManager) -> some View {
        let me = manager.me
        let channels = campaign.chatChannels(for: me.id)
        ThemedSection {
            ForEach(channels.filter { $0 == .party }) { channel in
                chatRow(channel, campaign: campaign, me: me)
            }
        } header: {
            Text("Everyone")
        }
        ThemedSection {
            let whispers = channels.filter { $0 != .party }
            if whispers.isEmpty {
                Text("No players yet. Once players join, you can message each of them privately here.")
                    .foregroundStyle(Theme.inkSoft)
            }
            ForEach(whispers) { channel in
                chatRow(channel, campaign: campaign, me: me)
            }
        } header: {
            Text("Private")
        } footer: {
            Text(manager.role(in: campaign) == .dungeonMaster
                 ? "Each private chat is only between you and that player. Use Narrate for things only they experience."
                 : "Only you and the Dungeon Master can read your private chat.")
        }
        .task(id: campaign.players.count) {
            for channel in channels {
                await model.chat.load(channel, campaign: campaign, viewer: me)
            }
        }
    }

    private func chatRow(_ channel: ChatChannel, campaign: Campaign, me: CampaignMember) -> some View {
        NavigationLink {
            CampaignChatView(code: campaign.joinCode, channel: channel)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(campaign.chatTitle(channel, for: me.id),
                      systemImage: channel == .party ? "person.3" : "lock")
                    .font(.serifBold(.headline))
                if let last = model.chat.messages(in: channel, campaign: campaign, viewer: me).last {
                    Text(last.isNarration ? last.text : "\(last.senderName): \(last.text)")
                        .font(.serif(.subheadline))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityIdentifier("chat.channel.\(channel.id)")
    }

    // MARK: - Inventory

    @ViewBuilder
    private func inventory(_ campaign: Campaign, manager: CampaignManager) -> some View {
        let isDM = manager.role(in: campaign) == .dungeonMaster
        // The DM sees every character; a player sees their own.
        let players = isDM ? campaign.players : campaign.players.filter { $0.id == manager.me.id }

        if players.isEmpty {
            Text(isDM ? "No players yet. Once players join, you can give their characters items here."
                      : "You're not in this campaign's party.")
                .foregroundStyle(Theme.inkSoft)
        }

        ForEach(players) { player in
            ThemedSection {
                let entries = campaign.inventory(of: player.id)
                if entries.isEmpty {
                    Text("No items yet.").foregroundStyle(Theme.inkSoft)
                }
                ForEach(entries) { entry in
                    HStack {
                        Text("\(entry.name) ×\(entry.quantity)")
                            .accessibilityIdentifier("inventory.item.\(entry.itemID)")
                        Spacer()
                        Button {
                            Task { await remove(entry, from: player) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove one \(entry.name)")
                        .accessibilityIdentifier("inventory.remove.\(entry.itemID)")
                    }
                }
                if isDM {
                    Button {
                        addingTo = player
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .accessibilityIdentifier("inventory.add")
                }
            } header: {
                Text(player.character.map { "\($0.name) (\(player.name))" } ?? player.name)
            } footer: {
                if !isDM {
                    Text("Only the Dungeon Master can add items. Tap − when you use or drop one.")
                }
            }
        }
    }

    private func remove(_ entry: InventoryEntry, from player: CampaignMember) async {
        do {
            try await model.removeItem(entry.itemID, from: player.id, inCampaign: code)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The DM picks a Library item and how many to give a character.
struct InventoryItemPicker: View {
    let player: CampaignMember
    let add: (EquipmentItem, Int) async throws -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var quantity = 1
    @State private var errorMessage: String?

    var body: some View {
        let items = model.itemLibrary.catalog.items.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        NavigationStack {
            List {
                ThemedSection {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                        .accessibilityIdentifier("itemPicker.quantity")
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.crimson)
                    }
                } footer: {
                    Text("Tap an item to give it to \(player.character?.name ?? player.name).")
                }
                ThemedSection {
                    ForEach(items) { item in
                        Button {
                            Task { await choose(item) }
                        } label: {
                            HStack {
                                Text(item.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(item.category.title).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .accessibilityIdentifier("itemPicker.item.\(item.id)")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
            .navigationTitle("Add item")
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func choose(_ item: EquipmentItem) async {
        do {
            try await add(item, quantity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
