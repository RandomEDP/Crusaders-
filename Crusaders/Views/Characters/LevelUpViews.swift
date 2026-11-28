import SwiftUI
import CrusadersKit

/// Adds XP to a character. Calls `onLevelUp` when the XP takes them to a new level.
struct AddExperienceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let characterID: PlayerCharacter.ID
    let onLevelUp: (LevelUpSummary) -> Void

    @State private var amountText = ""
    @State private var errorMessage: String?

    private static let quickAmounts = [50, 100, 250, 500, 1_000]

    var body: some View {
        NavigationStack {
            Form {
                if let sheet = model.sheet(for: characterID) {
                    ThemedSection {
                        LabeledContent("Current XP", value: sheet.character.experiencePoints.formatted())
                        if let next = sheet.nextLevelXP {
                            LabeledContent("Level \(sheet.level + 1) at", value: "\(next.formatted()) XP")
                        }
                    }
                }
                ThemedSection {
                    TextField("XP to add", text: $amountText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("xp.amount")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.quickAmounts, id: \.self) { amount in
                                Button("+\(amount.formatted())") {
                                    amountText = String((Int(amountText) ?? 0) + amount)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } footer: {
                    Text("Your level goes up automatically when you pass the next XP milestone.")
                }
                if let errorMessage {
                    ThemedSection {
                        Text(errorMessage).foregroundStyle(Theme.crimson)
                    }
                }
            }
            .navigationTitle("Add experience")
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                        .accessibilityIdentifier("xp.submit")
                }
            }
        }
    }

    private func submit() {
        let digits = amountText.filter(\.isNumber)
        guard let amount = Int(digits) else {
            errorMessage = CharacterError.invalidExperience.localizedDescription
            return
        }
        do {
            if let summary = try model.addExperience(amount, to: characterID) {
                onLevelUp(summary)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shows everything a character unlocked by levelling up.
struct LevelUpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let summary: LevelUpSummary
    let characterID: PlayerCharacter.ID

    var body: some View {
        NavigationStack {
            List {
                ThemedSection {
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text("\(summary.characterName) reached level \(summary.toLevel)!")
                            .font(.gothic(.title2))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("levelUp.title")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                ForEach(summary.levels, id: \.level) { unlocks in
                    levelSection(unlocks)
                }
            }
            .navigationTitle("Level up")
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("levelUp.done")
                }
            }
        }
    }

    private var knownSpellIDs: Set<String> {
        model.character(id: characterID)?.spellIDs ?? []
    }

    private func levelSection(_ unlocks: LevelUnlocks) -> some View {
        ThemedSection("Level \(unlocks.level)") {
            Label("+\(unlocks.hitPointIncrease) max hit points", systemImage: "heart.fill")
            if let bonus = unlocks.proficiencyBonus {
                Label("Proficiency bonus is now +\(bonus)", systemImage: "arrow.up.circle")
            }
            if let subclass = unlocks.subclass {
                RuleTextRow(rule: RuleText(name: "\(subclass.flavor): \(subclass.name)", description: subclass.description), caption: "New subclass")
            }
            if unlocks.abilityScoreImprovement {
                Label("Ability Score Improvement: 2 points to spend on your sheet", systemImage: "figure.strengthtraining.traditional")
            }
            ForEach(Array(unlocks.features.enumerated()), id: \.offset) { _, feature in
                RuleTextRow(rule: feature.rule, caption: "New \(feature.source) feature")
            }
            ForEach(unlocks.counterChanges, id: \.name) { change in
                LabeledContent(change.name, value: changeText(change))
            }
            ForEach(unlocks.spellSlotChanges, id: \.name) { change in
                LabeledContent(change.name, value: changeText(change))
            }
            Group {
                if unlocks.cantripsGained > 0 {
                    Label("Learn \(unlocks.cantripsGained) more cantrip(s)", systemImage: "sparkle")
                }
                if unlocks.spellsKnownGained > 0 {
                    Label("Learn \(unlocks.spellsKnownGained) more spell(s)", systemImage: "sparkles")
                }
                if !unlocks.subclassSpells.isEmpty {
                    Text("Subclass spells").font(.serifBold(.subheadline))
                    ForEach(unlocks.subclassSpells) { spell in
                        SpellRow(spell: spell)
                    }
                }
                if !unlocks.newlyAvailableSpells.isEmpty {
                    if let newLevel = unlocks.newSpellLevel {
                        Text("You can now cast \(Spell.ordinal(newLevel))-level spells. Tap to learn:")
                            .font(.serifBold(.subheadline))
                    } else {
                        Text("New spells you can learn:").font(.serifBold(.subheadline))
                    }
                    ForEach(unlocks.newlyAvailableSpells) { spell in
                        Button {
                            model.toggleSpell(spell.id, for: characterID)
                        } label: {
                            SpellRow(spell: spell, isKnown: knownSpellIDs.contains(spell.id))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
    }

    private func changeText(_ change: LevelUpChange) -> String {
        guard let from = change.from else { return change.to }
        return "\(from) → \(change.to)"
    }
}
