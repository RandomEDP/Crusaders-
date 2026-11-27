import Foundation

/// Raw SRD data bundled with the app. The JSON lives in the generated files under `SRD/`.
enum SRDData {}

/// Races, classes and spells the character builder can use.
public struct RulesCatalog: Sendable {
    /// The credit the SRD's CC BY 4.0 licence requires wherever its content is shown.
    public static let srdAttribution = """
    This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC \
    and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the \
    Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.
    """

    public let races: [Race]
    public let classes: [CharacterClass]
    /// Sorted by level, then name.
    public let spells: [Spell]
    private let spellsByID: [String: Spell]

    public init(races: [Race], classes: [CharacterClass], spells: [Spell]) {
        self.races = races
        self.classes = classes
        self.spells = spells.sorted { ($0.level, $0.name) < ($1.level, $1.name) }
        self.spellsByID = Dictionary(spells.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(racesJSON: String, classesJSON: String, spellsJSON: String) throws {
        let decoder = JSONDecoder()
        try self.init(
            races: decoder.decode([Race].self, from: Data(racesJSON.utf8)),
            classes: decoder.decode([CharacterClass].self, from: Data(classesJSON.utf8)),
            spells: decoder.decode([Spell].self, from: Data(spellsJSON.utf8))
        )
    }

    /// Every race, class and spell in the SRD 5.1.
    public static let srd: RulesCatalog = {
        do {
            return try RulesCatalog(racesJSON: SRDData.racesJSON, classesJSON: SRDData.classesJSON, spellsJSON: SRDData.spellsJSON)
        } catch {
            fatalError("Bundled SRD data failed to load: \(error)")
        }
    }()

    public func race(id: String?) -> Race? {
        guard let id else { return nil }
        return races.first { $0.id == id }
    }

    public func characterClass(id: String?) -> CharacterClass? {
        guard let id else { return nil }
        return classes.first { $0.id == id }
    }

    public func spell(id: String) -> Spell? {
        spellsByID[id]
    }

    public func spells(ids: [String]) -> [Spell] {
        ids.compactMap { spellsByID[$0] }
    }

    /// Spells on a class's list, optionally limited to a range of spell levels.
    public func spells(forClass classID: String, levels: ClosedRange<Int> = 0...9) -> [Spell] {
        spells.filter { $0.classes.contains(classID) && levels.contains($0.level) }
    }
}
