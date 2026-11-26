import SwiftUI
import CrusadersKit

struct CampaignsView: View {
    private enum Sheet: String, Identifiable {
        case create, join
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var sheet: Sheet?

    var body: some View {
        Group {
            if model.campaignBook.campaigns.isEmpty {
                ContentUnavailableView(
                    "No campaigns yet",
                    systemImage: "map",
                    description: Text("Tap + to create a campaign or join one with a code.")
                )
            } else {
                List(model.campaignBook.campaigns) { campaign in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(campaign.name).font(.headline)
                        Text("\(campaign.role.label) · Code \(campaign.joinCode)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("campaigns.row")
                }
            }
        }
        .navigationTitle("Campaigns")
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
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(mode == .create ? "Campaign name" : "Join code", text: $text)
                        .textInputAutocapitalization(mode == .join ? .characters : .words)
                        .autocorrectionDisabled(mode == .join)
                        .accessibilityIdentifier("campaignForm.field")
                } footer: {
                    Text(mode == .create
                         ? "You'll be the Dungeon Master. Share the join code with your players."
                         : "Ask your Dungeon Master for the 6 character code.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(mode == .create ? "Create campaign" : "Join campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Create" : "Join") { submit() }
                        .accessibilityIdentifier("campaignForm.submit")
                }
            }
        }
    }

    private func submit() {
        do {
            switch mode {
            case .create: try model.createCampaign(name: text)
            case .join: try model.joinCampaign(code: text)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { CampaignsView() }.environment(AppModel())
}
