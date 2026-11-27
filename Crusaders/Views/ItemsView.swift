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
                Section {
                    Label(error, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
            }

            ForEach(sections) { section in
                Section {
                    if isExpanded(section.category) {
                        ForEach(section.groups) { group in
                            if section.groups.count > 1 {
                                Text(group.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
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

            Section {
                Text(SRDAttribution.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "Search items")
        .navigationTitle("Items")
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
                    .font(.headline)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
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
                Text(item.name).font(.headline)
                if isEdited {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Edited")
                }
            }
            if !item.summary.isEmpty {
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { ItemsView() }.environment(AppModel())
}
