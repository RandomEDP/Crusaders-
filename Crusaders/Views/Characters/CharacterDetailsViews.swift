import SwiftUI
import CrusadersKit

/// Sheet sections every character has: background and alignment, languages, proficiencies and feats,
/// limited uses to tick off, and a link to the character's lore.
struct CharacterDetailsSections: View {
    @Environment(AppModel.self) private var model
    let character: PlayerCharacter
    /// The campaign whose party chat gets ability rolls.
    var campaignCode: String? = nil
    /// Show the rest buttons even with no limited uses, so spell slots can come back.
    var hasSpellSlots = false
    var outcome: Binding<ActionOutcome?>? = nil
    var actionError: Binding<String?>? = nil
    @State private var isEditing = false

    var body: some View {
        ThemedSection("Background, languages and feats") {
            row("Background", character.background)
            row("Alignment", character.alignment)
            row("Languages", character.languages.joined(separator: ", "))
            row("Armor", character.armorProficiencies.joined(separator: ", "))
            row("Weapons", character.weaponProficiencies.joined(separator: ", "))
            row("Tools", character.toolProficiencies.joined(separator: ", "))
            row("Feats", character.feats.joined(separator: ", "))
            Button {
                isEditing = true
            } label: {
                Label("Edit details and limited uses", systemImage: "pencil")
            }
            .accessibilityIdentifier("sheet.editDetails")
            .sheet(isPresented: $isEditing) {
                CharacterDetailsEditor(character: character)
            }
        }

        if !character.resources.isEmpty || hasSpellSlots {
            ThemedSection {
                ForEach(character.resources) { resource in
                    ResourceRow(resource: resource) {
                        use(resource)
                    } restore: {
                        model.updateCharacter(character.id) { $0.restoreResource(resource.id) }
                    }
                }
                HStack {
                    Button("Short rest") { model.updateCharacter(character.id) { $0.rest(long: false) } }
                        .accessibilityIdentifier("sheet.shortRest")
                    Spacer()
                    Button("Long rest") { model.updateCharacter(character.id) { $0.rest(long: true) } }
                        .accessibilityIdentifier("sheet.longRest")
                }
                .buttonStyle(.borderless)
            } header: {
                Text(character.resources.isEmpty ? "Rests" : "Limited uses")
            } footer: {
                Text(character.resources.isEmpty
                     ? "A long rest brings back every spell slot."
                     : "Tap − to use an ability. Its roll goes in the party chat. Rests bring uses and spell slots back.")
            }
        }

        ThemedSection("Lore") {
            ForEach(character.lore.filled.prefix(3), id: \.label) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label).font(.serifBold(.subheadline))
                    Text(entry.text).font(.serif(.footnote)).lineLimit(3)
                }
            }
            NavigationLink {
                LoreView(characterID: character.id)
            } label: {
                Label(character.lore.isEmpty ? "Write backstory and lore" : "All lore", systemImage: "book.closed")
            }
            .accessibilityIdentifier("sheet.lore")
        }
    }

    /// Spends one use, rolls any dice in the ability's detail, and posts it in the party chat.
    private func use(_ resource: CharacterResource) {
        Task {
            do {
                let result = try await model.useAbility(resource.id, characterID: character.id, campaignCode: campaignCode)
                if let outcome { outcome.wrappedValue = result }
                if let actionError { actionError.wrappedValue = nil }
            } catch {
                if let actionError { actionError.wrappedValue = error.localizedDescription }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }
}

private struct ResourceRow: View {
    let resource: CharacterResource
    let use: () -> Void
    let restore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.name).font(.serifBold(.subheadline))
                Text([("\(resource.remaining) of \(resource.uses) left · \(resource.recharge)"), resource.detail].compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.serif(.caption))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button(action: restore) { Image(systemName: "arrow.uturn.backward.circle") }
                .disabled(resource.used == 0)
                .accessibilityLabel("Give back one \(resource.name)")
            Button(action: use) { Image(systemName: "minus.circle.fill") }
                .disabled(resource.remaining == 0)
                .accessibilityLabel("Use one \(resource.name)")
                .accessibilityIdentifier("resource.use")
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .accessibilityElement(children: .contain)
    }
}

