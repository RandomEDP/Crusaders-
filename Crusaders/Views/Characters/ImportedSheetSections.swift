import SwiftUI
import CrusadersKit

/// Character sheet sections for a character imported from D&D Beyond. Shows the numbers exactly as
/// D&D Beyond printed them, with its feats, species traits and items already applied.
struct ImportedSheetSections: View {
    /// What the sheet needs to roll attacks and cast spells. Nil on the import review screen, where nothing is tappable.
    struct Actions {
        let sheet: CharacterSheet
        let campaignCode: String?
        let outcome: Binding<ActionOutcome?>
        let error: Binding<String?>
    }

    @Environment(AppModel.self) private var model
    let sheet: ImportedSheet
    var actions: Actions? = nil

    var body: some View {
        Group {
            identitySection
            abilitiesSection
            combatSection
            savingThrowsSection
            skillsSection
            // On the character sheet, attacks are rolled from "Equipment and attacks".
            if actions == nil { attacksSection }
        }
        // Background, languages, proficiencies, feats, limited uses and lore are the character's own
        // editable fields (CharacterDetailsSections), filled in from the sheet when it was imported.
        Group {
            spellsSection
            if !sheet.metamagic.isEmpty { metamagicSection }
            coinsAndEquipmentSection
            featuresSection
        }
    }

