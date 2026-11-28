import SwiftUI
import CrusadersKit

/// Character sheet sections for a character imported from D&D Beyond. Shows the numbers exactly as
/// D&D Beyond printed them, with its feats, species traits and items already applied.
struct ImportedSheetSections: View {
    let sheet: ImportedSheet

    var body: some View {
        Group {
            identitySection
            abilitiesSection
            combatSection
            savingThrowsSection
            skillsSection
            attacksSection
        }
        Group {
            if !sheet.resources.isEmpty { resourcesSection }
            spellsSection
            proficienciesSection
            coinsAndEquipmentSection
            featuresSection
            detailsSection
        }
    }

    private var identitySection: some View {
        ThemedSection {
            LabeledContent("Class", value: sheet.classes.map { entry in
                [entry.name, "\(entry.level)", entry.subclass.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " / "))
            optionalRow("Species", [sheet.species, sheet.ancestry.map { "\($0) ancestry" }].compactMap { $0 }.joined(separator: ", "))
            optionalRow("Background", sheet.background)
            optionalRow("Alignment", sheet.alignment)
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

    private var resourcesSection: some View {
        ThemedSection("Limited uses") {
            ForEach(sheet.resources, id: \.name) { resource in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(resource.name, value: "\(resource.uses) / \(resource.recharge)")
                    if let detail = resource.detailText {
                        Text(detail).font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                    }
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
                                Text("\(sheet.slots(atLevel: level)) slots").font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        ForEach(sheet.spells(atLevel: level), id: \.name) { spell in
                            HStack {
                                Text(spell.name)
                                if spell.alwaysPrepared {
                                    Text("always prepared").font(.serifItalic(.caption)).foregroundStyle(Theme.inkSoft)
                                }
                                Spacer()
                                Text(spell.saveOrAttack ?? "").font(.serif(.caption))
                            }
                        }
                    }
                }
            }
        }
    }

    private var spellLevels: [Int] {
        Array(Set(sheet.spells.map(\.level) + sheet.spellSlots.map(\.level))).sorted()
    }

    private var proficienciesSection: some View {
        ThemedSection("Proficiencies") {
            optionalRow("Languages", sheet.languages.joined(separator: ", "))
            optionalRow("Armor", sheet.armorProficiencies.joined(separator: ", "))
            optionalRow("Weapons", sheet.weaponProficiencies.joined(separator: ", "))
            optionalRow("Tools", sheet.toolProficiencies.joined(separator: ", "))
            optionalRow("Feats", sheet.feats.joined(separator: ", "))
            optionalRow("Metamagic", sheet.metamagic.joined(separator: ", "))
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

    @ViewBuilder
    private var detailsSection: some View {
        let details = detailRows
        if !details.isEmpty {
            ThemedSection("Details") {
                ForEach(details, id: \.0) { label, text in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.serifBold(.subheadline))
                        Text(text).font(.serif(.footnote))
                    }
                }
            }
        }
    }

    private var detailRows: [(String, String)] {
        let fixed: [(String, String?)] = [
            ("Personality traits", sheet.personalityTraits), ("Ideals", sheet.ideals), ("Bonds", sheet.bonds),
            ("Flaws", sheet.flaws), ("Backstory", sheet.backstory)
        ]
        var rows: [(String, String)] = []
        for (label, text) in fixed {
            if let text, !text.isEmpty { rows.append((label, text)) }
        }
        for detail in sheet.otherDetails {
            rows.append((detail.label, detail.text))
        }
        return rows
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
