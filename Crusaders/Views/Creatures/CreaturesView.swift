import SwiftUI
import CrusadersKit

/// Library > Creatures: every SRD creature plus the creator's own, under collapsible type headers.
struct CreaturesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var expanded: Set<CreatureType> = []
    @State private var isAdding = false

    var body: some View {
        let library = model.creatureLibrary
        let sections = library.catalog.sections(matching: query)
        List {
            if let error = library.syncError {
                ThemedSection {
                    Label(error, systemImage: "exclamationmark.icloud")
                        .font(.serif(.footnote))
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }

            ForEach(sections) { section in
                ThemedSection {
                    if isExpanded(section.type) {
                        ForEach(section.creatures) { creature in
                            NavigationLink {
                                CreatureDetailView(creatureID: creature.id)
                            } label: {
                                CreatureRow(
                                    creature: creature,
                                    isEdited: library.catalog.isEdited(creature.id),
                                    isCustom: library.catalog.isCustom(creature.id)
                                )
                            }
                            .accessibilityIdentifier("creature.\(creature.id)")
                        }
                    }
                } header: {
                    CreatureTypeHeader(
                        type: section.type,
                        count: section.creatures.count,
                        isExpanded: isExpanded(section.type)
                    ) {
                        toggle(section.type)
                    }
                }
            }

            ThemedSection {
                Text(SRDAttribution.text)
                    .font(.serif(.caption2))
                    .foregroundStyle(Theme.inkSoft)
            } footer: {
                Text("Search by name, type (\"dragon\"), subtype (\"goblinoid\") or challenge rating (\"CR 1/4\").")
            }
        }
        .searchable(text: $query, prompt: "Search creatures")
        .navigationTitle("Creatures")
        .parchmentScreen()
        .toolbar {
            if library.isCreator {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("New creature", systemImage: "plus")
                    }
                    .accessibilityIdentifier("creatures.add")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            CreatureEditorView(creature: .newCustom(), isNew: true)
        }
        .overlay(alignment: .top) {
            if library.isLoading && library.catalog.entries.isEmpty {
                ProgressView().padding(.top, 8)
            }
        }
        .task { await library.refresh() }
        .refreshable { await library.refresh() }
    }

    /// Searching opens every header so matches are visible.
    private func isExpanded(_ type: CreatureType) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || expanded.contains(type)
    }

    private func toggle(_ type: CreatureType) {
        withAnimation {
            if expanded.contains(type) {
                expanded.remove(type)
            } else {
                expanded.insert(type)
            }
        }
    }
}

private struct CreatureTypeHeader: View {
    let type: CreatureType
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(type.pluralTitle, systemImage: type.systemImage)
                    .font(.gothic(.title3))
                Spacer()
                Text("\(count)").foregroundStyle(Theme.inkSoft)
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(Theme.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityIdentifier("creatures.header.\(type.rawValue)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct CreatureRow: View {
    let creature: Creature
    let isEdited: Bool
    let isCustom: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(creature.name).font(.serifBold(.headline))
                if isCustom {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Added by the creator")
                } else if isEdited {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Edited")
                }
            }
            Text(creature.summary).font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
        }
    }
}

#Preview {
    NavigationStack { CreaturesView() }.environment(AppModel())
}
