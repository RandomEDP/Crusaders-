import SwiftUI
import CrusadersKit

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.libraryCategories) { category in
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
