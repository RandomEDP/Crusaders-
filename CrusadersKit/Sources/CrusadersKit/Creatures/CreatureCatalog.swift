import Foundation

/// Loads the built-in SRD 5.1 creatures that ship with the app.
public enum SRDCreatures {
    private struct File: Decodable {
        let creatures: [Creature]
    }

    public static func load() throws -> [Creature] {
        guard let url = Bundle.module.url(forResource: "srd-creatures", withExtension: "json") else {
            throw ItemCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> [Creature] {
        try JSONDecoder().decode(File.self, from: data).creatures
    }
}

/// One drop-down header in Library > Creatures, e.g. Dragons.
public struct CreatureSection: Identifiable, Hashable, Sendable {
    public var id: CreatureType { type }
    public let type: CreatureType
    public let creatures: [Creature]
}

/// Built-in creatures, with the creator's edits laid over them and the creator's own creatures added.
public struct CreatureCatalog: Sendable, Equatable {
    public private(set) var baseCreatures: [Creature]
    /// Creator records keyed by id: edits of SRD creatures, and new creatures.
    public private(set) var entries: [String: Creature]

    public init(baseCreatures: [Creature], entries: [Creature] = []) {
        self.baseCreatures = baseCreatures
        self.entries = [:]
        replaceEntries(entries)
    }

    /// Every creature, edits applied, sorted by name.
    public var creatures: [Creature] {
        let base = baseCreatures.map { entries[$0.id] ?? $0 }
        let custom = entries.values.filter { original(id: $0.id) == nil }
        return (base + custom).sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    public var count: Int { creatures.count }

    /// The creator's own creatures (not from the SRD).
    public var customCreatures: [Creature] {
        creatures.filter { original(id: $0.id) == nil }
    }

    public func creature(id: String) -> Creature? {
        entries[id] ?? original(id: id)
    }

    public func original(id: String) -> Creature? {
        baseCreatures.first { $0.id == id }
    }

    /// Whether this SRD creature has been changed by the creator.
    public func isEdited(_ id: String) -> Bool {
        guard let entry = entries[id], let base = original(id: id) else { return false }
        return entry != base
    }

    /// Whether the creator added this creature.
    public func isCustom(_ id: String) -> Bool {
        entries[id] != nil && original(id: id) == nil
    }

    public mutating func apply(_ creature: Creature) {
        entries[creature.id] = creature
    }

    /// Removes the creator's record: an SRD creature goes back to its built-in values, a new one disappears.
    public mutating func remove(id: String) {
        entries[id] = nil
    }

    public mutating func replaceEntries(_ creatures: [Creature]) {
        entries = [:]
        for creature in creatures { entries[creature.id] = creature }
    }

    /// Creatures under their type headers, filtered by a search query on name, type, subtype or CR ("cr 5").
    public func sections(matching query: String = "") -> [CreatureSection] {
        let matching = creatures.filter { Self.matches($0, query: query) }
        return CreatureType.allCases.compactMap { type in
            let ofType = matching.filter { $0.type == type }
            return ofType.isEmpty ? nil : CreatureSection(type: type, creatures: ofType)
        }
    }

    static func matches(_ creature: Creature, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("cr ") {
            return creature.challengeRatingText == lower.dropFirst(3).trimmingCharacters(in: .whitespaces)
        }
        return creature.name.localizedCaseInsensitiveContains(trimmed)
            || creature.type.rawValue.localizedCaseInsensitiveContains(trimmed)
            || (creature.subtype?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }
}
