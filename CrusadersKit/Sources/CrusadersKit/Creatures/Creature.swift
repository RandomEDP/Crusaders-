import Foundation

/// How big a creature is.
public enum CreatureSize: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case tiny, small, medium, large, huge, gargantuan

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// The kind of creature. Library > Creatures shows one drop-down header per type.
public enum CreatureType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case aberration, beast, celestial, construct, dragon, elemental, fey, fiend, giant, humanoid
    case monstrosity, ooze, plant, swarm, undead

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    /// The header title: "Beasts", "Fey", "Undead".
    public var pluralTitle: String {
        switch self {
        case .fey, .undead: return title
        case .monstrosity: return "Monstrosities"
        default: return title + "s"
        }
    }

    public var systemImage: String {
        switch self {
        case .aberration: return "eye"
        case .beast: return "pawprint"
        case .celestial: return "sun.max"
        case .construct: return "gearshape.2"
        case .dragon: return "flame"
        case .elemental: return "tornado"
        case .fey: return "leaf"
        case .fiend: return "bolt.horizontal"
        case .giant: return "figure.stand"
        case .humanoid: return "person.2"
        case .monstrosity: return "tortoise"
        case .ooze: return "drop"
        case .plant: return "tree"
        case .swarm: return "ant"
        case .undead: return "moon.stars"
        }
    }
}

/// A named trait, action, reaction or legendary action in a stat block.
public struct CreatureFeature: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name + "\n" + description }
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// Challenge rating: how tough a creature is. 1/8, 1/4 and 1/2 are stored as 0.125, 0.25 and 0.5.
public enum ChallengeRating {
    /// Every rating from the 5e rules, lowest first.
    public static let all: [Double] = [0, 0.125, 0.25, 0.5] + (1...30).map(Double.init)

    /// "1/4", "1/2", "5".
    public static func text(_ rating: Double) -> String {
        switch rating {
        case 0.125: return "1/8"
        case 0.25: return "1/4"
        case 0.5: return "1/2"
        default: return rating == rating.rounded() ? String(Int(rating)) : String(rating)
        }
    }

    public static func isValid(_ rating: Double) -> Bool { all.contains(rating) }

    /// Experience points for defeating a creature of this rating (SRD table).
    public static func experience(_ rating: Double) -> Int {
        switch rating {
        case 0: return 10
        case 0.125: return 25
        case 0.25: return 50
        case 0.5: return 100
        default:
            let table = [200, 450, 700, 1100, 1800, 2300, 2900, 3900, 5000, 5900,
                         7200, 8400, 10000, 11500, 13000, 15000, 18000, 20000, 22000, 25000,
                         33000, 41000, 50000, 62000, 75000, 90000, 105000, 120000, 135000, 155000]
            let index = Int(rating) - 1
            return table.indices.contains(index) ? table[index] : 0
        }
    }

    /// Proficiency bonus by rating: +2 up to CR 4, then +1 every 4 ratings.
    public static func proficiencyBonus(_ rating: Double) -> Int {
        rating < 5 ? 2 : 2 + (Int(rating) - 1) / 4
    }
}

/// A monster, animal or NPC stat block. Built-in ones come from the SRD 5.1; the creator can add more.
public struct Creature: Identifiable, Codable, Hashable, Sendable {
    /// Ids of creatures the creator adds start with this.
    public static let customPrefix = "custom-"

    public let id: String
    public var name: String
    public var size: CreatureSize
    public var type: CreatureType
    /// E.g. "goblinoid", "shapechanger".
    public var subtype: String?
    public var alignment: String
    public var armorClass: Int
    /// E.g. "natural armor" or "leather armor, shield".
    public var armorNote: String?
    public var hitPoints: Int
    /// E.g. "2d6" or "19d12 + 133".
    public var hitDice: String
    /// E.g. "30 ft., fly 60 ft.".
    public var speed: String
    public var abilities: AbilityScores
    public var savingThrows: String?
    public var skills: String?
    public var damageVulnerabilities: String?
    public var damageResistances: String?
    public var damageImmunities: String?
    public var conditionImmunities: String?
    public var senses: String
    public var languages: String
    public var challengeRating: Double
    public var traits: [CreatureFeature]
    public var actions: [CreatureFeature]
    public var reactions: [CreatureFeature]
    public var legendaryActions: [CreatureFeature]
    /// Lore or notes shown under the stat block.
    public var description: String?

