import Foundation

/// A named rule: a racial trait, a class feature or a subclass feature.
public struct RuleText: Codable, Hashable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// "Choose N abilities and add a bonus to each", as Half-Elves do.
public struct AbilityBonusChoice: Codable, Hashable, Sendable {
    public let count: Int
    public let bonus: Int
    public let from: [Ability]
}

public struct Subrace: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let abilityBonuses: [Ability: Int]
    public let traits: [RuleText]
}

public struct Race: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let speed: Int
    public let size: String
    public let abilityBonuses: [Ability: Int]
    public let languages: String
    public let age: String
    public let alignment: String
    public let traits: [RuleText]
    public let subraces: [Subrace]
    public let abilityBonusChoice: AbilityBonusChoice?

    /// Skills every member of the race is proficient in (Elf: Keen Senses, Half-Orc: Menacing).
    public var grantedSkills: Set<Skill> {
        switch id {
        case "elf": return [.perception]
        case "half-orc": return [.intimidation]
        default: return []
        }
    }

    /// Extra skills of the player's choice (Half-Elf: Skill Versatility).
    public var extraSkillChoices: Int {
        id == "half-elf" ? 2 : 0
    }

    public func subrace(id: String?) -> Subrace? {
        guard let id else { return nil }
        return subraces.first { $0.id == id }
    }
}

public struct SkillChoice: Codable, Hashable, Sendable {
    public let count: Int
    public let from: [Skill]
}

/// What a class gains at one level.
public struct ClassLevel: Codable, Hashable, Sendable {
    public let level: Int
    public let proficiencyBonus: Int
    public let abilityScoreImprovement: Bool
    public let features: [RuleText]
    /// Class-specific numbers such as "Rage count" or "Sneak attack", as display text.
    public let counters: [String: String]
    /// Spell slots for spell levels 1 to 9. Nil for classes that don't cast.
    public let spellSlots: [Int]?
    public let cantripsKnown: Int?
    public let spellsKnown: Int?

    /// The highest spell level this level has a slot for, or 0.
    public var highestSpellLevel: Int {
        guard let spellSlots else { return 0 }
        return (spellSlots.lastIndex { $0 > 0 }).map { $0 + 1 } ?? 0
    }

    /// Counters that are in use at this level (hides zero and "No").
    public var activeCounters: [String: String] {
        counters.filter { $0.value != "0" && $0.value != "No" }
    }
}

public struct Subclass: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// What the class calls its subclasses, such as "Divine Domain".
    public let flavor: String
    public let description: String
    /// Features keyed by class level ("3": [...]).
    public let features: [String: [RuleText]]
    /// Spell ids the subclass adds, keyed by class level.
    public let bonusSpells: [String: [String]]

    public func features(atLevel level: Int) -> [RuleText] {
        features[String(level)] ?? []
    }

    public func bonusSpellIDs(atLevel level: Int) -> [String] {
        bonusSpells[String(level)] ?? []
    }

    public func bonusSpellIDs(upToLevel level: Int) -> [String] {
        guard level >= 1 else { return [] }
        return (1...level).flatMap { bonusSpellIDs(atLevel: $0) }
    }
}

public struct CharacterClass: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let hitDie: Int
    public let savingThrows: [Ability]
    /// Armour, weapon and tool proficiencies.
    public let proficiencies: [String]
    public let skillChoices: SkillChoice
    /// The class level the subclass is chosen at.
    public let subclassLevel: Int
    public let subclass: Subclass
    /// One entry per level, 1 to 20.
    public let levels: [ClassLevel]
    public let spellcastingAbility: Ability?

    public func level(_ number: Int) -> ClassLevel? {
        levels.first { $0.level == number }
    }

    /// The order to place the standard array in, best ability first.
    public var suggestedAbilityOrder: [Ability] {
        switch id {
        case "barbarian": return [.str, .con, .dex, .wis, .cha, .int]
        case "bard": return [.cha, .dex, .con, .wis, .int, .str]
        case "cleric": return [.wis, .con, .str, .dex, .cha, .int]
        case "druid": return [.wis, .con, .dex, .int, .cha, .str]
        case "fighter": return [.str, .con, .dex, .wis, .cha, .int]
        case "monk": return [.dex, .wis, .con, .str, .int, .cha]
        case "paladin": return [.str, .cha, .con, .wis, .dex, .int]
        case "ranger": return [.dex, .wis, .con, .str, .int, .cha]
        case "rogue": return [.dex, .con, .int, .wis, .cha, .str]
        case "sorcerer", "warlock": return [.cha, .con, .dex, .wis, .int, .str]
        case "wizard": return [.int, .con, .dex, .wis, .cha, .str]
        default: return Ability.allCases
        }
    }
}

public struct Spell: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// 0 for cantrips.
    public let level: Int
    public let school: String
    public let castingTime: String
    public let range: String
    public let components: [String]
    public let material: String?
    public let duration: String
    public let concentration: Bool
    public let ritual: Bool
    public let description: String
    public let higherLevel: String?
    /// Ids of the classes that have this spell on their list.
    public let classes: [String]

    public var isCantrip: Bool { level == 0 }

    /// e.g. "Cantrip", "1st level", "3rd level"
    public var levelLabel: String { Spell.label(forLevel: level) }

    /// e.g. "2nd-level evocation" or "Evocation cantrip"
    public var subtitle: String {
        level == 0 ? "\(school) cantrip" : "\(Spell.ordinal(level))-level \(school.lowercased())"
    }

    public static func label(forLevel level: Int) -> String {
        level == 0 ? "Cantrips" : "\(ordinal(level)) level"
    }

    public static func ordinal(_ number: Int) -> String {
        switch number {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(number)th"
        }
    }
}
