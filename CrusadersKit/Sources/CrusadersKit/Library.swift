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
public protocol LibraryCatalog: Sendable {
    func categories() -> [LibraryCategory]
}

public struct PlaceholderLibraryCatalog: LibraryCatalog {
    public init() {}

    public func categories() -> [LibraryCategory] {
        Self.data
    }

    static let data: [LibraryCategory] = [
        LibraryCategory(id: "creatures", name: "Creatures", systemImage: "pawprint", items: [
            LibraryItem(id: "goblin", name: "Goblin", summary: "Small, sneaky and always in a group.", creator: "Crusaders"),
            LibraryItem(id: "owlbear", name: "Owlbear", summary: "Half owl, half bear, all trouble.", creator: "Crusaders"),
            LibraryItem(id: "young-red-dragon", name: "Young Red Dragon", summary: "Greedy, proud and breathes fire.", creator: "Crusaders")
        ]),
        LibraryCategory(id: "weapons", name: "Weapons", systemImage: "hammer", items: [
            LibraryItem(id: "longsword", name: "Longsword", summary: "Versatile martial blade, 1d8 slashing.", creator: "Crusaders"),
            LibraryItem(id: "shortbow", name: "Shortbow", summary: "Light ranged weapon, 1d6 piercing.", creator: "Crusaders"),
            LibraryItem(id: "warhammer", name: "Warhammer", summary: "Heavy hitter, 1d8 bludgeoning.", creator: "Crusaders")
        ]),
        LibraryCategory(id: "armour", name: "Armour", systemImage: "shield", items: [
            LibraryItem(id: "leather", name: "Leather Armour", summary: "Light armour, AC 11 + Dex.", creator: "Crusaders"),
            LibraryItem(id: "chain-mail", name: "Chain Mail", summary: "Heavy armour, AC 16.", creator: "Crusaders"),
            LibraryItem(id: "shield", name: "Shield", summary: "+2 AC while held.", creator: "Crusaders")
        ]),
        LibraryCategory(id: "spells", name: "Spells", systemImage: "sparkles", items: [
            LibraryItem(id: "fire-bolt", name: "Fire Bolt", summary: "Cantrip, ranged fire attack.", creator: "Crusaders"),
            LibraryItem(id: "cure-wounds", name: "Cure Wounds", summary: "1st level, heal a creature you touch.", creator: "Crusaders")
        ]),
        LibraryCategory(id: "items", name: "Magic Items", systemImage: "wand.and.stars", items: [
            LibraryItem(id: "bag-of-holding", name: "Bag of Holding", summary: "Bigger on the inside.", creator: "Crusaders"),
            LibraryItem(id: "potion-of-healing", name: "Potion of Healing", summary: "Regain 2d4 + 2 hit points.", creator: "Crusaders")
        ])
    ]
}
