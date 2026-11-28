import SwiftUI
import CrusadersKit

/// One campaign, in three tabs: Party (code, DM, players and their characters), Inventory and Chat.
struct CampaignDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case party = "Party"
        case inventory = "Inventory"
        case combat = "Combat"
        case chat = "Chat"
        var id: String { rawValue }
    }

    let code: String
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .party
    @State private var addingTo: CampaignMember?
    @State private var errorMessage: String?
    @State private var choosingBase: BaseChoice?
    @State private var combatAction: CombatAction?
    @State private var coinAction: CoinAction?

    /// A magic item like "Armor, +1" waiting for the player to say which armour or weapon it is.
    struct BaseChoice: Identifiable {
        let itemID: String
        let itemName: String
        let playerID: String
        let options: [EquipmentItem]
        var id: String { "\(playerID)-\(itemID)" }
    }

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
                case .combat: combat(campaign, manager: manager)
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
            .task(id: campaign.loadoutChanges.count + campaign.inventoryChanges.count) {
                await model.reportStatus(inCampaign: code)
            }
            .sheet(item: $combatAction) { action in
                CombatAmountSheet(action: action) { amount, type in
                    switch action.kind {
                    case .damage: try await model.campaigns.dealDamage(amount, type: type, to: action.player.id, inCampaign: code)
                    case .heal: try await model.campaigns.heal(amount, for: action.player.id, inCampaign: code)
                    case .temporary: try await model.campaigns.giveTemporaryHitPoints(amount, to: action.player.id, inCampaign: code)
                    }
                }
            }
            .sheet(item: $coinAction) { action in
                CoinAmountSheet(action: action) { amount, coin in
                    switch action.kind {
                    case .give: try await model.campaigns.giveCoins(amount, of: coin, to: action.player.id, inCampaign: code)
                    case .spend: try await model.campaigns.spend(Cost(amount: amount, coin: coin), for: action.player.id, inCampaign: code)
                    }
                }
            }
            .sheet(item: $choosingBase) { choice in
                BaseItemPicker(choice: choice) { base in
                    await equip(choice, as: base)
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

    // MARK: - Combat

    /// The round counter, and each character's hit points and effects. The DM deals damage and heals here.
    @ViewBuilder
    private func combat(_ campaign: Campaign, manager: CampaignManager) -> some View {
        let isDM = manager.role(in: campaign) == .dungeonMaster
        let players = isDM ? campaign.players : campaign.players.filter { $0.id == manager.me.id }

        ThemedSection {
            Text("Round \(campaign.round)")
                .font(.gothic(.title2))
                .accessibilityIdentifier("combat.round")
            if isDM {
                Button {
                    Task { await run { try await manager.advanceRounds(1, inCampaign: code) } }
                } label: {
                    Label("Next round", systemImage: "forward.end")
                }
                .accessibilityIdentifier("combat.nextRound")
                Button {
                    Task { await run { try await manager.advanceRounds(PotionEffect.minute, inCampaign: code) } }
                } label: {
                    Label("1 minute passes (10 rounds)", systemImage: "clock")
                }
                .accessibilityIdentifier("combat.nextMinute")
            }
        } footer: {
            Text("1 round is 6 seconds. Potion effects count down as the Dungeon Master moves rounds on.")
        }

        if players.isEmpty {
            Text(isDM ? "No players yet." : "You're not in this campaign's party.")
                .foregroundStyle(Theme.inkSoft)
                .parchmentRow()
        }

        ForEach(players) { player in
            let state = campaign.combatState(of: player.id)
            ThemedSection {
                Text(healthText(for: player, state: state, campaign: campaign, manager: manager))
                    .font(.serifBold(.headline))
                    .accessibilityIdentifier("combat.hp.\(player.id)")
                ForEach(state.activeEffects) { effect in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effect.name)
                            Text(ActiveEffect.timeLeftText(effect.roundsLeft(atRound: state.round)))
                                .font(.serif(.caption))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("combat.effect")
                        Spacer()
                        if isDM || player.id == manager.me.id {
                            Button("End") {
                                Task { await run { try await manager.endEffect(effect.id, for: player.id, inCampaign: code) } }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                if isDM {
                    HStack {
                        combatButton("Damage", "burst", .damage, player)
                        combatButton("Heal", "cross.case", .heal, player)
                        combatButton("Temp HP", "shield.lefthalf.filled", .temporary, player)
                    }
                    Button {
                        Task { await run { try await manager.longRest(player.id, inCampaign: code) } }
                    } label: {
                        Label("Long rest (full HP, end effects)", systemImage: "moon.zzz")
                    }
                    .accessibilityIdentifier("combat.longRest.\(player.id)")
                }
                ForEach(Array(state.events.suffix(5).reversed())) { event in
                    if let note = event.note {
                        Text(note).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                }
            } header: {
                Text(player.character.map { "\($0.name) (\(player.name))" } ?? player.name)
            }
        }
    }

    private func combatButton(_ title: String, _ image: String, _ kind: CombatAction.Kind, _ player: CampaignMember) -> some View {
        Button {
            combatAction = CombatAction(kind: kind, player: player)
        } label: {
            Label(title, systemImage: image).font(.serif(.subheadline))
        }
        .buttonStyle(.bordered)
        .contentShape(Rectangle())
        .accessibilityIdentifier("combat.\(kind.rawValue).\(player.id)")
    }

    /// The player's own phone knows the full sheet; the DM uses the max HP and AC the player's phone reported.
    private func healthText(for player: CampaignMember, state: CombatState, campaign: Campaign, manager: CampaignManager) -> String {
        if player.id == manager.me.id, let characterID = player.character?.id,
           let sheet = model.sheet(for: characterID, campaignCode: campaign.joinCode) {
            return "\(sheet.health.text) · AC \(sheet.armorClass)"
        }
        if let report = state.lastReport {
            return "\(state.health(maxHitPoints: report.maxHitPoints).text) · AC \(report.armorClass)"
        }
        let net = state.netDamage
        return net > 0 ? "\(net) damage taken" : "No damage taken"
    }

    private func run(_ action: () async throws -> Campaign) async {
        do {
            _ = try await action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
                .foregroundStyle(Theme.inkSoft)
        }

        ForEach(players) { player in
            let entries = campaign.inventory(of: player.id)
            let loadout = campaign.loadout(of: player.id).sanitized(inventory: entries, catalog: model.itemLibrary.catalog)
            let canEquip = isDM || player.id == manager.me.id
            ThemedSection {
                if let characterID = player.character?.id, player.id == manager.me.id,
                   let sheet = model.sheet(for: characterID, campaignCode: code) {
                    NavigationLink {
                        CharacterSheetView(characterID: characterID, campaignCode: code)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AC \(sheet.armorClass) · Speed \(sheet.speed) ft")
                                .font(.serifBold(.headline))
                                .accessibilityIdentifier("inventory.summary")
                            Text("Open character sheet").font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .accessibilityIdentifier("inventory.sheet")
                }
                let purse = campaign.purse(of: player.id)
                VStack(alignment: .leading, spacing: 6) {
                    Label(purse.text, systemImage: "dollarsign.circle")
                        .accessibilityIdentifier("inventory.purse.\(player.id)")
                    HStack {
                        if isDM {
                            Button {
                                coinAction = CoinAction(kind: .give, player: player)
                            } label: {
                                Label("Give coins", systemImage: "plus.circle").font(.serif(.subheadline))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("inventory.giveCoins.\(player.id)")
                        }
                        if canEquip && !purse.isEmpty {
                            Button {
                                coinAction = CoinAction(kind: .spend, player: player)
                            } label: {
                                Label("Spend", systemImage: "minus.circle").font(.serif(.subheadline))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("inventory.spendCoins.\(player.id)")
                        }
                    }
                }
                if entries.isEmpty {
                    Text("No items yet.").foregroundStyle(Theme.inkSoft)
                }
                ForEach(entries) { entry in
                    InventoryRow(
                        entry: entry,
                        loadout: loadout,
                        canEquip: canEquip,
                        perform: { action in Task { await perform(action, on: entry, for: player) } },
                        remove: { Task { await remove(entry, from: player) } }
                    )
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
                VStack(alignment: .leading, spacing: 4) {
                    if !loadout.attunedIDs.isEmpty {
                        Text("Attuned to \(loadout.attunedIDs.count) of \(Loadout.maxAttuned) magic items.")
                            .accessibilityIdentifier("inventory.attunement")
                    }
                    if !isDM {
                        Text("Only the Dungeon Master can add items. Tap the shield to wear, wield or attune, and − when you use or drop one.")
                    }
                }
            }
        }
    }

    private func perform(_ action: InventoryRow.Action, on entry: InventoryEntry, for player: CampaignMember) async {
        do {
            switch action {
            case .equip(let slot):
                try await model.equip(entry.itemID, in: slot, for: player.id, inCampaign: code)
            case .use:
                try await model.usePotion(entry.itemID, for: player.id, inCampaign: code)
            case .chooseBase:
                let catalog = model.itemLibrary.catalog
                guard let item = catalog.item(id: entry.itemID) else { return }
                choosingBase = BaseChoice(itemID: item.id, itemName: item.name, playerID: player.id,
                                          options: GearItem.baseOptions(for: item, in: catalog))
                return
            case .unequip:
                try await model.unequip(entry.itemID, for: player.id, inCampaign: code)
            case .bothHands(let both):
                try await model.setUsesBothHands(both, for: player.id, inCampaign: code)
            case .attune:
                try await model.attune(entry.itemID, for: player.id, inCampaign: code)
            case .endAttunement:
                try await model.endAttunement(entry.itemID, for: player.id, inCampaign: code)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Equips a magic item as the armour or weapon picked for it.
    private func equip(_ choice: BaseChoice, as base: EquipmentItem) async {
        let catalog = model.itemLibrary.catalog
        guard let item = catalog.item(id: choice.itemID),
              let slot = GearItem(item: item, base: base).allowedSlots.first else { return }
        do {
            try await model.equip(choice.itemID, in: slot, base: base.id, for: choice.playerID, inCampaign: code)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

/// One inventory line: name, quantity, where it's worn or held, and the equip menu.
struct InventoryRow: View {
    enum Action {
        /// Drink a potion.
        case use
        case equip(EquipSlot)
        /// Pick which armour or weapon a magic item is, then equip it.
        case chooseBase
        case unequip
        case bothHands(Bool)
        case attune
        case endAttunement
    }

    let entry: InventoryEntry
    let loadout: Loadout
    let canEquip: Bool
    let perform: (Action) -> Void
    let remove: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let catalog = model.itemLibrary.catalog
        let gear = loadout.gear(entry.itemID, catalog: catalog)
        let baseOptions = catalog.item(id: entry.itemID).map { GearItem.baseOptions(for: $0, in: catalog) } ?? []
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.name) ×\(entry.quantity)")
                    .accessibilityIdentifier("inventory.item.\(entry.itemID)")
                if let status = status(gear) {
                    Text(status)
                        .font(.serif(.caption))
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityIdentifier("inventory.status.\(entry.itemID)")
                }
            }
            Spacer()
            if canEquip, PotionEffect.srd(entry.itemID) != nil {
                Button {
                    perform(.use)
                } label: {
                    Image(systemName: "flask")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Use \(entry.name)")
                .accessibilityIdentifier("inventory.use.\(entry.itemID)")
            }
            if canEquip, let gear, !gear.allowedSlots.isEmpty || gear.item.requiresAttunement || !baseOptions.isEmpty {
                Menu {
                    menuItems(gear, baseOptions: baseOptions)
                } label: {
                    Image(systemName: loadout.isEquipped(entry.itemID) ? "shield.fill" : "shield")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Equip \(entry.name)")
                .accessibilityIdentifier("inventory.equip.\(entry.itemID)")
            }
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove one \(entry.name)")
            .accessibilityIdentifier("inventory.remove.\(entry.itemID)")
        }
    }

    /// e.g. "Worn", "Main hand · Off hand", "Both hands · Attuned"
    private func status(_ gear: GearItem?) -> String? {
        var parts: [String] = []
        for slot in loadout.slots(of: entry.itemID) {
            if slot == .mainHand, let gear, gear.isTwoHanded || (loadout.usesBothHands && gear.isVersatile) {
                parts.append("Both hands")
            } else {
                parts.append(slot.title)
            }
        }
        if let gear, gear.base != nil, gear.item.weapon == nil, gear.item.armour == nil, !parts.isEmpty {
            parts.insert(gear.name, at: 0)
        }
        if loadout.isAttuned(entry.itemID) { parts.append("Attuned") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func menuItems(_ gear: GearItem, baseOptions: [EquipmentItem]) -> some View {
        let slots = loadout.slots(of: entry.itemID)
        if gear.allowedSlots.isEmpty && !baseOptions.isEmpty {
            Button("Choose what it is and equip…") { perform(.chooseBase) }
        }
        if gear.allowedSlots.contains(.armour) && !slots.contains(.armour) {
            Button("Wear") { perform(.equip(.armour)) }
        }
        if gear.allowedSlots.contains(.shield) && !slots.contains(.shield) {
            Button("Hold shield") { perform(.equip(.shield)) }
        }
        if gear.allowedSlots.contains(.mainHand) && !slots.contains(.mainHand) {
            Button(gear.isTwoHanded ? "Hold in both hands" : "Hold in main hand") { perform(.equip(.mainHand)) }
        }
        if gear.allowedSlots.contains(.offHand) && !slots.contains(.offHand) {
            Button("Hold in off hand") { perform(.equip(.offHand)) }
        }
        if gear.isVersatile && slots.contains(.mainHand) {
            if loadout.usesBothHands {
                Button("Use with one hand") { perform(.bothHands(false)) }
            } else {
                Button("Use with both hands") { perform(.bothHands(true)) }
            }
        }
        if !slots.isEmpty {
            Button(gear.armour != nil && gear.armour?.kind != .shield ? "Take off" : "Put away") { perform(.unequip) }
        }
        if baseOptions.count > 1 && !gear.allowedSlots.isEmpty {
            Button("Change what it is…") { perform(.chooseBase) }
        }
        if gear.item.requiresAttunement {
            if gear.isAttuned {
                Button("End attunement") { perform(.endAttunement) }
            } else {
                Button("Attune (\(loadout.attunedIDs.count) of \(Loadout.maxAttuned) used)") { perform(.attune) }
            }
        }
    }
}

/// Picks which armour or weapon a magic item is, e.g. "Armor, +1" as Chain Mail.
struct BaseItemPicker: View {
    let choice: CampaignDetailView.BaseChoice
    let pick: (EquipmentItem) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ThemedSection {
                    ForEach(choice.options) { option in
                        Button {
                            Task {
                                await pick(option)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).foregroundStyle(Theme.ink)
                                Text(option.summary).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .accessibilityIdentifier("basePicker.item.\(option.id)")
                    }
                } footer: {
                    Text("Which armour or weapon is your \(choice.itemName)?")
                }
            }
            .navigationTitle(choice.itemName)
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Damage, healing or temporary hit points the DM is about to give a player.
struct CombatAction: Identifiable {
    enum Kind: String {
        case damage, heal, temporary
    }

    let kind: Kind
    let player: CampaignMember
    var id: String { "\(kind.rawValue)-\(player.id)" }

    var title: String {
        switch kind {
        case .damage: return "Deal damage"
        case .heal: return "Heal"
        case .temporary: return "Temporary HP"
        }
    }
}

/// Asks the DM how much damage (and what type), healing or temporary HP to give.
struct CombatAmountSheet: View {
    let action: CombatAction
    let apply: (Int, DamageType) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var damageType: DamageType = .none
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ThemedSection {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("combat.amount")
                    if action.kind == .damage {
                        Picker("Damage type", selection: $damageType) {
                            ForEach(DamageType.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.crimson)
                    }
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(action.title)
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { Task { await submit() } }
                        .accessibilityIdentifier("combat.apply")
                }
            }
        }
    }

    private var footer: String {
        let name = action.player.character?.name ?? action.player.name
        switch action.kind {
        case .damage: return "\(name) loses temporary hit points first, then hit points. HP never goes below 0."
        case .heal: return "\(name) can't go above their hit point maximum."
        case .temporary: return "Temporary hit points don't stack: \(name) keeps the higher amount."
        }
    }

    private func submit() async {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            errorMessage = CombatError.invalidAmount.localizedDescription
            return
        }
        do {
            try await apply(amount, damageType)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Coins the DM gives, or a character pays.
struct CoinAction: Identifiable {
    enum Kind: String {
        case give, spend
    }

    let kind: Kind
    let player: CampaignMember
    var id: String { "\(kind.rawValue)-\(player.id)" }
}

/// Asks how many coins of which type to give or pay. Paying breaks bigger coins and gives change if needed.
struct CoinAmountSheet: View {
    let action: CoinAction
    let apply: (Int, Coin) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var coin: Coin = .gp
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ThemedSection {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("coins.amount")
                    Picker("Coin", selection: $coin) {
                        ForEach(Coin.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("coins.coin")
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.crimson)
                    }
                } footer: {
                    Text(action.kind == .spend
                         ? "If you don't have the right coins, a bigger coin is broken and you get change. 1 gp = 100 sp, 1 sp = 100 cp."
                         : "1 gp = 100 sp, 1 sp = 100 cp.")
                }
            }
            .navigationTitle(action.kind == .give ? "Give coins" : "Spend coins")
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action.kind == .give ? "Give" : "Pay") { Task { await submit() } }
                        .accessibilityIdentifier("coins.apply")
                }
            }
        }
    }

    private func submit() async {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            errorMessage = CoinError.invalidAmount.localizedDescription
            return
        }
        do {
            try await apply(amount, coin)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
