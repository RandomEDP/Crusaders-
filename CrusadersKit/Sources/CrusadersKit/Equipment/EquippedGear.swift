import Foundation

/// A character's worn and held items and attunements, worked out from their loadout and inventory,
/// ready for the character sheet.
public struct EquippedGear: Hashable, Sendable {
    public var armour: GearItem?
    public var shield: GearItem?
    public var mainHand: GearItem?
    public var offHand: GearItem?
    public var usesBothHands: Bool
    /// Every attuned item in the inventory, worn or not.
    public var attuned: [GearItem]

    public init(armour: GearItem? = nil, shield: GearItem? = nil, mainHand: GearItem? = nil, offHand: GearItem? = nil,
                usesBothHands: Bool = false, attuned: [GearItem] = []) {
        self.armour = armour
        self.shield = shield
        self.mainHand = mainHand
        self.offHand = offHand
        self.usesBothHands = usesBothHands
        self.attuned = attuned
    }

    /// Nothing worn or held.
    public static let none = EquippedGear()

    /// Resolves a loadout against the inventory it belongs to. Items no longer in the inventory are left out.
    public init(loadout raw: Loadout, inventory: [InventoryEntry], catalog: ItemCatalog) {
        let loadout = raw.sanitized(inventory: inventory, catalog: catalog)
        self.init(
            armour: loadout.armourID.flatMap { loadout.gear($0, catalog: catalog) },
            shield: loadout.shieldID.flatMap { loadout.gear($0, catalog: catalog) },
            mainHand: loadout.mainHandID.flatMap { loadout.gear($0, catalog: catalog) },
            offHand: loadout.offHandID.flatMap { loadout.gear($0, catalog: catalog) },
            usesBothHands: loadout.usesBothHands,
            attuned: loadout.attunedIDs.compactMap { loadout.gear($0, catalog: catalog) }
        )
    }

    /// One worn or held item and where it is.
    public struct Slotted: Hashable, Sendable, Identifiable {
        public let slot: EquipSlot
        public let gear: GearItem
        public var id: EquipSlot { slot }
    }

    /// Worn and held items, in sheet order.
    public var equipped: [Slotted] {
        var list: [Slotted] = []
        if let armour { list.append(Slotted(slot: .armour, gear: armour)) }
        if let shield { list.append(Slotted(slot: .shield, gear: shield)) }
        if let mainHand { list.append(Slotted(slot: .mainHand, gear: mainHand)) }
        if let offHand { list.append(Slotted(slot: .offHand, gear: offHand)) }
        return list
    }

    /// Items whose magic counts: everything worn or held, plus attuned items, each once.
    var activeItems: [GearItem] {
        var seen = Set<String>()
        var items: [GearItem] = []
        for gear in equipped.map(\.gear) + attuned where seen.insert(gear.id).inserted {
            items.append(gear)
        }
        return items
    }

    public var isEmpty: Bool { equipped.isEmpty && attuned.isEmpty }
}

/// One attack the character can make with a held weapon (or an unarmed strike).
public struct WeaponAttack: Hashable, Sendable, Identifiable {
    public var id: String { "\(hand?.rawValue ?? "none")-\(name)" }
    public let name: String
    /// Nil for an unarmed strike.
    public let hand: EquipSlot?
    public let attackBonus: Int
    /// e.g. "1d8 + 3 slashing"
    public let damage: String
    public let notes: [String]
    /// The damage as dice to roll, e.g. 1d8 + 3. Nil for weapons that do no damage.
    public var damageDice: DamageDice? = nil
    public var damageType: DamageType = .none
    /// What the weapon fires, for bows, crossbows, slings and blowguns. Each attack uses one.
    public var ammunition: AmmoKind? = nil
}