    public init(
        id: String, name: String, size: CreatureSize, type: CreatureType, subtype: String? = nil,
        alignment: String = "unaligned", armorClass: Int = 10, armorNote: String? = nil,
        hitPoints: Int = 1, hitDice: String = "1d8", speed: String = "30 ft.",
        abilities: AbilityScores = AbilityScores(), savingThrows: String? = nil, skills: String? = nil,
        damageVulnerabilities: String? = nil, damageResistances: String? = nil, damageImmunities: String? = nil,
        conditionImmunities: String? = nil, senses: String = "passive Perception 10", languages: String = "—",
        challengeRating: Double = 0, traits: [CreatureFeature] = [], actions: [CreatureFeature] = [],
        reactions: [CreatureFeature] = [], legendaryActions: [CreatureFeature] = [], description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.type = type
        self.subtype = subtype
        self.alignment = alignment
        self.armorClass = armorClass
        self.armorNote = armorNote
        self.hitPoints = hitPoints
        self.hitDice = hitDice
        self.speed = speed
        self.abilities = abilities
        self.savingThrows = savingThrows
        self.skills = skills
        self.damageVulnerabilities = damageVulnerabilities
        self.damageResistances = damageResistances
        self.damageImmunities = damageImmunities
        self.conditionImmunities = conditionImmunities
        self.senses = senses
        self.languages = languages
        self.challengeRating = challengeRating
        self.traits = traits
        self.actions = actions
        self.reactions = reactions
        self.legendaryActions = legendaryActions
        self.description = description
    }

    /// A blank creature for the creator to fill in, with a new unique id.
    public static func newCustom(id: String = Creature.customPrefix + UUID().uuidString.lowercased()) -> Creature {
        Creature(id: id, name: "", size: .medium, type: .humanoid, alignment: "neutral",
                 actions: [CreatureFeature(name: "Club", description: "Melee Weapon Attack: +2 to hit, reach 5 ft., one target. Hit: 2 (1d4) bludgeoning damage.")])
    }

    /// Whether the creator added this creature (rather than it coming from the SRD).
    public var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    /// "Medium humanoid (goblinoid), neutral evil".
    public var typeLine: String {
        var line = "\(size.title) "
        if type == .swarm {
            line += "swarm of \(subtype ?? "Tiny creatures")"
        } else {
            line += type.rawValue
            if let subtype, !subtype.isEmpty { line += " (\(subtype))" }
        }
        return line + ", " + alignment
    }

    /// "Small humanoid · CR 1/4", for list rows.
    public var summary: String {
        "\(size.title) \(type == .swarm ? "swarm" : type.rawValue) · CR \(challengeRatingText)"
    }

    public var challengeRatingText: String { ChallengeRating.text(challengeRating) }
    public var experience: Int { ChallengeRating.experience(challengeRating) }
    public var proficiencyBonus: Int { ChallengeRating.proficiencyBonus(challengeRating) }

    /// "15 (leather armor, shield)".
    public var armorClassText: String {
        guard let armorNote, !armorNote.isEmpty else { return "\(armorClass)" }
        return "\(armorClass) (\(armorNote))"
    }

    /// "7 (2d6)".
    public var hitPointsText: String {
        hitDice.isEmpty ? "\(hitPoints)" : "\(hitPoints) (\(hitDice))"
    }

    /// "14 (+2)".
    public func abilityText(_ ability: Ability) -> String {
        "\(abilities[ability]) (\(AbilityScores.signed(abilities.modifier(ability))))"
    }
}
