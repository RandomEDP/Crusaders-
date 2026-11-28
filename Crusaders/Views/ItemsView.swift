import SwiftUI
import CrusadersKit

/// Library > Items: every SRD item under collapsible headers (Weapons, Armour, Potions...).
struct ItemsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var expanded: Set<ItemCategory> = []

    var body: some View {
        let library = model.itemLibrary
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
                    if isExpanded(section.category) {
                        ForEach(section.groups) { group in
                            if section.groups.count > 1 {
                                Text(group.name)
                                    .font(.serifBold(.subheadline))
                                    .foregroundStyle(Theme.inkSoft)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(group.items) { item in
                                NavigationLink {
                                    ItemDetailView(itemID: item.id)
                                } label: {
                                    ItemRow(item: item, isEdited: library.catalog.isEdited(item.id))
                                }
                                .accessibilityIdentifier("item.\(item.id)")
                            }
                        }
                    }
                } header: {
                    CategoryHeader(
                        category: section.category,
                        count: section.itemCount,
                        isExpanded: isExpanded(section.category)
                    ) {
                        toggle(section.category)
                    }
                }
            }

            ThemedSection {
                Text(SRDAttribution.text)
                    .font(.serif(.caption2))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .searchable(text: $query, prompt: "Search items")
        .navigationTitle("Items")
        .parchmentScreen()
        .overlay(alignment: .top) {
            if library.isLoading && library.catalog.overrides.isEmpty {
                ProgressView().padding(.top, 8)
            }
        }
        .task { await library.refresh() }
        .refreshable { await library.refresh() }
    }

    /// Searching opens every header so matches are visible.
    private func isExpanded(_ category: ItemCategory) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || expanded.contains(category)
    }

    private func toggle(_ category: ItemCategory) {
        withAnimation {
            if expanded.contains(category) {
                expanded.remove(category)
            } else {
                expanded.insert(category)
            }
        }
    }
}

private struct CategoryHeader: View {
    let category: ItemCategory
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(category.title, systemImage: category.systemImage)
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
        .accessibilityIdentifier("items.header.\(category.rawValue)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct ItemRow: View {
    let item: EquipmentItem
    let isEdited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.name).font(.serifBold(.headline))
                if isEdited {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Edited")
                }
            }
            if !item.summary.isEmpty {
                Text(item.summary).font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

#Preview {
    NavigationStack { ItemsView() }.environment(AppModel())
}
