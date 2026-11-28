import SwiftUI
import CrusadersKit

/// Creator-only form for adding a new creature or changing any part of an existing one's stat block.
struct CreatureEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Creature
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmingRemove = false
    private let isNew: Bool
    /// Called after the creator deletes their own creature, so the detail screen can close too.
    private let onDelete: () -> Void

    init(creature: Creature, isNew: Bool, onDelete: @escaping () -> Void = {}) {
        _draft = State(initialValue: creature)
        self.isNew = isNew
        self.onDelete = onDelete
    }

    var body: some View {
        let catalog = model.creatureLibrary.catalog
        let canReset = !isNew && catalog.isEdited(draft.id)
        let canDelete = !isNew && catalog.isCustom(draft.id)
        NavigationStack {
            Form {
                if let errorMessage {
                    ThemedSection {
                        Text(errorMessage)
                            .foregroundStyle(Theme.crimson)
                            .accessibilityIdentifier("creatureEditor.error")
                    }
                }

                ThemedSection("Basics") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("creatureEditor.name")
                    Picker("Size", selection: $draft.size) {
                        ForEach(CreatureSize.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Type", selection: $draft.type) {
                        ForEach(CreatureType.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("creatureEditor.type")
                    TextField("Subtype (e.g. goblinoid)", text: optionalText($draft.subtype))
                        .textInputAutocapitalization(.never)
                    TextField("Alignment (e.g. neutral evil)", text: $draft.alignment)
                        .textInputAutocapitalization(.never)
                }

                ThemedSection("Defences and speed") {
                    Stepper("Armour Class: \(draft.armorClass)", value: $draft.armorClass, in: 1...30)
                        .accessibilityIdentifier("creatureEditor.ac")
                    TextField("Armour note (e.g. natural armor)", text: optionalText($draft.armorNote))
                        .textInputAutocapitalization(.never)
                    TextField("Hit points", text: number($draft.hitPoints))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("creatureEditor.hp")
                    TextField("Hit dice (e.g. 2d6 or 4d8 + 4)", text: $draft.hitDice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Speed (e.g. 30 ft., fly 60 ft.)", text: $draft.speed)
                        .textInputAutocapitalization(.never)
                }

                ThemedSection("Ability scores") {
                    ForEach(Ability.allCases) { ability in
                        Stepper("\(ability.name): \(draft.abilityText(ability))", value: $draft.abilities[ability], in: 1...30)
                            .accessibilityIdentifier("creatureEditor.\(ability.rawValue)")
                    }
                }

                ThemedSection("Challenge") {
                    Picker("Challenge rating", selection: $draft.challengeRating) {
                        ForEach(ChallengeRating.all, id: \.self) { rating in
                            Text("\(ChallengeRating.text(rating)) (\(ChallengeRating.experience(rating).formatted()) XP)").tag(rating)
                        }
                    }
                    .accessibilityIdentifier("creatureEditor.cr")
                    LabeledContent("Proficiency bonus", value: AbilityScores.signed(draft.proficiencyBonus))
                }

                ThemedSection("Details") {
                    TextField("Saving throws (e.g. Dex +5, Wis +3)", text: optionalText($draft.savingThrows))
                    TextField("Skills (e.g. Stealth +6)", text: optionalText($draft.skills))
                    TextField("Damage vulnerabilities", text: optionalText($draft.damageVulnerabilities))
                    TextField("Damage resistances", text: optionalText($draft.damageResistances))
                    TextField("Damage immunities", text: optionalText($draft.damageImmunities))
                    TextField("Condition immunities", text: optionalText($draft.conditionImmunities))
                    TextField("Senses (e.g. darkvision 60 ft., passive Perception 10)", text: $draft.senses, axis: .vertical)
                    TextField("Languages", text: $draft.languages)
                }

                FeatureListEditor(title: "Traits", noun: "trait", features: $draft.traits, idPrefix: "traits")
                FeatureListEditor(title: "Actions", noun: "action", features: $draft.actions, idPrefix: "actions")
                FeatureListEditor(title: "Reactions", noun: "reaction", features: $draft.reactions, idPrefix: "reactions")
                FeatureListEditor(title: "Legendary actions", noun: "legendary action", features: $draft.legendaryActions, idPrefix: "legendary")

                ThemedSection("Description") {
                    TextEditor(text: optionalText($draft.description))
                        .frame(minHeight: 100)
                        .accessibilityIdentifier("creatureEditor.description")
                }

                if canReset {
                    ThemedSection {
                        Button("Reset to SRD stats", role: .destructive) { confirmingRemove = true }
                            .accessibilityIdentifier("creatureEditor.reset")
                    }
                } else if canDelete {
                    ThemedSection {
                        Button("Delete creature", role: .destructive) { confirmingRemove = true }
                            .accessibilityIdentifier("creatureEditor.delete")
                    }
                }
            }
            .navigationTitle(title)
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("creatureEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .accessibilityIdentifier("creatureEditor.save")
                }
            }
            .confirmationDialog(canDelete ? "Delete this creature?" : "Reset this creature?",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button(canDelete ? "Delete creature" : "Reset to SRD stats", role: .destructive) { remove(deleting: canDelete) }
            } message: {
                Text(canDelete
                     ? "\(draft.name) will be removed from the library for everyone."
                     : "Your edits to \(draft.name) will be removed for everyone.")
            }
        }
    }

    private var title: String {
        if isNew { return "New creature" }
        return "Edit \(draft.name.isEmpty ? "creature" : draft.name)"
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.creatureLibrary.save(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(deleting: Bool) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.creatureLibrary.remove(id: draft.id)
                dismiss()
                if deleting { onDelete() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Edits a whole number as text, keeping the old value while the field is blank or not a number.
    private func number(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: { String(value.wrappedValue) },
            set: { if let number = Int($0.trimmingCharacters(in: .whitespaces)) { value.wrappedValue = number } }
        )
    }
}

/// Add, edit and remove the named entries of one part of a stat block (traits, actions...).
private struct FeatureListEditor: View {
    let title: String
    let noun: String
    @Binding var features: [CreatureFeature]
    let idPrefix: String

    var body: some View {
        ThemedSection {
            ForEach(features.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name", text: field(index, \.name))
                            .font(.serifBold(.body))
                            .accessibilityIdentifier("creatureEditor.\(idPrefix).\(index).name")
                        Button(role: .destructive) {
                            features.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(noun)")
                        .accessibilityIdentifier("creatureEditor.\(idPrefix).\(index).remove")
                    }
                    TextField("What it does", text: field(index, \.description), axis: .vertical)
                        .lineLimit(2...8)
                        .accessibilityIdentifier("creatureEditor.\(idPrefix).\(index).description")
                }
            }
            Button {
                features.append(CreatureFeature(name: "", description: ""))
            } label: {
                Label("Add \(noun)", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .accessibilityIdentifier("creatureEditor.\(idPrefix).add")
        } header: {
            Text(title)
        }
    }

    /// A binding that stays safe while a row is being removed.
    private func field(_ index: Int, _ keyPath: WritableKeyPath<CreatureFeature, String>) -> Binding<String> {
        Binding(
            get: { features.indices.contains(index) ? features[index][keyPath: keyPath] : "" },
            set: { if features.indices.contains(index) { features[index][keyPath: keyPath] = $0 } }
        )
    }
}

/// Edits optional text: blank clears it.
private func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(
        get: { value.wrappedValue ?? "" },
        set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
