import SwiftUI
import CrusadersKit

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ItemsView()
                } label: {
                    Label {
                        HStack {
                            Text("Items")
                            Spacer()
                            Text("\(model.itemLibrary.catalog.baseItems.count)").foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                }
                .accessibilityIdentifier("library.items")
            } footer: {
                Text("Weapons, armour, ammunition, potions, gear and tools.")
            }

            Section {
                ForEach(model.libraryCategories) { category in
                    NavigationLink(value: category) {
                        Label {
                            HStack {
                                Text(category.name)
                                Spacer()
                                Text("\(category.items.count)").foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: category.systemImage)
                        }
                    }
                    .accessibilityIdentifier("library.category.\(category.id)")
                }
            }

            Section {
                NavigationLink {
                    CreatorAccessView()
                } label: {
                    Label("Creator access", systemImage: "person.badge.key")
                }
                .accessibilityIdentifier("library.creator")
            }
        }
        .navigationTitle("Library")
        .navigationDestination(for: LibraryCategory.self) { category in
            LibraryCategoryView(category: category)
        }
    }
}

struct LibraryCategoryView: View {
    let category: LibraryCategory
    @State private var query = ""

    var body: some View {
        List(category.items(matching: query)) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.headline)
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
                Text("by \(item.creator)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .searchable(text: $query)
        .navigationTitle(category.name)
    }
}

#Preview {
    NavigationStack { LibraryView() }.environment(AppModel())
}
