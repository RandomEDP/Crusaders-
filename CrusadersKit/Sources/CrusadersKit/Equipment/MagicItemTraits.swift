import Foundation

/// Which ordinary item a magic item is made from, e.g. "any sword" or "plate".
public enum BaseRequirement: Hashable, Sendable {
    /// Light, medium or heavy armour.
    case anyArmour
    /// Medium or heavy armour, but not hide (adamantine and mithral).
    case mediumOrHeavyArmourExceptHide
    case anyWeapon
    case anySword
    /// Longsword, greatsword or scimitar.
    case anySlashingSword
    case anyAxe
    case anyAxeOrSword
    /// Exactly one item, e.g. Dwarven Plate is plate.
    case item(String)

    static let swords = ["longsword", "shortsword", "greatsword", "rapier", "scimitar"]
    static let slashingSwords = ["longsword", "greatsword", "scimitar"]
    static let axes = ["handaxe", "battleaxe", "greataxe"]

    /// The catalog items that fit, in catalog order. Only ordinary (non-magic) items with stats count.
    public func options(in catalog: ItemCatalog) -> [EquipmentItem] {
        catalog.items.filter { item in
            guard !item.isMagic else { return false }
            switch self {
            case .anyArmour:
                guard let kind = item.armour?.kind else { return false }
                return kind != .shield
            case .mediumOrHeavyArmourExceptHide:
                guard let kind = item.armour?.kind else { return false }
                return (kind == .medium || kind == .heavy) && item.id != "hide"
            case .anyWeapon: return item.weapon != nil
            case .anySword: return item.weapon != nil && Self.swords.contains(item.id)
            case .anySlashingSword: return item.weapon != nil && Self.slashingSwords.contains(item.id)
            case .anyAxe: return item.weapon != nil && Self.axes.contains(item.id)
            case .anyAxeOrSword: return item.weapon != nil && (Self.axes + Self.swords).contains(item.id)
            case .item(let id): return item.id == id && (item.weapon != nil || item.armour != nil)
            }
        }
    }
}

/// The parts of a magic weapon or armour that change the character sheet (SRD 5.1).
public struct MagicItemTraits: Hashable, Sendable {
    /// What it's made from, when the Library item has no weapon or armour stats of its own.
    public var base: BaseRequirement?
    /// Added to Armor Class while worn or held.
    public var armorClassBonus: Int
    /// Added to attack and damage rolls made with it.
    public var attackBonus: Int
    /// Added to every saving throw.
    public var savingThrowBonus: Int
    /// Extra hit points per character level (Berserker Axe).
    public var hitPointsPerLevel: Int
    /// No Strength requirement (Mithral).
    public var ignoresStrengthRequirement: Bool
    /// No disadvantage on Stealth (Mithral).
    public var ignoresStealthDisadvantage: Bool
    /// Counts as proficient even without the armour proficiency (Elven Chain).
    public var alwaysProficient: Bool
    /// Damage type it deals instead of the base weapon's (Sun Blade: radiant).
    public var damageType: DamageType?
    /// Properties it gains (Sun Blade: finesse; Dwarven Thrower: thrown).
    public var addedProperties: [WeaponProperty]
    /// Extra effects shown under the attack, e.g. "+1d6 cold damage".
    public var attackNote: String?

    public init(base: BaseRequirement? = nil, armorClassBonus: Int = 0, attackBonus: Int = 0, savingThrowBonus: Int = 0,
                hitPointsPerLevel: Int = 0, ignoresStrengthRequirement: Bool = false, ignoresStealthDisadvantage: Bool = false,
                alwaysProficient: Bool = false, damageType: DamageType? = nil, addedProperties: [WeaponProperty] = [],
                attackNote: String? = nil) {
        self.base = base
        self.armorClassBonus = armorClassBonus
        self.attackBonus = attackBonus
        self.savingThrowBonus = savingThrowBonus
        self.hitPointsPerLevel = hitPointsPerLevel
        self.ignoresStrengthRequirement = ignoresStrengthRequirement
        self.ignoresStealthDisadvantage = ignoresStealthDisadvantage
        self.alwaysProficient = alwaysProficient
        self.damageType = damageType
        self.addedProperties = addedProperties
        self.attackNote = attackNote
    }

    public static let none = MagicItemTraits()

    /// Traits for the SRD magic weapons and armour in Library > Items, by item id.
    public static func srd(_ itemID: String) -> MagicItemTraits? {
        table[itemID]
    }

