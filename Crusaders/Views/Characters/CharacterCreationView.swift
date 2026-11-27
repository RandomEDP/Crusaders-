import SwiftUI
import CrusadersKit

/// The form for building a new character from the SRD races and classes.
struct CharacterCreationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CharacterDraft.starter()
    @State private var errorMessage: String?

    private var rules: RulesCatalog { model.rules }
    private var race: Race? { rules.race(id: draft.raceID) }
    private var characterClass: CharacterClass? { rules.characterClass(id: draft.classID) }

    var body: some View {
        let preview = draft.preview(catalog: rules)
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("newCharacter.name")
                    Stepper("Starting level \(draft.level)", value: $draft.level, in: PlayerCharacter.levelRange)
                        .accessibilityIdentifier("newCharacter.level")
                }

                raceSection
                classSection
                abilitySection(preview: preview)
                skillSection(preview: preview)
                summarySection(preview: preview)

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Text(RulesCatalog.srdAttribution)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .accessibilityIdentifier("newCharacter.create")
                }
            }
        }
    }

    private func create() {
        do {
            try model.createCharacter(from: draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Race

    private var raceSection: some View {
        Section("Race") {
            Picker("Race", selection: Binding(
                get: { draft.raceID ?? "" },
                set: { draft.selectRace($0, catalog: rules) }
            )) {
                ForEach(rules.races) { race in
                    Text(race.name).tag(race.id)
                }
            }
            .accessibilityIdentifier("newCharacter.race")

            if let race {
                if !race.subraces.isEmpty {
                    Picker("Subrace", selection: Binding(
                        get: { draft.subraceID ?? "" },
                        set: { draft.selectSubrace($0) }
                    )) {
                        ForEach(race.subraces) { subrace in
                            Text(subrace.name).tag(subrace.id)
                        }
                    }
                }

                if let choice = race.abilityBonusChoice {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose \(choice.count) abilities to get +\(choice.bonus)")
                            .font(.subheadline)
                        ForEach(choice.from) { ability in
                            Toggle(ability.name, isOn: Binding(
                                get: { draft.racialBonusChoices.contains(ability) },
                                set: { _ in draft.toggleRacialBonus(ability, catalog: rules) }
                            ))
                        }
                    }
                }

                DisclosureGroup("About the \(race.name)") {
                    LabeledContent("Speed", value: "\(race.speed) ft")
                    LabeledContent("Size", value: race.size)
                    LabeledContent("Ability bonuses", value: bonusText(race: race))
                    ForEach(traits(for: race), id: \.name) { trait in
                        RuleTextRow(rule: trait)
                    }
                    Text(race.languages).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func traits(for race: Race) -> [RuleText] {
        race.traits + (race.subrace(id: draft.subraceID)?.traits ?? [])
    }

    private func bonusText(race: Race) -> String {
        var bonuses = race.abilityBonuses
        for (ability, bonus) in race.subrace(id: draft.subraceID)?.abilityBonuses ?? [:] {
            bonuses[ability, default: 0] += bonus
        }
        return Ability.allCases
            .compactMap { ability in bonuses[ability].map { "\(ability.abbreviation) \(AbilityScores.signed($0))" } }
            .joined(separator: ", ")
    }

    // MARK: Class

    private var classSection: some View {
        Section("Class") {
            Picker("Class", selection: Binding(
                get: { draft.classID ?? "" },
                set: { draft.selectClass($0, catalog: rules) }
            )) {
                ForEach(rules.classes) { characterClass in
                    Text(characterClass.name).tag(characterClass.id)
                }
            }
            .accessibilityIdentifier("newCharacter.class")

            if let characterClass {
                DisclosureGroup("About the \(characterClass.name)") {
                    LabeledContent("Hit die", value: "d\(characterClass.hitDie)")
                    LabeledContent("Saving throws", value: characterClass.savingThrows.map(\.abbreviation).joined(separator: ", "))
                    if let ability = characterClass.spellcastingAbility {
                        LabeledContent("Spellcasting", value: ability.name)
                    }
                    LabeledContent("\(characterClass.subclass.flavor)", value: "\(characterClass.subclass.name) at level \(characterClass.subclassLevel)")
                    Text(characterClass.proficiencies.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(characterClass.level(1)?.features ?? [], id: \.name) { feature in
                        RuleTextRow(rule: feature)
                    }
                }
            }
        }
    }

    // MARK: Abilities

    private func abilitySection(preview: CharacterSheet) -> some View {
        Section {
            ForEach(Ability.allCases) { ability in
                Stepper(value: $draft.baseAbilityScores[ability], in: AbilityScores.baseRange) {
                    HStack {
                        Text(ability.name)
                        Spacer()
                        Text("\(draft.baseAbilityScores[ability])")
                            .foregroundStyle(.secondary)
                        let bonus = preview.racialBonuses[ability] ?? 0
                        if bonus != 0 {
                            Text(AbilityScores.signed(bonus)).foregroundStyle(.tint)
                        }
                        Text("= \(preview.abilityScores[ability]) (\(AbilityScores.signed(preview.modifier(ability))))")
                            .monospacedDigit()
                    }
                }
            }
            Button("Use standard array for this class") {
                draft.useStandardArray(catalog: rules)
            }
        } header: {
            Text("Ability scores")
        } footer: {
            Text("Base scores 3 to 18, then racial bonuses are added.")
        }
    }

    // MARK: Skills

    private func skillSection(preview: CharacterSheet) -> some View {
        let limit = draft.skillChoiceCount(catalog: rules)
        let granted = race?.grantedSkills ?? []
        return Section {
            ForEach(draft.allowedSkills(catalog: rules)) { skill in
                Toggle(isOn: Binding(
                    get: { draft.skills.contains(skill) },
                    set: { _ in draft.toggleSkill(skill, catalog: rules) }
                )) {
                    HStack {
                        Text(skill.name)
                        Text(skill.ability.abbreviation).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!draft.skills.contains(skill) && draft.skills.count >= limit)
            }
            ForEach(Array(granted).sorted { $0.name < $1.name }) { skill in
                LabeledContent(skill.name, value: "From your race")
            }
        } header: {
            Text("Skills (\(draft.skills.count) of \(limit))")
        }
    }

    // MARK: Summary

    private func summarySection(preview: CharacterSheet) -> some View {
        Section("Summary") {
            LabeledContent("Hit points", value: "\(preview.maxHitPoints)")
            LabeledContent("Speed", value: "\(preview.speed) ft")
            LabeledContent("Proficiency bonus", value: AbilityScores.signed(preview.proficiencyBonus))
            if let dc = preview.spellSaveDC, preview.canCastSpells {
                LabeledContent("Spell save DC", value: "\(dc)")
            }
        }
    }
}

/// A rule's name with its full text behind a disclosure arrow.
struct RuleTextRow: View {
    let rule: RuleText
    var caption: String?

    var body: some View {
        DisclosureGroup {
            Text(rule.description)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    CharacterCreationView().environment(AppModel())
}
