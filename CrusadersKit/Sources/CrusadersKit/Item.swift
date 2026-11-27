import Foundation

/// The drop-down headers inside Library > Items.
public enum ItemCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case weapons, armour, ammunition, potions, gear, tools

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weapons: return "Weapons"
        case .armour: return "Armour"
        case .ammunition: return "Ammunition"
        case .potions: return "Potions"
        case .gear: return "Adventuring Gear"
        case .tools: return "Tools"
        }
    }

    public var systemImage: String {
        switch self {
        case .weapons: return "hammer"
        case .armour: return "shield"
        case .ammunition: return "arrow.up.right"
        case .potions: return "flask"
        case .gear: return "backpack"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

public enum Coin: String, Codable, CaseIterable, Identifiable, Sendable {
    case cp, sp, ep, gp, pp

    public var id: String { rawValue }

    /// Value in copper pieces.
    public var copperValue: Int {
        switch self {
        case .cp: return 1
        case .sp: return 10
        case .ep: return 50
        case .gp: return 100
        case .pp: return 1000
        }
    }
}

public struct Cost: Codable, Hashable, Sendable {
    public var amount: Int
    public var coin: Coin

    public init(amount: Int, coin: Coin) {
        self.amount = amount
        self.coin = coin
    }

    public var inCopper: Int { amount * coin.copperValue }

    public var text: String { "\(amount) \(coin.rawValue)" }
}

public enum Rarity: String, Codable, CaseIterable, Identifiable, Sendable {
    case common, uncommon, rare, veryRare, legendary, artifact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .veryRare: return "Very rare"
        default: return rawValue.capitalized
        }
    }
}

public enum DamageType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, acid, bludgeoning, cold, fire, force, lightning, necrotic, piercing, poison, psychic, radiant, slashing, thunder

    public var id: String { rawValue }
    public var title: String { self == .none ? "None" : rawValue.capitalized }
}

public enum WeaponProperty: String, Codable, CaseIterable, Identifiable, Sendable {
    case ammunition, finesse, heavy, light, loading, reach, special, thrown, twoHanded, versatile

    public var id: String { rawValue }
    public var title: String { self == .twoHanded ? "Two-handed" : rawValue.capitalized }
}

public struct WeaponStats: Codable, Hashable, Sendable {
    /// Dice such as "1d8", "2d6", a flat number such as "1", or "0" for no damage.
    public var damage: String
    public var damageType: DamageType
    public var properties: [WeaponProperty]
    public var normalRange: Int?
    public var longRange: Int?
    public var versatileDamage: String?

    public init(damage: String, damageType: DamageType, properties: [WeaponProperty] = [],
                normalRange: Int? = nil, longRange: Int? = nil, versatileDamage: String? = nil) {
        self.damage = damage
        self.damageType = damageType
        self.properties = properties
        self.normalRange = normalRange
        self.longRange = longRange
        self.versatileDamage = versatileDamage
    }

    public var damageText: String {
        guard damage != "0", damageType != .none else { return "No damage" }
        return "\(damage) \(damageType.rawValue)"
    }

    public var propertiesText: String {
        let parts = properties.map { property -> String in
            switch property {
            case .ammunition, .thrown:
                if let normal = normalRange, let long = longRange {
                    return "\(property.title) (range \(normal)/\(long))"
                }
                return property.title
            case .versatile:
                if let versatile = versatileDamage { return "Versatile (\(versatile))" }
                return property.title
            default:
                return property.title
            }
        }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}

public enum ArmourKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, medium, heavy, shield

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ArmourStats: Codable, Hashable, Sendable {
    public var kind: ArmourKind
    /// Base AC for armour, or the bonus for a shield.
    public var baseArmorClass: Int
    public var addsDexterity: Bool
    public var maxDexterityBonus: Int?
    public var strengthRequirement: Int?
    public var stealthDisadvantage: Bool

    public init(kind: ArmourKind, baseArmorClass: Int, addsDexterity: Bool, maxDexterityBonus: Int? = nil,
                strengthRequirement: Int? = nil, stealthDisadvantage: Bool = false) {
        self.kind = kind
        self.baseArmorClass = baseArmorClass
        self.addsDexterity = addsDexterity
        self.maxDexterityBonus = maxDexterityBonus
        self.strengthRequirement = strengthRequirement
        self.stealthDisadvantage = stealthDisadvantage
    }

    public var armorClassText: String {
        if kind == .shield { return "+\(baseArmorClass)" }
        guard addsDexterity else { return "\(baseArmorClass)" }
        if let max = maxDexterityBonus { return "\(baseArmorClass) + Dex modifier (max \(max))" }
        return "\(baseArmorClass) + Dex modifier"
    }

    /// Armor Class a wearer with the given Dexterity modifier gets (for a shield, the bonus).
    public func armorClass(dexterityModifier: Int) -> Int {
        guard kind != .shield, addsDexterity else { return baseArmorClass }
        let dex = maxDexterityBonus.map { min(dexterityModifier, $0) } ?? dexterityModifier
        return baseArmorClass + dex
    }
}

/// One weapon, suit of armour, potion, piece of ammunition, gear or tool in Library > Items.
/// Every field is editable by the app's creator.
public struct EquipmentItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var category: ItemCategory
    /// Sub-heading within the category, such as "Martial Melee" or "Heavy Armour".
    public var group: String
    public var cost: Cost?
    /// Weight in pounds.
    public var weight: Double?
    public var rarity: Rarity?
    public var requiresAttunement: Bool
    public var description: String
    public var weapon: WeaponStats?
    public var armour: ArmourStats?

    public init(id: String, name: String, category: ItemCategory, group: String, cost: Cost? = nil, weight: Double? = nil,
                rarity: Rarity? = nil, requiresAttunement: Bool = false, description: String = "",
                weapon: WeaponStats? = nil, armour: ArmourStats? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.group = group
        self.cost = cost
        self.weight = weight
        self.rarity = rarity
        self.requiresAttunement = requiresAttunement
        self.description = description
        self.weapon = weapon
        self.armour = armour
    }

    public var isMagic: Bool { rarity != nil }

    public var weightText: String? {
        guard let weight, weight > 0 else { return nil }
        let number = weight.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) lb"
    }

    /// A one-line summary shown under the item's name in lists.
    public var summary: String {
        var parts: [String] = []
        if let weapon { parts.append(weapon.damageText) }
        if let armour { parts.append("AC \(armour.armorClassText)") }
        if let rarity {
            parts.append(requiresAttunement ? "\(rarity.title), attunement" : rarity.title)
        }
        if let cost { parts.append(cost.text) }
        if parts.isEmpty, let weightText { parts.append(weightText) }
        return parts.joined(separator: " · ")
    }
}
