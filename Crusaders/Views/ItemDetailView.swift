import SwiftUI
import CrusadersKit

struct ItemDetailView: View {
    @Environment(AppModel.self) private var model
    let itemID: String
    @State private var isEditing = false

    var body: some View {
        let library = model.itemLibrary
        Group {
            if let item = library.catalog.item(id: itemID) {
                List {
                    Section {
                        LabeledContent("Category", value: item.category.title)
                        LabeledContent("Type", value: item.group)
                        if let cost = item.cost { LabeledContent("Cost", value: cost.text) }
                        if let weight = item.weightText { LabeledContent("Weight", value: weight) }
                        if let rarity = item.rarity { LabeledContent("Rarity", value: rarity.title) }
                        if item.requiresAttunement { LabeledContent("Attunement", value: "Required") }
                    }

                    if let weapon = item.weapon {
                        Section("Weapon") {
                            LabeledContent("Damage", value: weapon.damageText)
                                .accessibilityIdentifier("item.detail.damage")
                            if let versatile = weapon.versatileDamage {
                                LabeledContent("Two-handed", value: versatile)
                            }
                            LabeledContent("Properties", value: weapon.propertiesText)
                        }
                    }

                    if let armour = item.armour {
                        Section("Armour") {
                            LabeledContent("Kind", value: armour.kind.title)
                            LabeledContent(armour.kind == .shield ? "AC bonus" : "Armour Class", value: armour.armorClassText)
                                .accessibilityIdentifier("item.detail.ac")
                            if let strength = armour.strengthRequirement {
                                LabeledContent("Strength", value: "\(strength)")
                            }
                            LabeledContent("Stealth", value: armour.stealthDisadvantage ? "Disadvantage" : "No penalty")
                        }
                    }

                    if !item.description.isEmpty {
                        Section("Description") {
                            Text(item.description)
                        }
                    }

                    if library.catalog.isEdited(item.id) {
                        Section {
                            Label("Edited by the creator", systemImage: "pencil.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("item.detail.edited")
                        }
                    }
                }
                .navigationTitle(item.name)
                .toolbar {
                    if library.isCreator {
                        Button("Edit") { isEditing = true }
                            .accessibilityIdentifier("item.edit")
                    }
                }
                .sheet(isPresented: $isEditing) {
                    ItemEditorView(item: item)
                }
            } else {
                ContentUnavailableView("Item not found", systemImage: "questionmark.square.dashed")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
