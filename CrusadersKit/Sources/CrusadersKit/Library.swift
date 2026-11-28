import Foundation

/// A piece of creator-uploaded content, such as a creature or a weapon.
public struct LibraryItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var summary: String
    public var creator: String

    public init(id: String, name: String, summary: String, creator: String) {
        self.id = id
        self.name = name
        self.summary = summary
        self.creator = creator
    }
}

/// A group of library content, such as Creatures or Weapons.
public struct LibraryCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var systemImage: String
    public var items: [LibraryItem]

    public init(id: String, name: String, systemImage: String, items: [LibraryItem]) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.items = items
    }

    /// Items whose name or summary contains the query (case-insensitive). An empty query returns everything.
    public func items(matching query: String) -> [LibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Where library content comes from. The placeholder catalog is used until creator uploads exist.
/// Weapons, armour, potions and other equipment live in Library > Items (see `ItemCatalog`),
/// and monsters in Library > Creatures (see `CreatureCatalog`).
public protocol LibraryCatalog: Sendable {
    func categories() -> [LibraryCategory]
}

public struct PlaceholderLibraryCatalog: LibraryCatalog {
    public init() {}

    public func categories() -> [LibraryCategory] {
        Self.data
    }

    static let data: [LibraryCategory] = [
        LibraryCategory(id: "spells", name: "Spells", systemImage: "sparkles", items: [
            LibraryItem(id: "fire-bolt", name: "Fire Bolt", summary: "Cantrip, ranged fire attack.", creator: "Crusaders"),
            LibraryItem(id: "cure-wounds", name: "Cure Wounds", summary: "1st level, heal a creature you touch.", creator: "Crusaders")
        ]),
        LibraryCategory(id: "items", name: "Magic Items", systemImage: "wand.and.stars", items: [
            LibraryItem(id: "bag-of-holding", name: "Bag of Holding", summary: "Bigger on the inside.", creator: "Crusaders")
        ])
    ]
}