/// Edits background, alignment, languages, proficiencies, feats and limited uses.
struct CharacterDetailsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let characterID: PlayerCharacter.ID

    @State private var background: String
    @State private var alignment: String
    @State private var languages: String
    @State private var armor: String
    @State private var weapons: String
    @State private var tools: String
    @State private var feats: String
    @State private var resources: [CharacterResource]

    init(character: PlayerCharacter) {
        characterID = character.id
        _background = State(initialValue: character.background)
        _alignment = State(initialValue: character.alignment)
        _languages = State(initialValue: character.languages.joined(separator: ", "))
        _armor = State(initialValue: character.armorProficiencies.joined(separator: ", "))
        _weapons = State(initialValue: character.weaponProficiencies.joined(separator: ", "))
        _tools = State(initialValue: character.toolProficiencies.joined(separator: ", "))
        _feats = State(initialValue: character.feats.joined(separator: ", "))
        _resources = State(initialValue: character.resources)
    }

    var body: some View {
        NavigationStack {
            Form {
                ThemedSection("Who they are") {
                    TextField("Background", text: $background).accessibilityIdentifier("details.background")
                    TextField("Alignment", text: $alignment).accessibilityIdentifier("details.alignment")
                }
                ThemedSection {
                    TextField("Languages", text: $languages, axis: .vertical).accessibilityIdentifier("details.languages")
                    TextField("Armor", text: $armor, axis: .vertical)
                    TextField("Weapons", text: $weapons, axis: .vertical)
                    TextField("Tools", text: $tools, axis: .vertical)
                    TextField("Feats", text: $feats, axis: .vertical).accessibilityIdentifier("details.feats")
                } header: {
                    Text("Languages, proficiencies and feats")
                } footer: {
                    Text("Separate entries with commas.")
                }
                ThemedSection {
                    ForEach($resources) { $resource in
                        VStack(alignment: .leading) {
                            TextField("Name", text: $resource.name)
                            Stepper("\(resource.uses) uses", value: $resource.uses, in: 0...99)
                            Picker("Comes back on", selection: $resource.recharge) {
                                ForEach(rechargeChoices(resource.recharge), id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    .onDelete { resources.remove(atOffsets: $0) }
                    Button {
                        resources.append(CharacterResource(name: "", uses: 1))
                    } label: {
                        Label("Add a limited use", systemImage: "plus")
                    }
                    .accessibilityIdentifier("details.addResource")
                } header: {
                    Text("Limited uses")
                } footer: {
                    Text("Things like Sorcery Points or a Breath Weapon. Swipe to remove one.")
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .parchmentScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("details.save")
                }
            }
        }
    }

    private func rechargeChoices(_ current: String) -> [String] {
        CharacterResource.recharges.contains(current) ? CharacterResource.recharges : [current] + CharacterResource.recharges
    }

    private func save() {
        let kept = resources
            .map { resource -> CharacterResource in
                var trimmed = resource
                trimmed.name = resource.name.trimmingCharacters(in: .whitespaces)
                trimmed.used = min(resource.used, resource.uses)
                return trimmed
            }
            .filter { !$0.name.isEmpty }
        model.updateCharacter(characterID) { character in
            character.background = background.trimmingCharacters(in: .whitespaces)
            character.alignment = alignment.trimmingCharacters(in: .whitespaces)
            character.languages = PlayerCharacter.list(from: languages)
            character.armorProficiencies = PlayerCharacter.list(from: armor)
            character.weaponProficiencies = PlayerCharacter.list(from: weapons)
            character.toolProficiencies = PlayerCharacter.list(from: tools)
            character.feats = PlayerCharacter.list(from: feats)
            character.resources = kept
        }
        dismiss()
    }
}

/// The character's profile lore: backstory, beliefs, looks and other world-building. Saved as you type.
struct LoreView: View {
    @Environment(AppModel.self) private var model
    let characterID: PlayerCharacter.ID

    var body: some View {
        Form {
            ThemedSection {
                ForEach(Array(CharacterLore.fields.enumerated()), id: \.offset) { _, field in
                    if field.isLong {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.serifBold(.subheadline))
                            TextField(field.label, text: binding(field.keyPath), axis: .vertical)
                                .lineLimit(3...12)
                                .accessibilityIdentifier("lore.\(field.label)")
                        }
                    } else {
                        LabeledContent(field.label) {
                            TextField(field.label, text: binding(field.keyPath))
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("lore.\(field.label)")
                        }
                    }
                }
            } footer: {
                Text("Backstory, beliefs, looks and anything else about who your character is.")
            }
        }
        .navigationTitle("Lore")
        .parchmentScreen()
    }

    private func binding(_ keyPath: WritableKeyPath<CharacterLore, String>) -> Binding<String> {
        Binding(
            get: { model.character(id: characterID)?.lore[keyPath: keyPath] ?? "" },
            set: { text in model.updateCharacter(characterID) { $0.lore[keyPath: keyPath] = text } }
        )
    }
}
