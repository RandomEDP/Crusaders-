import SwiftUI
import CrusadersKit

/// The full character sheet: abilities, skills, features, spells and experience.
struct CharacterSheetView: View {
    @Environment(AppModel.self) private var model
    let characterID: PlayerCharacter.ID

    @State private var isAddingExperience = false
    @State private var pendingLevelUp: LevelUpSummary?
    @State private var levelUp: LevelUpSummary?
    @State private var isPickingSpells = false
    @State private var errorMessage: String?

    var body: some View {
        if let sheet = model.sheet(for: characterID) {
            content(sheet)
        } else {
            ContentUnavailableView("Character not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func content(_ sheet: CharacterSheet) -> some View {
        List {
            experienceSection(sheet)
            if sheet.unspentImprovementPoints > 0 {
                improvementSection(sheet)
            }
            abilitiesSection(sheet)
            combatSection(sheet)
            savingThrowsSection(sheet)
            skillsSection(sheet)
            spellsSection(sheet)
            featuresSection(sheet)
            Section {
                Text(RulesCatalog.srdAttribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(sheet.character.name)
        .sheet(isPresented: $isAddingExperience, onDismiss: {
            levelUp = pendingLevelUp
            pendingLevelUp = nil
        }) {
            AddExperienceView(characterID: characterID) { summary in
                pendingLevelUp = summary
            }
        }
        .sheet(item: $levelUp) { summary in
            LevelUpView(summary: summary, characterID: characterID)
        }
        .sheet(isPresented: $isPickingSpells) {
            SpellPickerView(characterID: characterID)
        }
    }

    // MARK: Sections

    private func experienceSection(_ sheet: CharacterSheet) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(sheet.character.summary)
                    .font(.headline)
                    .accessibilityIdentifier("sheet.summary")
                if let next = sheet.nextLevelXP {
                    ProgressView(value: sheet.levelProgress)
                    Text("\(sheet.character.experiencePoints.formatted()) / \(next.formatted()) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(sheet.character.experiencePoints.formatted()) XP (max level)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                isAddingExperience = true
            } label: {
                Label("Add experience", systemImage: "star.circle")
            }
            .accessibilityIdentifier("sheet.addXP")
        }
    }

    private func improvementSection(_ sheet: CharacterSheet) -> some View {
        Section {
            ForEach(Ability.allCases) { ability in
                Button {
                    do {
                        try model.spendImprovementPoint(on: ability, for: characterID)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    HStack {
                        Text("+1 \(ability.name)")
                        Spacer()
                        Text("\(sheet.abilityScores[ability])").foregroundStyle(.secondary)
                    }
                }
                .disabled(sheet.abilityScores[ability] >= AbilityScores.maximum)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        } header: {
            Text("Ability Score Improvement")
        } footer: {
            Text("\(sheet.unspentImprovementPoints) point(s) to spend. Abilities can't go above 20.")
        }
    }

    private func abilitiesSection(_ sheet: CharacterSheet) -> some View {
        Section("Abilities") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Ability.allCases) { ability in
                    VStack(spacing: 2) {
                        Text(ability.abbreviation).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(AbilityScores.signed(sheet.modifier(ability))).font(.title2.bold())
                        Text("\(sheet.abilityScores[ability])").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func combatSection(_ sheet: CharacterSheet) -> some View {
        Section("Combat") {
            LabeledContent("Hit points", value: "\(sheet.maxHitPoints)")
            LabeledContent("Hit dice", value: "\(sheet.level)d\(sheet.hitDie)")
            LabeledContent("Proficiency bonus", value: AbilityScores.signed(sheet.proficiencyBonus))
            LabeledContent("Initiative", value: AbilityScores.signed(sheet.initiative))
            LabeledContent("Speed", value: "\(sheet.speed) ft")
            LabeledContent("Passive Perception", value: "\(sheet.passivePerception)")
            ForEach(sheet.counters, id: \.name) { counter in
                LabeledContent(counter.name, value: counter.value)
            }
            if let proficiencies = sheet.characterClass?.proficiencies, !proficiencies.isEmpty {
                Text(proficiencies.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func savingThrowsSection(_ sheet: CharacterSheet) -> some View {
        Section("Saving throws") {
            ForEach(Ability.allCases) { ability in
                ProficiencyRow(
                    title: ability.name,
                    value: sheet.savingThrow(ability),
                    isProficient: sheet.isProficient(save: ability)
                )
            }
        }
    }

    private func skillsSection(_ sheet: CharacterSheet) -> some View {
        Section("Skills") {
            ForEach(Skill.allCases) { skill in
                ProficiencyRow(
                    title: "\(skill.name) (\(skill.ability.abbreviation))",
                    value: sheet.skillModifier(skill),
                    isProficient: sheet.isProficient(skill)
                )
            }
        }
    }

    @ViewBuilder
    private func spellsSection(_ sheet: CharacterSheet) -> some View {
        if let ability = sheet.spellcastingAbility {
            Section("Spellcasting") {
                LabeledContent("Ability", value: ability.name)
                if let dc = sheet.spellSaveDC, let attack = sheet.spellAttackBonus {
                    LabeledContent("Spell save DC", value: "\(dc)")
                    LabeledContent("Spell attack", value: AbilityScores.signed(attack))
                }
                if let cantrips = sheet.cantripLimit {
                    LabeledContent("Cantrips known", value: "\(sheet.knownCantripCount) of \(cantrips)")
                }
                if let known = sheet.spellsKnownLimit {
                    LabeledContent("Spells known", value: "\(sheet.knownLeveledSpellCount) of \(known)")
                }
                if sheet.highestSpellLevel > 0 {
                    SpellSlotsRow(slots: sheet.spellSlots)
                } else {
                    Text("No spell slots yet.").foregroundStyle(.secondary)
                }
            }
        }

        Section {
            let known = sheet.knownSpells
            if known.isEmpty {
                Text("No spells yet.").foregroundStyle(.secondary)
            }
            ForEach(known) { spell in
                NavigationLink {
                    SpellDetailView(spell: spell, characterID: characterID)
                } label: {
                    SpellRow(spell: spell)
                }
            }
            ForEach(sheet.subclassSpells) { spell in
                NavigationLink {
                    SpellDetailView(spell: spell, characterID: nil)
                } label: {
                    SpellRow(spell: spell, note: sheet.characterClass?.subclass.name)
                }
            }
            Button {
                isPickingSpells = true
            } label: {
                Label("Add or remove spells", systemImage: "sparkles")
            }
            .accessibilityIdentifier("sheet.spells")
        } header: {
            Text("Spells")
        }
    }

    private func featuresSection(_ sheet: CharacterSheet) -> some View {
        Section("Features and traits") {
            ForEach(Array(sheet.features.enumerated()), id: \.offset) { _, feature in
                RuleTextRow(rule: feature.rule, caption: "\(feature.source) level \(feature.level)")
            }
            ForEach(sheet.traits, id: \.name) { trait in
                RuleTextRow(rule: trait, caption: sheet.character.race)
            }
            if sheet.features.isEmpty && sheet.traits.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProficiencyRow: View {
    let title: String
    let value: Int
    let isProficient: Bool

    var body: some View {
        HStack {
            Image(systemName: isProficient ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(isProficient ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text(title)
            Spacer()
            Text(AbilityScores.signed(value)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Slots for each spell level the character has.
struct SpellSlotsRow: View {
    let slots: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spell slots").font(.subheadline)
            HStack(spacing: 8) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, count in
                    if count > 0 {
                        VStack(spacing: 0) {
                            Text("\(count)").font(.headline)
                            Text(Spell.ordinal(index + 1)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 32)
                    }
                }
            }
        }
    }
}
