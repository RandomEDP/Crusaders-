import SwiftUI
import CrusadersKit

struct CharactersView: View {
    @Environment(AppModel.self) private var model
    @State private var isCreating = false

    var body: some View {
        Group {
            if model.roster.characters.isEmpty {
                ContentUnavailableView(
                    "No characters yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Tap + to create your first hero.")
                )
            } else {
                List {
                    ForEach(model.roster.characters) { character in
                        NavigationLink {
                            CharacterSheetView(characterID: character.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(character.name).font(.headline)
                                Text(character.summary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("characters.row")
                    }
                    .onDelete { model.deleteCharacters(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("Characters")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isCreating = true
                } label: {
                    Label("New character", systemImage: "plus")
                }
                .accessibilityIdentifier("characters.add")
            }
        }
        .sheet(isPresented: $isCreating) {
            CharacterCreationView()
        }
    }
}

#Preview {
    NavigationStack { CharactersView() }.environment(AppModel())
}
