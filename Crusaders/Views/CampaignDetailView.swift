import SwiftUI
import CrusadersKit

/// One campaign, in two tabs: Party (code, DM, players and their characters) and Inventory.
struct CampaignDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case party = "Party"
        case inventory = "Inventory"
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
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("campaign.error")
                }

                switch tab {
                case .party: party(campaign, manager: manager)
                case .inventory: inventory(campaign, manager: manager)
                }
            }
            .navigationTitle(campaign.name)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await manager.refresh() }
            .sheet(item: $addingTo) { player in
                InventoryItemPicker(player: player) { item, quantity in
                    _ = try await model.addItem(item, quantity: quantity, to: player.id, inCampaign: code)
                }
            }
        } else {
            ContentUnavailableView("Campaign not found", systemImage: "map")
        }
    }

    // MARK: - Party

    @ViewBuilder
    private func party(_ campaign: Campaign, manager: CampaignManager) -> some View {
        Section {
            VStack(spacing: 8) {
                Text("Join code").font(.subheadline).foregroundStyle(.secondary)
                Text(JoinCode.display(campaign.joinCode))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
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

        Section("Dungeon Master") {
            memberRow(campaign.dungeonMaster, isMe: campaign.dungeonMaster.id == manager.me.id)
        }

        Section("Players") {
            if campaign.players.isEmpty {
                Text("No players yet. Share the code to invite your party.")
                    .foregroundStyle(.secondary)
            }
            ForEach(campaign.players) { player in
                memberRow(player, isMe: player.id == manager.me.id)
            }
        }

        if !manager.isShared {
            Section {
                Text("Until iCloud is switched on, campaigns stay on this phone, so friends can't join yet. Try joining the sample campaign with code \(JoinCode.display(InMemoryCampaignDirectory.sampleCode)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memberRow(_ member: CampaignMember, isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(member.name)
                if isMe {
                    Text("(you)").foregroundStyle(.secondary)
                }
            }
            if let character = member.character {
                Text("\(character.name), \(character.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
                .foregroundStyle(.secondary)
        }

        ForEach(players) { player in
            Section {
                let entries = campaign.inventory(of: player.id)
                if entries.isEmpty {
                    Text("No items yet.").foregroundStyle(.secondary)
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
                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                        .accessibilityIdentifier("itemPicker.quantity")
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Tap an item to give it to \(player.character?.name ?? player.name).")
                }
                Section {
                    ForEach(items) { item in
                        Button {
                            Task { await choose(item) }
                        } label: {
                            HStack {
                                Text(item.name).foregroundStyle(.primary)
                                Spacer()
                                Text(item.category.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("itemPicker.item.\(item.id)")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
            .navigationTitle("Add item")
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
