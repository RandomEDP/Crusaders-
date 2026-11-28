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
                ThemedSection {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("newCharacter.name")
                    Stepper("Starting level \(draft.level)", value: $draft.level, in: PlayerCharacter.levelRange)
                        .accessibilityIdentifier("newCharacter.level")
                }

                raceSection
                classSection
                abilitySection(preview: preview)
                hitPointSection(preview: preview)
                skillSection(preview: preview)
                summarySection(preview: preview)

                if let errorMessage {
                    ThemedSection {
                        Text(errorMessage).foregroundStyle(Theme.crimson)
                    }
                }

                ThemedSection {
                    Text(RulesCatalog.srdAttribution)
                        .font(.serif(.footnote))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .onChange(of: draft.level) {
                draft.syncHitPointRolls(catalog: rules)
            }
            .navigationTitle("New character")
            .parchmentScreen()
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
        ThemedSection("Race") {
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
                            .font(.serif(.subheadline))
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
                    Text(race.languages).font(.serif(.footnote)).foregroundStyle(Theme.inkSoft)
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
        ThemedSection("Class") {
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
                        .font(.serif(.footnote))
                        .foregroundStyle(Theme.inkSoft)
                    ForEach(characterClass.level(1)?.features ?? [], id: \.name) { feature in
                        RuleTextRow(rule: feature)
                    }
                }
            }
        }
    }

    // MARK: Abilities

    private func abilitySection(preview: CharacterSheet) -> some View {
        ThemedSection {
            Picker("Method", selection: Binding(
                get: { draft.abilityMethod },
                set: { draft.selectAbilityMethod($0, catalog: rules) }
            )) {
                ForEach(AbilityMethod.allCases) { method in
                    Text(shortName(method)).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("newCharacter.abilityMethod")

            methodDetails

            ForEach(Ability.allCases) { ability in
                abilityRow(ability, preview: preview)
            }
        } header: {
            HStack {
                Text("Ability scores")
                Spacer()
                presetMenu
            }
        } footer: {
            Text(methodFooter)
        }
    }

    private func shortName(_ method: AbilityMethod) -> String {
        switch method {
        case .standardArray: return "Array"
        case .pointBuy: return "Points"
        case .rolled: return "Roll"
        case .custom: return "Custom"
        }
    }

    private var methodFooter: String {
        switch draft.abilityMethod {
        case .standardArray: return "15, 14, 13, 12, 10 and 8. Tap the arrows on a score to swap it with another."
        case .pointBuy: return "Spend 27 points. Scores go from 8 to 15, and 14 and 15 cost extra."
        case .rolled: return "Roll 4d6 six times and drop the lowest die each time. Swap the results to place them."
        case .custom: return "Type in scores you rolled at the table, 3 to 18 before racial bonuses."
        }
    }

    @ViewBuilder
    private var methodDetails: some View {
        switch draft.abilityMethod {
        case .pointBuy:
            LabeledContent("Points left", value: "\(draft.pointBuyRemaining ?? 0) of \(PointBuy.budget)")
                .accessibilityIdentifier("newCharacter.pointsLeft")
        case .rolled:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(draft.abilityRolls.enumerated()), id: \.offset) { _, roll in
                    AbilityRollRow(roll: roll)
                }
            }
            Button {
                draft.rollAbilityScores(catalog: rules)
            } label: {
                Label("Roll again", systemImage: "dice")
            }
            .accessibilityIdentifier("newCharacter.reroll")
        case .standardArray, .custom:
            EmptyView()
        }
    }

    /// The little button with three builds for the chosen class.
    private var presetMenu: some View {
        Menu {
            ForEach(characterClass?.presets ?? []) { preset in
                Button {
                    draft.apply(preset, catalog: rules)
                } label: {
                    Text(preset.name)
                    Text(preset.summary)
                }
            }
        } label: {
            Label("Presets", systemImage: "wand.and.stars")
                .labelStyle(.titleAndIcon)
                .font(.serifBold(.caption))
                .textCase(nil)
        }
        .disabled(characterClass == nil)
        .accessibilityIdentifier("newCharacter.presets")
    }

    @ViewBuilder
    private func abilityRow(_ ability: Ability, preview: CharacterSheet) -> some View {
        let label = HStack {
            Text(ability.name)
            Spacer()
            Text("\(draft.baseAbilityScores[ability])")
                .foregroundStyle(Theme.inkSoft)
            let bonus = preview.racialBonuses[ability] ?? 0
            if bonus != 0 {
                Text(AbilityScores.signed(bonus)).foregroundStyle(.tint)
            }
            Text("= \(preview.abilityScores[ability]) (\(AbilityScores.signed(preview.modifier(ability))))")
                .monospacedDigit()
        }
        switch draft.abilityMethod {
        case .pointBuy, .custom:
            Stepper {
                label
            } onIncrement: {
                draft.adjust(ability, by: 1)
            } onDecrement: {
                draft.adjust(ability, by: -1)
            }
            .accessibilityIdentifier("newCharacter.score.\(ability.rawValue)")
        case .standardArray, .rolled:
            HStack {
                label
                Menu {
                    ForEach(Ability.allCases.filter { $0 != ability }) { other in
                        Button("Swap with \(other.name) (\(draft.baseAbilityScores[other]))") {
                            draft.swapScores(ability, other)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .accessibilityLabel("Swap \(ability.name)")
                }
                .accessibilityIdentifier("newCharacter.swap.\(ability.rawValue)")
            }
        }
    }

    // MARK: Hit points

    private func hitPointSection(preview: CharacterSheet) -> some View {
        ThemedSection {
            Picker("Hit points", selection: Binding(
                get: { draft.hitPointMethod },
                set: { draft.selectHitPointMethod($0, catalog: rules) }
            )) {
                ForEach(HitPointMethod.allCases) { method in
                    Text(method == .fixed ? "Fixed average" : "Roll hit dice").tag(method)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("newCharacter.hpMethod")

            LabeledContent("Level 1", value: "\(preview.hitDie) (full hit die)")
            if draft.hitPointMethod == .rolled {
                ForEach(Array(draft.hitPointRolls.enumerated()), id: \.offset) { index, roll in
                    LabeledContent("Level \(index + 2)", value: "rolled \(roll) on d\(preview.hitDie)")
                }
                if draft.level > 1 {
                    Button {
                        draft.rerollHitPoints(catalog: rules)
                    } label: {
                        Label("Roll hit points again", systemImage: "dice")
                    }
                    .accessibilityIdentifier("newCharacter.rerollHP")
                }
            } else if draft.level > 1 {
                LabeledContent("Each level after", value: "\(preview.hitDie / 2 + 1)")
            }
            LabeledContent("Max hit points", value: "\(preview.maxHitPoints)")
                .accessibilityIdentifier("newCharacter.maxHP")
        } header: {
            Text("Hit points")
        } footer: {
            Text("Constitution modifier is added every level.")
        }
    }

    // MARK: Skills

    private func skillSection(preview: CharacterSheet) -> some View {
        let limit = draft.skillChoiceCount(catalog: rules)
        let granted = race?.grantedSkills ?? []
        return ThemedSection {
            ForEach(draft.allowedSkills(catalog: rules)) { skill in
                Toggle(isOn: Binding(
                    get: { draft.skills.contains(skill) },
                    set: { _ in draft.toggleSkill(skill, catalog: rules) }
                )) {
                    HStack {
                        Text(skill.name)
                        Text(skill.ability.abbreviation).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
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
        ThemedSection("Summary") {
            LabeledContent("Hit points", value: "\(preview.maxHitPoints)")
            LabeledContent("Speed", value: "\(preview.speed) ft")
            LabeledContent("Proficiency bonus", value: AbilityScores.signed(preview.proficiencyBonus))
            if let dc = preview.spellSaveDC, preview.canCastSpells {
                LabeledContent("Spell save DC", value: "\(dc)")
            }
        }
    }
}

/// One 4d6 roll: the four dice with the dropped one struck through, and the total.
private struct AbilityRollRow: View {
    let roll: AbilityRoll

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(roll.dice.enumerated()), id: \.offset) { index, die in
                Text("\(die)")
                    .monospacedDigit()
                    .strikethrough(index == roll.droppedIndex)
                    .foregroundStyle(index == roll.droppedIndex ? AnyShapeStyle(Theme.inkSoft.opacity(0.5)) : AnyShapeStyle(Theme.ink))
            }
            Spacer()
            Text("\(roll.total)").font(.serifBold(.headline)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rolled \(roll.dice.map(String.init).joined(separator: ", ")), total \(roll.total)")
    }
}

/// A rule's name with its full text behind a disclosure arrow.
struct RuleTextRow: View {
    let rule: RuleText
    var caption: String?

    var body: some View {
        DisclosureGroup {
            Text(rule.description)
                .font(.serif(.callout))
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                if let caption {
                    Text(caption).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

#Preview {
    CharacterCreationView().environment(AppModel())
}