    private var identitySection: some View {
        ThemedSection {
            LabeledContent("Class", value: sheet.classes.map { entry in
                [entry.name, "\(entry.level)", entry.subclass.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " / "))
            optionalRow("Species", [sheet.species, sheet.ancestry.map { "\($0) ancestry" }].compactMap { $0 }.joined(separator: ", "))
            optionalRow("Size", sheet.size)
            optionalRow("Player", sheet.playerName)
        } header: {
            Text("Imported from \(sheet.source)")
        } footer: {
            Text("Imported \(sheet.importedAt.formatted(date: .abbreviated, time: .omitted)). Numbers are as printed on the sheet.")
        }
        .accessibilityIdentifier("sheet.imported")
    }

    private var abilitiesSection: some View {
        ThemedSection("Abilities") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Ability.allCases) { ability in
                    VStack(spacing: 2) {
                        Text(ability.abbreviation).font(.serifBold(.caption)).foregroundStyle(Theme.inkSoft)
                        Text(sheet.ability(ability).map { AbilityScores.signed($0.modifier) } ?? "--").font(.gothic(.title2))
                        Text(sheet.ability(ability).map { "\($0.score)" } ?? "--").font(.serif(.caption))
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

    private var combatSection: some View {
        ThemedSection("Combat") {
            optionalRow("Armor Class", sheet.armorClass.map { "\($0)" })
                .accessibilityIdentifier("sheet.armorClass")
            optionalRow("Max hit points", sheet.maxHitPoints.map { "\($0)" })
            optionalRow("Hit dice", sheet.hitDice)
            optionalRow("Proficiency bonus", sheet.proficiencyBonus.map(AbilityScores.signed))
            optionalRow("Initiative", sheet.initiative.map(AbilityScores.signed))
            optionalRow("Speed", sheet.speeds.map { "\($0.feet) ft \($0.mode.lowercased())" }.joined(separator: ", "))
            optionalRow("Passive Perception", sheet.passivePerception.map { "\($0)" })
            optionalRow("Passive Insight", sheet.passiveInsight.map { "\($0)" })
            optionalRow("Passive Investigation", sheet.passiveInvestigation.map { "\($0)" })
            optionalRow("Senses", sheet.senses.joined(separator: ", "))
            optionalRow("Resistances", sheet.resistances.joined(separator: ", "))
            optionalRow("Immunities", sheet.immunities.joined(separator: ", "))
            optionalRow("Vulnerabilities", sheet.vulnerabilities.joined(separator: ", "))
        }
    }

    private var savingThrowsSection: some View {
        ThemedSection("Saving throws") {
            ForEach(sheet.savingThrows, id: \.ability) { save in
                markedRow(save.ability.name, AbilityScores.signed(save.bonus), mark: save.proficient ? "Proficient" : nil)
            }
        }
    }

    private var skillsSection: some View {
        ThemedSection("Skills") {
            ForEach(sheet.skills, id: \.skill) { skill in
                markedRow("\(skill.skill.name) (\(skill.skill.ability.abbreviation))", AbilityScores.signed(skill.bonus),
                          mark: skill.proficiency == .expertise ? "Expertise" : skill.proficiency == .proficient ? "Proficient" : nil)
            }
        }
    }

    @ViewBuilder
    private var attacksSection: some View {
        if !sheet.attacks.isEmpty {
            ThemedSection("Attacks") {
                ForEach(Array(sheet.attacks.enumerated()), id: \.offset) { _, attack in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(attack.name).font(.serifBold(.headline))
                            Spacer()
                            Text(attack.attackBonus.map(AbilityScores.signed) ?? attack.saveText ?? "")
                        }
                        Text([attack.damage, attack.damageType].compactMap { $0 }.joined(separator: " "))
                            .font(.serif(.subheadline))
                        if let notes = attack.notes {
                            Text(notes).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var spellsSection: some View {
        if !sheet.spells.isEmpty || !sheet.spellcasting.isEmpty {
            ThemedSection("Spellcasting") {
                ForEach(Array(sheet.spellcasting.enumerated()), id: \.offset) { _, casting in
                    let parts = [
                        casting.className,
                        casting.ability.map { $0.abbreviation },
                        casting.saveDC.map { "save DC \($0)" },
                        casting.attackBonus.map { "attack \(AbilityScores.signed($0))" }
                    ].compactMap { $0 }
                    Text(parts.joined(separator: " · "))
                }
                ForEach(spellLevels, id: \.self) { level in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(level == 0 ? "Cantrips" : "Level \(level)").font(.serifBold(.headline))
                            Spacer()
                            if level > 0 {
                                Text(slotText(level)).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                                    .accessibilityIdentifier("imported.slots.\(level)")
                            }
                        }
                        ForEach(sheet.spells(atLevel: level), id: \.name) { spell in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spell.name)
                                    if spell.alwaysPrepared {
                                        Text("always prepared").font(.serifItalic(.caption)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                Spacer()
                                Text(spell.saveOrAttack ?? "").font(.serif(.caption))
                                if let actions {
                                    castButton(spell, actions: actions)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// "3 of 4 slots left" on the character sheet; "4 slots" on the review screen.
    private func slotText(_ level: Int) -> String {
        guard let actions else { return "\(sheet.slots(atLevel: level)) slots" }
        return "\(actions.sheet.spellSlotsLeft(atLevel: level)) of \(sheet.slots(atLevel: level)) slots left"
    }

    private func castButton(_ spell: ImportedSheet.SpellEntry, actions: Actions) -> some View {
        let srd = spell.srdID.flatMap { model.rules.spells(ids: [$0]).first }
        let rollsToHit = srd.map { SpellDice(spell: $0).attack != nil } ?? (spell.saveOrAttack?.contains("+") ?? false)
        return CastSpellButton(name: spell.name, spellLevel: spell.level, rollsToHit: rollsToHit, sheet: actions.sheet,
                               cast: { slot, mode in
                                   try await model.castSpell(imported: spell, slotLevel: slot,
                                                             characterID: actions.sheet.character.id,
                                                             campaignCode: actions.campaignCode, mode: mode)
                               }, outcome: actions.outcome, errorMessage: actions.error)
    }

    private var spellLevels: [Int] {
        Array(Set(sheet.spells.map(\.level) + sheet.spellSlots.map(\.level))).sorted()
    }

    private var metamagicSection: some View {
        ThemedSection("Metamagic") {
            ForEach(sheet.metamagic, id: \.self) { Text($0) }
        }
    }

    private var coinsAndEquipmentSection: some View {
        ThemedSection {
            LabeledContent("Coins", value: sheet.coinPurse.text)
            ForEach(sheet.equipment, id: \.name) { item in
                LabeledContent(item.name, value: item.quantity > 1 ? "× \(item.quantity)" : "")
            }
        } header: {
            Text("Coins and equipment")
        } footer: {
            Text("From the D&D Beyond sheet. Campaign inventories and purses are kept separately.")
        }
    }

    @ViewBuilder
    private var featuresSection: some View {
        if !sheet.features.isEmpty {
            ThemedSection("Features and traits") {
                ForEach(Array(sheet.features.enumerated()), id: \.offset) { _, feature in
                    DisclosureGroup {
                        Text(feature.text.isEmpty ? "No description on the sheet." : feature.text)
                            .font(.serif(.footnote))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.name).font(.serifBold(.subheadline))
                            Text([feature.section, feature.source].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.serif(.caption))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func optionalRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }

    private func markedRow(_ title: String, _ value: String, mark: String?) -> some View {
        HStack {
            Image(systemName: mark == nil ? "circle" : mark == "Expertise" ? "star.circle.fill" : "circle.fill")
                .foregroundStyle(mark == nil ? Theme.inkSoft : Theme.crimson)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(value).font(.serifBold(.body))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(mark ?? "")
    }
}
