import SwiftUI
import CrusadersKit

/// Shows whether this iCloud account can edit library items and creatures, and the ID needed to be added as a creator.
struct CreatorAccessView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.itemLibrary
        let status = library.creatorStatus
        List {
            ThemedSection {
                if library.isLoading {
                    ProgressView()
                } else if status.isCreator {
                    Label("You can add and edit library items and creatures", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("creator.status.creator")
                } else {
                    Label("Viewing only", systemImage: "eye")
                        .accessibilityIdentifier("creator.status.viewer")
                }
                if let problem = status.problem {
                    Text(problem).font(.serif(.footnote)).foregroundStyle(Theme.inkSoft)
                }
            }

            if let userID = status.userID {
                ThemedSection {
                    Text(userID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("Copy iCloud ID") { UIPasteboard.general.string = userID }
                } header: {
                    Text("Your iCloud ID")
                } footer: {
                    Text("To become a creator, this ID is added to the Creator list in the CloudKit Dashboard. Creator edits are shared with every player.")
                }
            }
        }
        .navigationTitle("Creator access")
        .parchmentScreen()
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await model.itemLibrary.refresh()
        await model.creatureLibrary.refresh()
    }
}
