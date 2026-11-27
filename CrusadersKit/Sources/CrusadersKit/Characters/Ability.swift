import Foundation

/// The six ability scores.
public enum Ability: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Identifiable, Sendable {
    case str, dex, con, int, wis, cha

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .str: return "Strength"
        case .dex: return "Dexterity"
        case .con: return "Constitution"
        case .int: return "Intelligence"
        case .wis: return "Wisdom"
        case .cha: return "Charisma"
        }
    }

    public var abbreviation: String { rawValue.uppercased() }
}

/// A full set of ability scores.
public struct AbilityScores: Codable, Hashable, Sendable {
    /// Scores you can type in while building a character, before racial bonuses.
    public static let baseRange = 3...18
    /// The most an ability can reach through racial bonuses and level-up improvements.
    public static let maximum = 20
    /// The SRD standard array.
    public static let standardArray = [15, 14, 13, 12, 10, 8]

    public var str: Int
    public var dex: Int
    public var con: Int
    public var int: Int
    public var wis: Int
    public var cha: Int

    public init(str: Int = 10, dex: Int = 10, con: Int = 10, int: Int = 10, wis: Int = 10, cha: Int = 10) {
        self.str = str
        self.dex = dex
        self.con = con
        self.int = int
        self.wis = wis
        self.cha = cha
    }

    public subscript(ability: Ability) -> Int {
        get {
            switch ability {
            case .str: return str
            case .dex: return dex
            case .con: return con
            case .int: return int
            case .wis: return wis
            case .cha: return cha
            }
        }
        set {
            switch ability {
            case .str: str = newValue
            case .dex: dex = newValue
            case .con: con = newValue
            case .int: int = newValue
            case .wis: wis = newValue
            case .cha: cha = newValue
            }
        }
    }

    /// The modifier for a score: (score - 10) / 2, rounded down.
    public static func modifier(for score: Int) -> Int {
        let difference = score - 10
        return difference >= 0 ? difference / 2 : (difference - 1) / 2
    }

    public func modifier(_ ability: Ability) -> Int {
        Self.modifier(for: self[ability])
    }

    /// Adds each bonus to its ability.
    public func adding(_ bonuses: [Ability: Int]) -> AbilityScores {
        var result = self
        for (ability, bonus) in bonuses {
            result[ability] += bonus
        }
        return result
    }

    /// Puts the standard array onto the abilities, highest first, in the given order.
    public static func standardArray(order: [Ability]) -> AbilityScores {
        var scores = AbilityScores()
        let fullOrder = order + Ability.allCases.filter { !order.contains($0) }
        for (ability, score) in zip(fullOrder, standardArray) {
            scores[ability] = score
        }
        return scores
    }
}

extension AbilityScores {
    /// Formats a modifier or bonus as "+2", "+0" or "-1".
    public static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}

/// The eighteen skills. Raw values match the SRD indexes.
public enum Skill: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case acrobatics
    case animalHandling = "animal-handling"
    case arcana
    case athletics
    case deception
    case history
    case insight
    case intimidation
    case investigation
    case medicine
    case nature
    case perception
    case performance
    case persuasion
    case religion
    case sleightOfHand = "sleight-of-hand"
    case stealth
    case survival

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .animalHandling: return "Animal Handling"
        case .sleightOfHand: return "Sleight of Hand"
        default: return rawValue.capitalized
        }
    }

    public var ability: Ability {
        switch self {
        case .athletics: return .str
        case .acrobatics, .sleightOfHand, .stealth: return .dex
        case .arcana, .history, .investigation, .nature, .religion: return .int
        case .animalHandling, .insight, .medicine, .perception, .survival: return .wis
        case .deception, .intimidation, .performance, .persuasion: return .cha
        }
    }
}