    static let table: [String: MagicItemTraits] = [
        // Weapons
        "weapon-plus-1": .init(base: .anyWeapon, attackBonus: 1),
        "weapon-plus-2": .init(base: .anyWeapon, attackBonus: 2),
        "weapon-plus-3": .init(base: .anyWeapon, attackBonus: 3),
        "berserker-axe": .init(base: .anyAxe, attackBonus: 1, hitPointsPerLevel: 1),
        "dagger-of-venom": .init(base: .item("dagger"), attackBonus: 1),
        "dancing-sword": .init(base: .anySword),
        "defender": .init(base: .anySword, attackBonus: 3),
        "dragon-slayer": .init(base: .anySword, attackBonus: 1, attackNote: "+3d6 damage against dragons"),
        "dwarven-thrower": .init(base: .item("warhammer"), attackBonus: 3, addedProperties: [.thrown],
                                 attackNote: "Thrown 20/60 and returns; +1d8 (+2d8 vs giants) when thrown"),
        "flame-tongue": .init(base: .anySword, attackNote: "+2d6 fire damage while ablaze"),
        "frost-brand": .init(base: .anySword, attackNote: "+1d6 cold damage; resistance to fire"),
        "giant-slayer": .init(base: .anyAxeOrSword, attackBonus: 1, attackNote: "+2d6 damage against giants"),
        "hammer-of-thunderbolts": .init(base: .item("maul"), attackBonus: 1),
        "holy-avenger": .init(base: .anySword, attackBonus: 3, attackNote: "+2d10 radiant against fiends and undead"),
        "javelin-of-lightning": .init(base: .item("javelin")),
        "luck-blade": .init(base: .anySword, attackBonus: 1, savingThrowBonus: 1),
        "mace-of-disruption": .init(base: .item("mace"), attackNote: "+2d6 radiant against fiends and undead"),
        "mace-of-smiting": .init(base: .item("mace"), attackBonus: 1, attackNote: "+3 instead of +1 against constructs"),
        "mace-of-terror": .init(base: .item("mace")),
        "nine-lives-stealer": .init(base: .anySword, attackBonus: 2),
        "oathbow": .init(base: .item("longbow"), attackNote: "+3d6 piercing against your sworn enemy"),
        "scimitar-of-speed": .init(base: .item("scimitar"), attackBonus: 2, attackNote: "One extra attack as a bonus action"),
        "sun-blade": .init(base: .item("longsword"), attackBonus: 2, damageType: .radiant, addedProperties: [.finesse],
                           attackNote: "+1d8 radiant against undead"),
        "sword-of-life-stealing": .init(base: .anySword, attackNote: "On a 20: +3d6 necrotic and you gain that many temp HP"),
        "sword-of-sharpness": .init(base: .anySlashingSword, attackNote: "On a 20: +4d6 slashing"),
        "sword-of-wounding": .init(base: .anySword, attackNote: "Once per turn: wound for 1d4 necrotic each turn"),
        "trident-of-fish-command": .init(base: .item("trident")),
        "vicious-weapon": .init(base: .anyWeapon, attackNote: "On a 20: +2d6 damage"),
        "vorpal-sword": .init(base: .anySlashingSword, attackBonus: 3, attackNote: "Ignores resistance to slashing"),

        // Armour
        "armor-plus-1": .init(base: .anyArmour, armorClassBonus: 1),
        "armor-plus-2": .init(base: .anyArmour, armorClassBonus: 2),
        "armor-plus-3": .init(base: .anyArmour, armorClassBonus: 3),
        "adamantine-armor": .init(base: .mediumOrHeavyArmourExceptHide),
        "armor-of-invulnerability": .init(base: .item("plate")),
        "armor-of-resistance": .init(base: .anyArmour),
        "armor-of-vulnerability": .init(base: .item("plate")),
        "demon-armor": .init(base: .item("plate"), armorClassBonus: 1),
        "dragon-scale-mail": .init(base: .item("scale-mail"), armorClassBonus: 1),
        "dwarven-plate": .init(base: .item("plate"), armorClassBonus: 2),
        "efreeti-chain": .init(base: .item("chain-mail"), armorClassBonus: 3),
        "elven-chain": .init(base: .item("chain-shirt"), armorClassBonus: 1, alwaysProficient: true),
        "glamoured-studded-leather": .init(base: .item("studded-leather"), armorClassBonus: 1),
        "mithral-armor": .init(base: .mediumOrHeavyArmourExceptHide, ignoresStrengthRequirement: true,
                               ignoresStealthDisadvantage: true),
        "plate-armor-of-etherealness": .init(base: .item("plate")),
        "shield-plus-1": .init(base: .item("shield"), armorClassBonus: 1),
        "shield-plus-2": .init(base: .item("shield"), armorClassBonus: 2),
        "shield-plus-3": .init(base: .item("shield"), armorClassBonus: 3),
        "animated-shield": .init(base: .item("shield")),
        "arrow-catching-shield": .init(base: .item("shield")),
        "shield-of-missile-attraction": .init(base: .item("shield")),
        "spellguard-shield": .init(base: .item("shield")),
    ]
}
