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
                            .font(.serif(.footnote))
                            .foregroundStyle(Theme.inkSoft)
                            .parchmentRow()
                    }
                    ForEach(manager.campaigns) { campaign in
                        NavigationLink {
                            CampaignDetailView(code: campaign.joinCode)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(campaign.name).font(.serifBold(.headline))
                                Text("\(manager.role(in: campaign)?.label ?? "Player") · Code \(JoinCode.display(campaign.joinCode))")
                                    .font(.serif(.subheadline))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .accessibilityIdentifier("campaigns.row")
                        .parchmentRow()
                    }
                }
                .refreshable { await manager.refresh() }
            }
        }
        .navigationTitle("Campaigns")
        .parchmentScreen()
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
    @State private var characterID: PlayerCharacter.ID?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    ThemedSection {
                        VStack(spacing: 8) {
                            Text("\(created.name) is ready").font(.serifBold(.headline))
                            Text(JoinCode.display(created.joinCode))
                                .font(.joinCode)
                                .accessibilityIdentifier("campaignForm.createdCode")
                            Text("You're the Dungeon Master. Give this code to your players.")
                                .font(.serif(.subheadline))
                                .foregroundStyle(Theme.inkSoft)
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
            .parchmentScreen()
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
                if characterID == nil { characterID = model.roster.characters.first?.id }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        ThemedSection {
            if mode == .create {
                TextField("Campaign name", text: $text)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("campaignForm.field")
            } else {
                TextField("6-digit code", text: $text)
                    .keyboardType(.numberPad)
                    .font(.serifBold(.title2).monospacedDigit())
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
        if mode == .join {
            ThemedSection("Your character") {
                if model.roster.characters.isEmpty {
                    Text("Create a character in Characters first, then come back to join.")
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityIdentifier("campaignForm.noCharacters")
                }
                ForEach(model.roster.characters) { character in
                    Button {
                        characterID = character.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(character.name).foregroundStyle(Theme.ink)
                                Text(character.summary).font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            if characterID == character.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("campaignForm.character")
                    .accessibilityValue(characterID == character.id ? "Selected" : "")
                }
            }
        }
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(Theme.crimson)
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
                try await model.joinCampaign(code: text, yourName: yourName, characterID: characterID)
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
