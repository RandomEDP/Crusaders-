import SwiftUI
import CrusadersKit

/// Shows what was read from a D&D Beyond PDF before it becomes a character. Anything missing or uncertain
/// is flagged in crimson, and the main values can be fixed here before saving.
struct ImportReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SheetImport
    @State private var errorMessage: String?

    init(result: SheetImport) {
        _draft = State(initialValue: result)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !draft.issues.isEmpty {
                    ThemedSection {
                        ForEach(draft.issues) { issue in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.field).font(.serifBold(.subheadline))
                                    Text(issue.message).font(.serif(.footnote))
                                }
                            } icon: {
                                Image(systemName: issue.kind == .missing ? "exclamationmark.triangle" : "questionmark.circle")
                            }
                            .foregroundStyle(Theme.crimson)
                            .accessibilityIdentifier("import.issue")
                        }
                    } header: {
                        Text("Check these")
                    } footer: {
                        Text("Everything else was read. Fix what you can below, or change it later on the sheet.")
                    }
                }

                ThemedSection("Character") {
                    textRow("Name", field: "Name", text: $draft.name, id: "import.name")
                    textRow("Species", field: "Species", text: optionalText(\.species, field: "Species"))
                    LabeledContent("Class", value: classText)
                        .foregroundStyle(isFlagged("Class") ? Theme.crimson : Theme.ink)
                    textRow("Background", field: "Background", text: optionalText(\.background, field: "Background"))
                    textRow("Alignment", field: "Alignment", text: optionalText(\.alignment, field: "Alignment"))
                    numberRow("Experience", field: "Experience", value: \.experiencePoints)
                    if let player = draft.sheet.playerName {
                        LabeledContent("Player", value: player)
                    }
                }

                ThemedSection {
                    ForEach(Ability.allCases) { ability in
                        abilityRow(ability)
                    }
                } header: {
                    Text("Abilities")
                } footer: {
                    Text("As printed by D&D Beyond, with species and feat bonuses already added.")
                }

                ThemedSection("Combat") {
                    numberRow("Armor Class", field: "Armor Class", value: \.armorClass, id: "import.armorClass")
                    numberRow("Max HP", field: "Max HP", value: \.maxHitPoints, id: "import.maxHP")
                    numberRow("Initiative", field: "Initiative", value: \.initiative, signed: true)
                    numberRow("Proficiency bonus", field: "Proficiency bonus", value: \.proficiencyBonus, signed: true)
                    textRow("Hit dice", field: "Hit dice", text: optionalText(\.hitDice, field: "Hit dice"))
                    LabeledContent("Speed", value: speedText)
                        .foregroundStyle(isFlagged("Speed") ? Theme.crimson : Theme.ink)
                }

                ThemedSection("Coins") {
                    ForEach(Coin.allCases.reversed()) { coin in
                        Stepper(value: coinBinding(coin), in: 0...1_000_000) {
                            LabeledContent(coin.title, value: "\(draft.sheet.coins(coin)) \(coin.rawValue)")
                        }
                    }
                }

                ThemedSection {
                    summaryRow("Skills", "\(draft.sheet.skills.count) (\(proficientSkills))")
                    summaryRow("Attacks", draft.sheet.attacks.map(\.name).joined(separator: ", "))
                    summaryRow("Spells", spellText)
                    summaryRow("Resources", draft.sheet.resources.map { "\($0.name) \($0.uses)/\($0.recharge)" }.joined(separator: ", "))
                    summaryRow("Feats", draft.sheet.feats.joined(separator: ", "))
                    summaryRow("Features", "\(draft.sheet.features.count)")
                    summaryRow("Equipment", "\(draft.sheet.equipment.count) kinds of item")
                    summaryRow("Languages", draft.sheet.languages.joined(separator: ", "))
                } header: {
                    Text("Also read")
                } footer: {
                    Text("Read on this phone. Nothing was uploaded.")
                }
            }
            .navigationTitle("Import character")
            .navigationBarTitleDisplayMode(.inline)
            .parchmentScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.pendingImport = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("import.save")
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try model.saveImport(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Rows

    private func isFlagged(_ field: String) -> Bool {
        !draft.issues(for: field).isEmpty
    }

    private func clearIssues(_ field: String) {
        draft.issues.removeAll { $0.field == field }
    }

    private func flagIcon(_ field: String) -> some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(Theme.crimson)
            .opacity(isFlagged(field) ? 1 : 0)
            .accessibilityHidden(!isFlagged(field))
            .accessibilityLabel("Needs checking")
    }

    private func textRow(_ title: String, field: String, text: Binding<String>, id: String? = nil) -> some View {
        HStack {
            Text(title)
            flagIcon(field)
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id ?? "import.\(field)")
        }
        .foregroundStyle(isFlagged(field) ? Theme.crimson : Theme.ink)
    }

    private func numberRow(_ title: String, field: String, value: WritableKeyPath<ImportedSheet, Int?>,
                           signed: Bool = false, id: String? = nil) -> some View {
        let binding = Binding<String>(
            get: {
                guard let number = draft.sheet[keyPath: value] else { return "" }
                return signed ? AbilityScores.signed(number) : "\(number)"
            },
            set: { newValue in
                let cleaned = newValue.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "+", with: "")
                    .trimmingCharacters(in: .whitespaces)
                draft.sheet[keyPath: value] = Int(cleaned)
                clearIssues(field)
            }
        )
        return HStack {
            Text(title)
            flagIcon(field)
            TextField("--", text: binding)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id ?? "import.\(field)")
        }
        .foregroundStyle(isFlagged(field) ? Theme.crimson : Theme.ink)
    }

    private func optionalText(_ keyPath: WritableKeyPath<ImportedSheet, String?>, field: String) -> Binding<String> {
        Binding(
            get: { draft.sheet[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                draft.sheet[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
                clearIssues(field)
            }
        )
    }

    private func abilityRow(_ ability: Ability) -> some View {
        let score = Binding<Int>(
            get: { draft.sheet.ability(ability)?.score ?? 10 },
            set: { newValue in
                let entry = ImportedSheet.AbilityEntry(ability: ability, score: newValue, modifier: AbilityScores.modifier(for: newValue))
                if let index = draft.sheet.abilities.firstIndex(where: { $0.ability == ability }) {
                    draft.sheet.abilities[index] = entry
                } else {
                    draft.sheet.abilities.append(entry)
                }
                clearIssues(ability.name)
            }
        )
        return Stepper(value: score, in: 1...30) {
            HStack {
                Text(ability.name)
                flagIcon(ability.name)
                Spacer()
                Text("\(score.wrappedValue) (\(AbilityScores.signed(AbilityScores.modifier(for: score.wrappedValue))))")
                    .font(.serifBold(.body))
            }
        }
        .foregroundStyle(isFlagged(ability.name) ? Theme.crimson : Theme.ink)
        .accessibilityIdentifier("import.ability.\(ability.rawValue)")
    }

    private func coinBinding(_ coin: Coin) -> Binding<Int> {
        Binding(
            get: { draft.sheet.coins(coin) },
            set: { newValue in
                if let index = draft.sheet.coins.firstIndex(where: { $0.coin == coin }) {
                    draft.sheet.coins[index].count = newValue
                } else {
                    draft.sheet.coins.append(.init(coin: coin, count: newValue))
                }
                clearIssues("Coins")
            }
        )
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value.isEmpty ? "None" : value)
                .font(.serif(.footnote))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(value.isEmpty ? Theme.crimson : Theme.inkSoft)
        }
    }

    // MARK: Text

    private var classText: String {
        let classes = draft.sheet.classes.map { entry in
            [entry.name, "\(entry.level)", entry.subclass.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        }
        return classes.isEmpty ? "Unknown" : classes.joined(separator: " / ")
    }

    private var speedText: String {
        let speeds = draft.sheet.speeds.map { "\($0.feet) ft \($0.mode.lowercased())" }
        return speeds.isEmpty ? "Unknown" : speeds.joined(separator: ", ")
    }

    private var proficientSkills: String {
        let names = draft.sheet.skills.filter { $0.proficiency != .none }.map(\.skill.name)
        return names.isEmpty ? "none proficient" : names.joined(separator: ", ")
    }

    private var spellText: String {
        let spells = draft.sheet.spells
        guard !spells.isEmpty else { return "" }
        let cantrips = spells.filter { $0.level == 0 }.count
        return "\(cantrips) cantrips, \(spells.count - cantrips) leveled"
    }
}
