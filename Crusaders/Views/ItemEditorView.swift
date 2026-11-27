import SwiftUI
import CrusadersKit

/// Creator-only form for changing any characteristic of an item.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EquipmentItem
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmingReset = false

    init(item: EquipmentItem) {
        _draft = State(initialValue: item)
    }

    var body: some View {
        let library = model.itemLibrary
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("itemEditor.error")
                    }
                }

                Section("Basics") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("itemEditor.name")
                    Picker("Category", selection: $draft.category) {
                        ForEach(ItemCategory.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Sub-heading (e.g. Martial Melee)", text: $draft.group)
                        .accessibilityIdentifier("itemEditor.group")
                }

                Section("Cost and weight") {
                    Toggle("Has a cost", isOn: hasCost)
                    if draft.cost != nil {
                        TextField("Amount", text: costAmount)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("itemEditor.costAmount")
                        Picker("Coin", selection: costCoin) {
                            ForEach(Coin.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    TextField("Weight (lb)", text: weight)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("itemEditor.weight")
                }

                Section("Magic") {
                    Picker("Rarity", selection: $draft.rarity) {
                        Text("Not magic").tag(Rarity?.none)
                        ForEach(Rarity.allCases) { Text($0.title).tag(Rarity?.some($0)) }
                    }
                    Toggle("Requires attunement", isOn: $draft.requiresAttunement)
                }

                Section {
                    Toggle("Weapon stats", isOn: hasWeapon)
                        .accessibilityIdentifier("itemEditor.hasWeapon")
                    if let weapon = Binding($draft.weapon) {
                        WeaponFields(weapon: weapon)
                    }
                }

                Section {
                    Toggle("Armour stats", isOn: hasArmour)
                        .accessibilityIdentifier("itemEditor.hasArmour")
                    if let armour = Binding($draft.armour) {
                        ArmourFields(armour: armour)
                    }
                }

                Section("Description") {
                    TextEditor(text: $draft.description)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("itemEditor.description")
                }

                if library.catalog.isEdited(draft.id) {
                    Section {
                        Button("Reset to SRD values", role: .destructive) { confirmingReset = true }
                            .accessibilityIdentifier("itemEditor.reset")
                    }
                }
            }
            .navigationTitle("Edit \(draft.name.isEmpty ? "item" : draft.name)")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("itemEditor.save")
                }
            }
            .confirmationDialog("Reset this item?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset to SRD values", role: .destructive) { reset() }
            } message: {
                Text("Your edits to \(draft.name) will be removed for everyone.")
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.itemLibrary.save(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reset() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.itemLibrary.revert(id: draft.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Bindings for optional values

    private var hasCost: Binding<Bool> {
        Binding(get: { draft.cost != nil }, set: { draft.cost = $0 ? (draft.cost ?? Cost(amount: 1, coin: .gp)) : nil })
    }

    private var costAmount: Binding<String> {
        Binding(
            get: { draft.cost.map { String($0.amount) } ?? "" },
            set: { if let amount = Int($0) { draft.cost?.amount = amount } }
        )
    }

    private var costCoin: Binding<Coin> {
        Binding(get: { draft.cost?.coin ?? .gp }, set: { draft.cost?.coin = $0 })
    }

    private var weight: Binding<String> {
        Binding(
            get: { draft.weight.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                draft.weight = trimmed.isEmpty ? nil : (Double(trimmed.replacingOccurrences(of: ",", with: ".")) ?? draft.weight)
            }
        )
    }

    private var hasWeapon: Binding<Bool> {
        Binding(
            get: { draft.weapon != nil },
            set: { draft.weapon = $0 ? (draft.weapon ?? WeaponStats(damage: "1d6", damageType: .slashing)) : nil }
        )
    }

    private var hasArmour: Binding<Bool> {
        Binding(
            get: { draft.armour != nil },
            set: { draft.armour = $0 ? (draft.armour ?? ArmourStats(kind: .light, baseArmorClass: 11, addsDexterity: true)) : nil }
        )
    }
}

private struct WeaponFields: View {
    @Binding var weapon: WeaponStats

    var body: some View {
        TextField("Damage (e.g. 1d8)", text: $weapon.damage)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("itemEditor.damage")
        Picker("Damage type", selection: $weapon.damageType) {
            ForEach(DamageType.allCases) { Text($0.title).tag($0) }
        }
        TextField("Two-handed damage (versatile)", text: optionalText($weapon.versatileDamage))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("Normal range (ft)", text: optionalNumber($weapon.normalRange))
            .keyboardType(.numberPad)
        TextField("Long range (ft)", text: optionalNumber($weapon.longRange))
            .keyboardType(.numberPad)
        ForEach(WeaponProperty.allCases) { property in
            Toggle(property.title, isOn: Binding(
                get: { weapon.properties.contains(property) },
                set: { isOn in
                    weapon.properties.removeAll { $0 == property }
                    if isOn {
                        weapon.properties.append(property)
                        weapon.properties.sort { a, b in
                            WeaponProperty.allCases.firstIndex(of: a)! < WeaponProperty.allCases.firstIndex(of: b)!
                        }
                    }
                }
            ))
        }
    }
}

private struct ArmourFields: View {
    @Binding var armour: ArmourStats

    var body: some View {
        Picker("Kind", selection: $armour.kind) {
            ForEach(ArmourKind.allCases) { Text($0.title).tag($0) }
        }
        Stepper(armour.kind == .shield ? "AC bonus: +\(armour.baseArmorClass)" : "Base AC: \(armour.baseArmorClass)",
                value: $armour.baseArmorClass, in: 0...30)
            .accessibilityIdentifier("itemEditor.ac")
        Toggle("Adds Dex modifier", isOn: $armour.addsDexterity)
        if armour.addsDexterity {
            TextField("Max Dex bonus (blank for none)", text: optionalNumber($armour.maxDexterityBonus))
                .keyboardType(.numberPad)
        }
        TextField("Strength needed (blank for none)", text: optionalNumber($armour.strengthRequirement))
            .keyboardType(.numberPad)
        Toggle("Stealth disadvantage", isOn: $armour.stealthDisadvantage)
    }
}

/// Edits an optional number as text: blank clears it.
private func optionalNumber(_ value: Binding<Int?>) -> Binding<String> {
    Binding(
        get: { value.wrappedValue.map(String.init) ?? "" },
        set: { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                value.wrappedValue = nil
            } else if let number = Int(trimmed) {
                value.wrappedValue = number
            }
        }
    )
}

/// Edits optional text: blank clears it.
private func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(
        get: { value.wrappedValue ?? "" },
        set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
