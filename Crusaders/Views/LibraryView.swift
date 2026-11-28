import SwiftUI
import CrusadersKit

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ThemedSection {
                NavigationLink {
                    ItemsView()
                } label: {
                    Label {
                        HStack {
                            Text("Items")
                            Spacer()
                            Text("\(model.itemLibrary.catalog.baseItems.count)").foregroundStyle(Theme.inkSoft)
                        }
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                }
                .accessibilityIdentifier("library.items")
            } footer: {
                Text("Weapons, armour, ammunition, potions, gear and tools.")
            }

            ThemedSection {
                NavigationLink {
                    CreaturesView()
                } label: {
                    Label {
                        HStack {
                            Text("Creatures")
                            Spacer()
                            Text("\(model.creatureLibrary.catalog.count)").foregroundStyle(Theme.inkSoft)
                        }
                    } icon: {
                        Image(systemName: "pawprint")
                    }
                }
                .accessibilityIdentifier("library.creatures")
            } footer: {
                Text("Monsters, beasts and people to fight or befriend, with full stat blocks.")
            }

            ThemedSection {
                ForEach(model.libraryCategories) { category in
                    NavigationLink(value: category) {
                        Label {
                            HStack {
                                Text(category.name)
                                Spacer()
                                Text("\(category.items.count)").foregroundStyle(Theme.inkSoft)
                            }
                        } icon: {
                            Image(systemName: category.systemImage)
                        }
                    }
                    .accessibilityIdentifier("library.category.\(category.id)")
                }
            }

            ThemedSection {
                NavigationLink {
                    CreatorAccessView()
                } label: {
                    Label("Creator access", systemImage: "person.badge.key")
                }
                .accessibilityIdentifier("library.creator")
            }
        }
        .navigationTitle("Library")
        .parchmentScreen()
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
                Text(item.name).font(.serifBold(.headline))
                Text(item.summary).font(.serif(.subheadline)).foregroundStyle(Theme.inkSoft)
                Text("by \(item.creator)").font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
            }
            .parchmentRow()
        }
        .searchable(text: $query)
        .navigationTitle(category.name)
        .parchmentScreen()
    }
}

#Preview {
    NavigationStack { LibraryView() }.environment(AppModel())
}
