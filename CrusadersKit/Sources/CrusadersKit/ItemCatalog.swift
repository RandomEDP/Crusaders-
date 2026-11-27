import Foundation

/// The SRD 5.1 attribution that must be shown wherever this item data appears.
public enum SRDAttribution {
    public static let text = """
    This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC \
    and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the \
    Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.
    """
}

public enum ItemCatalogError: Error, Equatable {
    case missingResource
}

/// Loads the built-in item list that ships with the app.
public enum SRDItems {
    private struct File: Decodable {
        let items: [EquipmentItem]
    }

    public static func load() throws -> [EquipmentItem] {
        guard let url = Bundle.module.url(forResource: "srd-items", withExtension: "json") else {
            throw ItemCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> [EquipmentItem] {
        try JSONDecoder().decode(File.self, from: data).items
    }
}

/// A sub-heading of items inside one category, e.g. "Martial Melee" under Weapons.
public struct ItemGroup: Identifiable, Hashable, Sendable {
    public var id: String { "\(category.rawValue)/\(name)" }
    public let category: ItemCategory
    public let name: String
    public let items: [EquipmentItem]
}

/// One drop-down header in Library > Items, with its sub-headings.
public struct ItemSection: Identifiable, Hashable, Sendable {
    public var id: ItemCategory { category }
    public let category: ItemCategory
    public let groups: [ItemGroup]

    public var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
}

/// Built-in items with the creator's edits laid over the top.
public struct ItemCatalog: Sendable, Equatable {
    public private(set) var baseItems: [EquipmentItem]
    /// Creator edits, keyed by item id.
    public private(set) var overrides: [String: EquipmentItem]

    public init(baseItems: [EquipmentItem], overrides: [EquipmentItem] = []) {
        self.baseItems = baseItems
        self.overrides = [:]
        for item in overrides { self.overrides[item.id] = item }
    }

    /// Every item, with edits applied, in the built-in order.
    public var items: [EquipmentItem] {
        baseItems.map { overrides[$0.id] ?? $0 }
    }

    public func item(id: String) -> EquipmentItem? {
        overrides[id] ?? baseItems.first { $0.id == id }
    }

    public func original(id: String) -> EquipmentItem? {
        baseItems.first { $0.id == id }
    }

    public func isEdited(_ id: String) -> Bool {
        guard let edited = overrides[id] else { return false }
        return edited != original(id: id)
    }

    public mutating func applyEdit(_ item: EquipmentItem) {
        overrides[item.id] = item
    }

    public mutating func revert(id: String) {
        overrides[id] = nil
    }

    public mutating func replaceOverrides(_ items: [EquipmentItem]) {
        overrides = [:]
        for item in items { overrides[item.id] = item }
    }

    /// Items grouped under their category headers, then sub-headings, filtered by a search query.
    /// Categories with no matching items are left out. Sub-headings keep their built-in order.
    public func sections(matching query: String = "") -> [ItemSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = items.filter { item in
            trimmed.isEmpty
                || item.name.localizedCaseInsensitiveContains(trimmed)
                || item.group.localizedCaseInsensitiveContains(trimmed)
                || item.description.localizedCaseInsensitiveContains(trimmed)
        }
        return ItemCategory.allCases.compactMap { category in
            let inCategory = matching.filter { $0.category == category }
            guard !inCategory.isEmpty else { return nil }
            var order: [String] = []
            var byGroup: [String: [EquipmentItem]] = [:]
            for item in inCategory {
                if byGroup[item.group] == nil { order.append(item.group) }
                byGroup[item.group, default: []].append(item)
            }
            let groups = order.map { ItemGroup(category: category, name: $0, items: byGroup[$0] ?? []) }
            return ItemSection(category: category, groups: groups)
        }
    }
}
