import SwiftUI
import CrusadersKit

/// The full character sheet: abilities, skills, features, spells and experience.
/// Equipped items from a campaign inventory (AC, attacks, speed, saves) are applied automatically.
struct CharacterSheetView: View {
    @Environment(AppModel.self) private var model
    let characterID: PlayerCharacter.ID
    /// The campaign whose inventory to use. Nil: the one picked on the sheet, or the first campaign.
    var campaignCode: String? = nil

    @State private var pickedCampaign: String?

    @State private var isAddingExperience = false
    @State private var pendingLevelUp: LevelUpSummary?
    @State private var levelUp: LevelUpSummary?
    @State private var isPickingSpells = false
    @State private var errorMessage: String?

    var body: some View {
        if let sheet = model.sheet(for: characterID, campaignCode: campaignCode ?? pickedCampaign) {
            content(sheet)
        } else {
            ContentUnavailableView("Character not found", systemImage: "person.crop.circle.badge.questionmark")
                .parchmentScreen()
        }
    }

    private func content(_ sheet: CharacterSheet) -> some View {
        List {
            experienceSection(sheet)
            // Imported characters already chose their improvements and feats on D&D Beyond.
            if sheet.unspentImprovementPoints > 0 && !sheet.character.isImported {
                improvementSection(sheet)
            }
            if let imported = sheet.character.importedSheet {
                // Imported from D&D Beyond: show its printed numbers instead of working them out again.
                ImportedSheetSections(sheet: imported)
                effectsSection(sheet)
                equipmentSection(sheet)
            } else {
                abilitiesSection(sheet)
                combatSection(sheet)
                effectsSection(sheet)
                equipmentSection(sheet)
                savingThrowsSection(sheet)
                skillsSection(sheet)
                spellsSection(sheet)
                featuresSection(sheet)
            }
            ThemedSection {
                Text(RulesCatalog.srdAttribution)
                    .font(.serif(.footnote))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .navigationTitle(sheet.character.name)
        .parchmentScreen()
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
        ThemedSection {
            VStack(alignment: .leading, spacing: 6) {
                Text(sheet.character.summary)
                    .font(.serifBold(.headline))
                    .accessibilityIdentifier("sheet.summary")
                if let next = sheet.nextLevelXP {
                    ProgressView(value: sheet.levelProgress)
                    Text("\(sheet.character.experiencePoints.formatted()) / \(next.formatted()) XP")
                        .font(.serif(.caption))
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Text("\(sheet.character.experiencePoints.formatted()) XP (max level)")
                        .font(.serif(.caption))
                        .foregroundStyle(Theme.inkSoft)
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
        ThemedSection {
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
                        Text("\(sheet.abilityScores[ability])").foregroundStyle(Theme.inkSoft)
                    }
                }
                .disabled(sheet.abilityScores[ability] >= AbilityScores.maximum)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.crimson)
            }
        } header: {
            Text("Ability Score Improvement")
        } footer: {
            Text("\(sheet.unspentImprovementPoints) point(s) to spend. Abilities can't go above 20.")
        }
    }

    private func abilitiesSection(_ sheet: CharacterSheet) -> some View {
        ThemedSection("Abilities") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Ability.allCases) { ability in
                    VStack(spacing: 2) {
                        Text(ability.abbreviation).font(.serifBold(.caption)).foregroundStyle(Theme.inkSoft)
                        Text(AbilityScores.signed(sheet.modifier(ability))).font(.gothic(.title2))
                        Text("\(sheet.abilityScores[ability])").font(.serif(.caption))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .paperCard(RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func combatSection(_ sheet: CharacterSheet) -> some View {
        ThemedSection("Combat") {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Armor Class", value: "\(sheet.armorClass)")
                    .accessibilityIdentifier("sheet.armorClass")
                Text(sheet.armorClassParts.map { "\($0.name) \($0.value)" }.joined(separator: " + "))
                    .font(.serif(.caption))
                    .foregroundStyle(Theme.inkSoft)
            }
            if model.campaigns(playing: characterID).isEmpty {
                LabeledContent("Hit points", value: "\(sheet.maxHitPoints)")
            } else {
                LabeledContent("Hit points", value: sheet.health.text)
                    .accessibilityIdentifier("sheet.hitPoints")
            }
            LabeledContent("Hit dice", value: "\(sheet.level)d\(sheet.hitDie)")
            LabeledContent("Proficiency bonus", value: AbilityScores.signed(sheet.proficiencyBonus))
            LabeledContent("Initiative", value: AbilityScores.signed(sheet.initiative))
            LabeledContent("Speed", value: sheet.armourSpeedPenalty > 0
                           ? "\(sheet.speed) ft (−\(sheet.armourSpeedPenalty) armour)"
                           : "\(sheet.speed) ft")
                .accessibilityIdentifier("sheet.speed")
            ForEach(sheet.extraSpeeds, id: \.self) { speed in
                Text(speed).font(.serif(.subheadline))
            }
            LabeledContent("Passive Perception", value: "\(sheet.passivePerception)")
            ForEach(sheet.counters, id: \.name) { counter in
                LabeledContent(counter.name, value: counter.value)
            }
            if let proficiencies = sheet.characterClass?.proficiencies, !proficiencies.isEmpty {
                Text(proficiencies.joined(separator: ", "))
                    .font(.serif(.footnote))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// Potions and other effects that are active, with the rounds they have left.
    @ViewBuilder
    private func effectsSection(_ sheet: CharacterSheet) -> some View {
        if !sheet.activeEffects.isEmpty {
            ThemedSection("Active effects") {
                ForEach(sheet.activeEffects) { effect in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(effect.name).font(.serifBold(.headline))
                            Spacer()
                            Text(ActiveEffect.timeLeftText(effect.roundsLeft(atRound: sheet.combat.round)))
                                .font(.serif(.caption))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        ForEach(effect.summary, id: \.self) { note in
                            Text(note).font(.serif(.caption))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sheet.effect")
                }
                ForEach(sheet.effectSaveNotes, id: \.self) { note in
                    Text("Saving throws \(note)").font(.serif(.footnote)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    /// Worn and held items, attacks and armour warnings, from the campaign inventory.
    @ViewBuilder
    private func equipmentSection(_ sheet: CharacterSheet) -> some View {
        let playing = model.campaigns(playing: characterID)
        ThemedSection {
            if playing.isEmpty {
                Text("Join a campaign with this character. Items you equip from its inventory change your AC, attacks and speed here.")
                    .foregroundStyle(Theme.inkSoft)
            } else {
                if campaignCode == nil && playing.count > 1 {
                    Picker("Campaign", selection: Binding(
                        get: { pickedCampaign ?? playing.first?.joinCode ?? "" },
                        set: { pickedCampaign = $0 }
                    )) {
                        ForEach(playing) { Text($0.name).tag($0.joinCode) }
                    }
                }
                ForEach(sheet.gear.equipped) { entry in
                    LabeledContent(entry.slot.title, value: entry.gear.name)
                }
                ForEach(sheet.gear.attuned, id: \.id) { gear in
                    LabeledContent("Attuned", value: gear.name)
                }
                if sheet.gear.isEmpty {
                    Text("Nothing equipped. Equip items on the campaign's Inventory tab.")
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(sheet.equipmentWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.serif(.footnote))
                        .foregroundStyle(Theme.crimson)
                }
            }
            ForEach(sheet.attacks) { attack in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(attack.name).font(.serifBold(.headline))
                        Spacer()
                        Text(AbilityScores.signed(attack.attackBonus)).monospacedDigit()
                    }
                    Text(attack.damage).font(.serif(.subheadline))
                    if !attack.notes.isEmpty {
                        Text(attack.notes.joined(separator: " · "))
                            .font(.serif(.caption))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sheet.attack.\(attack.id)")
            }
        } header: {
            Text("Equipment and attacks")
        }
    }

    private func savingThrowsSection(_ sheet: CharacterSheet) -> some View {
        ThemedSection("Saving throws") {
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
        ThemedSection("Skills") {
            ForEach(Skill.allCases) { skill in
                ProficiencyRow(
                    title: "\(skill.name) (\(skill.ability.abbreviation))",
                    value: sheet.skillModifier(skill),
                    isProficient: sheet.isProficient(skill),
                    note: skill == .stealth && sheet.hasStealthDisadvantage ? "Disadvantage (armour)" : nil
                )
            }
        }
    }

    @ViewBuilder
    private func spellsSection(_ sheet: CharacterSheet) -> some View {
        if let ability = sheet.spellcastingAbility {
            ThemedSection("Spellcasting") {
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
                    Text("No spell slots yet.").foregroundStyle(Theme.inkSoft)
                }
            }
        }

        ThemedSection {
            let known = sheet.knownSpells
            if known.isEmpty {
                Text("No spells yet.").foregroundStyle(Theme.inkSoft)
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
        ThemedSection("Features and traits") {
            ForEach(Array(sheet.features.enumerated()), id: \.offset) { _, feature in
                RuleTextRow(rule: feature.rule, caption: "\(feature.source) level \(feature.level)")
            }
            ForEach(sheet.traits, id: \.name) { trait in
                RuleTextRow(rule: trait, caption: sheet.character.race)
            }
            if sheet.features.isEmpty && sheet.traits.isEmpty {
                Text("Nothing yet.").foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

private struct ProficiencyRow: View {
    let title: String
    let value: Int
    let isProficient: Bool
    var note: String? = nil

    var body: some View {
        HStack {
            Image(systemName: isProficient ? "circle.fill" : "circle")
                .font(.serif(.caption2))
                .foregroundStyle(isProficient ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.inkSoft))
            Text(title)
            if let note {
                Text(note).font(.serif(.caption)).foregroundStyle(Theme.crimson)
            }
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
            Text("Spell slots").font(.serif(.subheadline))
            HStack(spacing: 8) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, count in
                    if count > 0 {
                        VStack(spacing: 0) {
                            Text("\(count)").font(.serifBold(.headline))
                            Text(Spell.ordinal(index + 1)).font(.serif(.caption2)).foregroundStyle(Theme.inkSoft)
                        }
                        .frame(minWidth: 32)
                    }
                }
            }
        }
    }
}
