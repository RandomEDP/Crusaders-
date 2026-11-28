import SwiftUI
import CrusadersKit

/// One line in a spell list.
struct SpellRow: View {
    let spell: Spell
    var note: String?
    var isKnown: Bool?

    var body: some View {
        HStack(spacing: 12) {
            if let isKnown {
                Image(systemName: isKnown ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isKnown ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.inkSoft))
                    .font(.gothic(.title3))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spell.name)
                    if spell.concentration {
                        Badge(text: "C")
                    }
                    if spell.ritual {
                        Badge(text: "R")
                    }
                }
                Text([spell.subtitle, note].compactMap { $0 }.joined(separator: " · "))
                    .font(.serif(.caption))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        // The whole row is tappable, not just the letters (taps between the two lines used to miss).
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isKnown == true ? "Known" : "")
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.serifBold(.caption2))
            .padding(.horizontal, 4)
            .background(Theme.rule.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Every detail of a spell. With a character, it also offers learn and forget.
struct SpellDetailView: View {
    @Environment(AppModel.self) private var model
    let spell: Spell
    let characterID: PlayerCharacter.ID?

    var body: some View {
        List {
            ThemedSection {
                Text(spell.subtitle).font(.serifBold(.headline))
                LabeledContent("Casting time", value: spell.castingTime)
                LabeledContent("Range", value: spell.range)
                LabeledContent("Components", value: componentText)
                LabeledContent("Duration", value: spell.concentration ? "Concentration, \(spell.duration.lowercased())" : spell.duration)
                if spell.ritual {
                    LabeledContent("Ritual", value: "Yes")
                }
                LabeledContent("Classes", value: classNames)
            }
            ThemedSection("Description") {
                Text(spell.description)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let higherLevel = spell.higherLevel {
                ThemedSection("At higher levels") {
                    Text(higherLevel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(spell.name)
        .parchmentScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let characterID, let character = model.character(id: characterID) {
                    Button(character.spellIDs.contains(spell.id) ? "Forget" : "Learn") {
                        model.toggleSpell(spell.id, for: characterID)
                    }
                    .accessibilityIdentifier("spell.toggle")
                }
            }
        }
    }

    private var componentText: String {
        let letters = spell.components.joined(separator: ", ")
        guard let material = spell.material, !material.isEmpty else { return letters }
        return "\(letters) (\(material))"
    }

    private var classNames: String {
        spell.classes.compactMap { model.rules.characterClass(id: $0)?.name }.joined(separator: ", ")
    }
}

/// Lets a character learn or forget spells, from their class list or every SRD spell.
struct SpellPickerView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case available = "Can cast now"
        case classList = "Class list"
        case all = "All spells"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let characterID: PlayerCharacter.ID

    @State private var scope: Scope?
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if let sheet = model.sheet(for: characterID) {
                    list(sheet)
                } else {
                    ContentUnavailableView("Character not found", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("Spells")
            .parchmentScreen()
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search spells")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("spells.done")
                }
            }
        }
    }

    private func defaultScope(_ sheet: CharacterSheet) -> Scope {
        sheet.canCastSpells ? .available : .all
    }

    private func spells(_ sheet: CharacterSheet, scope: Scope) -> [Spell] {
        let base: [Spell]
        switch scope {
        case .available: base = sheet.learnableSpells
        case .classList: base = sheet.characterClass.map { model.rules.spells(forClass: $0.id) } ?? []
        case .all: base = model.rules.spells
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.school.localizedCaseInsensitiveContains(trimmed) }
    }

    private func list(_ sheet: CharacterSheet) -> some View {
        let current = scope ?? defaultScope(sheet)
        let shown = spells(sheet, scope: current)
        let levels = Array(Set(shown.map(\.level))).sorted()
        return List {
            ThemedSection {
                Picker("Show", selection: Binding(get: { current }, set: { scope = $0 })) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                if let limit = sheet.cantripLimit {
                    LabeledContent("Cantrips known", value: "\(sheet.knownCantripCount) of \(limit)")
                }
                if let limit = sheet.spellsKnownLimit {
                    LabeledContent("Spells known", value: "\(sheet.knownLeveledSpellCount) of \(limit)")
                }
            }
            if shown.isEmpty {
                Text(current == .all ? "No spells match." : "Your class can't cast any spells at this level yet. Try All spells.")
                    .foregroundStyle(Theme.inkSoft)
                    .parchmentRow()
            }
            ForEach(levels, id: \.self) { level in
                ThemedSection(Spell.label(forLevel: level)) {
                    ForEach(shown.filter { $0.level == level }) { spell in
                        PickerRow(spell: spell, characterID: characterID, isKnown: sheet.character.spellIDs.contains(spell.id))
                    }
                }
            }
        }
    }
}

private struct PickerRow: View {
    @Environment(AppModel.self) private var model
    let spell: Spell
    let characterID: PlayerCharacter.ID
    let isKnown: Bool

    var body: some View {
        HStack {
            Button {
                model.toggleSpell(spell.id, for: characterID)
            } label: {
                SpellRow(spell: spell, isKnown: isKnown)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier("spells.row.\(spell.id)")
            Spacer()
            NavigationLink {
                SpellDetailView(spell: spell, characterID: characterID)
            } label: {
                Image(systemName: "info.circle")
            }
            .fixedSize()
            .accessibilityLabel("Details for \(spell.name)")
        }
    }
}
