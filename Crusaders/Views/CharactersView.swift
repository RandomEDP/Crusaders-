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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(character.name).font(.headline)
                            Text(character.summary).font(.subheadline).foregroundStyle(.secondary)
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
            NewCharacterView()
        }
    }
}

struct NewCharacterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var race = ""
    @State private var characterClass = ""
    @State private var level = 1
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("newCharacter.name")
                TextField("Race", text: $race)
                TextField("Class", text: $characterClass)
                Stepper("Level \(level)", value: $level, in: PlayerCharacter.levelRange)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        do {
                            try model.addCharacter(name: name, race: race, characterClass: characterClass, level: level)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("newCharacter.create")
                }
            }
        }
    }
}

#Preview {
    NavigationStack { CharactersView() }.environment(AppModel())
}
