import SwiftUI
import CrusadersKit

struct CampaignsView: View {
    private enum Sheet: String, Identifiable {
        case create, join
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var sheet: Sheet?

    private var manager: CampaignManager { model.campaigns }

    var body: some View {
        Group {
            if manager.campaigns.isEmpty {
                ContentUnavailableView(
                    "No campaigns yet",
                    systemImage: "map",
                    description: Text("Tap + to create a campaign or join one with a 6-digit code.")
                )
            } else {
                List {
                    if let problem = manager.refreshError {
                        Label(problem, systemImage: "exclamationmark.icloud")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manager.campaigns) { campaign in
                        NavigationLink {
                            CampaignDetailView(code: campaign.joinCode)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(campaign.name).font(.headline)
                                Text("\(manager.role(in: campaign)?.label ?? "Player") · Code \(JoinCode.display(campaign.joinCode))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("campaigns.row")
                    }
                }
                .refreshable { await manager.refresh() }
            }
        }
        .navigationTitle("Campaigns")
        .task { await manager.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Create campaign", systemImage: "plus.square") { sheet = .create }
                    Button("Join campaign", systemImage: "person.badge.plus") { sheet = .join }
                } label: {
                    Label("Add campaign", systemImage: "plus")
                }
                .accessibilityIdentifier("campaigns.add")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .create: CampaignFormView(mode: .create)
            case .join: CampaignFormView(mode: .join)
            }
        }
    }
}

/// One campaign: its join code, the Dungeon Master and the players.
struct CampaignDetailView: View {
    let code: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let manager = model.campaigns
        if let campaign = manager.campaign(code: code) {
            List {
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
                        .accessibilityIdentifier("campaign.dm")
                }

                Section("Players") {
                    if campaign.players.isEmpty {
                        Text("No players yet. Share the code to invite your party.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(campaign.players) { player in
                        memberRow(player, isMe: player.id == manager.me.id)
                            .accessibilityIdentifier("campaign.player")
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
            .navigationTitle(campaign.name)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await manager.refresh() }
        } else {
            ContentUnavailableView("Campaign not found", systemImage: "map")
        }
    }

    private func memberRow(_ member: CampaignMember, isMe: Bool) -> some View {
        HStack {
            Text(member.name)
            if isMe {
                Text("(you)").foregroundStyle(.secondary)
            }
        }
    }
}

struct CampaignFormView: View {
    enum Mode {
        case create, join
    }

    let mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var yourName = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var created: Campaign?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section {
                        VStack(spacing: 8) {
                            Text("\(created.name) is ready").font(.headline)
                            Text(JoinCode.display(created.joinCode))
                                .font(.system(size: 44, weight: .bold, design: .monospaced))
                                .accessibilityIdentifier("campaignForm.createdCode")
                            Text("You're the Dungeon Master. Give this code to your players.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } else {
                    fields
                }
            }
            .navigationTitle(mode == .create ? "Create campaign" : "Join campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if created != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("campaignForm.done")
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Button(mode == .create ? "Create" : "Join") { Task { await submit() } }
                                .accessibilityIdentifier("campaignForm.submit")
                        }
                    }
                }
            }
            .onAppear {
                if yourName.isEmpty { yourName = model.campaigns.me.name }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        Section {
            if mode == .create {
                TextField("Campaign name", text: $text)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("campaignForm.field")
            } else {
                TextField("6-digit code", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(.title2, design: .monospaced))
                    .accessibilityIdentifier("campaignForm.field")
            }
            TextField("Your name", text: $yourName)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .accessibilityIdentifier("campaignForm.yourName")
        } footer: {
            Text(mode == .create
                 ? "You'll be the Dungeon Master. We'll make a 6-digit code to share with your players."
                 : "Ask your Dungeon Master for the 6-digit code. You'll join as a player.")
        }
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .accessibilityIdentifier("campaignForm.error")
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .create:
                created = try await model.createCampaign(name: text, yourName: yourName)
            case .join:
                try await model.joinCampaign(code: text, yourName: yourName)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { CampaignsView() }.environment(AppModel())
}
