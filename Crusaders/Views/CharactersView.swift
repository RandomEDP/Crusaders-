import SwiftUI
import UniformTypeIdentifiers
import CrusadersKit

struct CharactersView: View {
    @Environment(AppModel.self) private var model
    @State private var isCreating = false
    @State private var isPickingPDF = false

    var body: some View {
        Group {
            if model.roster.characters.isEmpty {
                ContentUnavailableView(
                    "No characters yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Tap + to create your first hero, or import one from D&D Beyond.")
                )
            } else {
                List {
                    ForEach(model.roster.characters) { character in
                        NavigationLink {
                            CharacterSheetView(characterID: character.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(character.name).font(.serifBold(.headline))
                                Text(character.summary).font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .accessibilityIdentifier("characters.row")
                        .parchmentRow()
                    }
                    .onDelete { model.deleteCharacters(atOffsets: $0) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StorageNote(mode: model.characterStorageMode, problem: model.characterStorageProblem)
        }
        .navigationTitle("Characters")
        .parchmentScreen()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isCreating = true
                } label: {
                    Label("New character", systemImage: "plus")
                }
                .accessibilityIdentifier("characters.add")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPickingPDF = true
                } label: {
                    Label("Import from D&D Beyond", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("characters.import")
            }
        }
        .sheet(isPresented: $isCreating) {
            CharacterCreationView()
        }
        // Pick a character sheet PDF exported from D&D Beyond. It's read on the phone; nothing is uploaded.
        .fileImporter(isPresented: $isPickingPDF, allowedContentTypes: [UTType.pdf]) { result in
            switch result {
            case .success(let url): model.openSheetPDF(at: url)
            case .failure(let error): model.importProblem = error.localizedDescription
            }
        }
    }
}

/// Tells the player where their characters are saved, and shows save errors.
private struct StorageNote: View {
    let mode: CharacterPersistence.Mode
    let problem: String?

    var body: some View {
        if let text = problem ?? message {
            Label(text, systemImage: icon)
                .font(.serif(.footnote))
                .foregroundStyle(problem == nil ? AnyShapeStyle(Theme.inkSoft) : AnyShapeStyle(Theme.crimson))
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.parchment)
                .accessibilityIdentifier("characters.storage")
        }
    }

    private var message: String? {
        switch mode {
        case .iCloud: return "Saved to iCloud and synced to your devices."
        case .device: return "Saved on this device. iCloud sync turns on once iCloud is set up for the app."
        case .memory(let reason): return reason
        }
    }

    private var icon: String {
        if problem != nil { return "exclamationmark.icloud" }
        switch mode {
        case .iCloud: return "checkmark.icloud"
        case .device: return "iphone"
        case .memory: return "exclamationmark.triangle"
        }
    }
}

#Preview {
    NavigationStack { CharactersView() }.environment(AppModel())
}
