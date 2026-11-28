import SwiftUI
import CrusadersKit

/// A creature's full stat block.
struct CreatureDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let creatureID: String
    @State private var isEditing = false

    var body: some View {
        let library = model.creatureLibrary
        Group {
            if let creature = library.catalog.creature(id: creatureID) {
                List {
                    ThemedSection {
                        Text(creature.typeLine)
                            .font(.serifItalic(.body))
                            .accessibilityIdentifier("creature.detail.type")
                        LabeledContent("Armour Class", value: creature.armorClassText)
                            .accessibilityIdentifier("creature.detail.ac")
                        LabeledContent("Hit Points", value: creature.hitPointsText)
                            .accessibilityIdentifier("creature.detail.hp")
                        LabeledContent("Speed", value: creature.speed)
                    }

                    ThemedSection("Abilities") {
                        AbilityGrid(creature: creature)
                    }

                    ThemedSection {
                        optionalRow("Saving Throws", creature.savingThrows)
                        optionalRow("Skills", creature.skills)
                        optionalRow("Damage Vulnerabilities", creature.damageVulnerabilities)
                        optionalRow("Damage Resistances", creature.damageResistances)
                        optionalRow("Damage Immunities", creature.damageImmunities)
                        optionalRow("Condition Immunities", creature.conditionImmunities)
                        LabeledContent("Senses", value: creature.senses)
                        LabeledContent("Languages", value: creature.languages)
                        LabeledContent("Challenge", value: "\(creature.challengeRatingText) (\(creature.experience.formatted()) XP)")
                            .accessibilityIdentifier("creature.detail.cr")
                        LabeledContent("Proficiency Bonus", value: AbilityScores.signed(creature.proficiencyBonus))
                    }

                    FeatureSection(title: "Traits", features: creature.traits)
                    FeatureSection(title: "Actions", features: creature.actions)
                    FeatureSection(title: "Reactions", features: creature.reactions)
                    FeatureSection(title: "Legendary Actions", features: creature.legendaryActions)

                    if let description = creature.description {
                        ThemedSection("Description") {
                            Text(description)
                        }
                    }

                    if library.catalog.isCustom(creature.id) {
                        ThemedSection {
                            Label("Added by the creator", systemImage: "star.circle")
                                .foregroundStyle(Theme.inkSoft)
                                .accessibilityIdentifier("creature.detail.custom")
                        }
                    } else if library.catalog.isEdited(creature.id) {
                        ThemedSection {
                            Label("Edited by the creator", systemImage: "pencil.circle")
                                .foregroundStyle(Theme.inkSoft)
                                .accessibilityIdentifier("creature.detail.edited")
                        }
                    }
                }
                .navigationTitle(creature.name)
                .parchmentScreen()
                .toolbar {
                    if library.isCreator {
                        Button("Edit") { isEditing = true }
                            .accessibilityIdentifier("creature.edit")
                    }
                }
                .sheet(isPresented: $isEditing) {
                    CreatureEditorView(creature: creature, isNew: false, onDelete: { dismiss() })
                }
            } else {
                ContentUnavailableView("Creature not found", systemImage: "questionmark.square.dashed")
                    .parchmentScreen()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func optionalRow(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value)
        }
    }
}

/// STR, DEX, CON, INT, WIS, CHA with score and modifier, three to a row so big text still fits.
private struct AbilityGrid: View {
    let creature: Creature

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(Ability.allCases) { ability in
                VStack(spacing: 2) {
                    Text(ability.abbreviation).font(.serifBold(.subheadline))
                    Text(creature.abilityText(ability)).font(.serif(.body))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ability.name) \(creature.abilityText(ability))")
                .accessibilityIdentifier("creature.detail.\(ability.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FeatureSection: View {
    let title: String
    let features: [CreatureFeature]

    var body: some View {
        if !features.isEmpty {
            ThemedSection(title) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.name).font(.serifBold(.headline))
                        if !feature.description.isEmpty {
                            Text(feature.description).font(.serif(.body))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
