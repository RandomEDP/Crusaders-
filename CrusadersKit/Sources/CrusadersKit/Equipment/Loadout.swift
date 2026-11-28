import Foundation

/// Where an item is worn or held.
public enum EquipSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Body armour (light, medium or heavy). Only one at a time.
    case armour
    /// A shield, held in the off hand. Only one at a time.
    case shield
    case mainHand
    case offHand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .armour: return "Worn"
        case .shield: return "Shield"
        case .mainHand: return "Main hand"
        case .offHand: return "Off hand"
        }
    }
}

public enum EquipError: Error, Equatable, Sendable {
    case notInInventory
    /// Potions, gear and the like can't be worn or wielded.
    case notEquippable
    /// A magic item like "Armor, +1" needs its base armour or weapon picked first.
    case needsBaseItem
    case invalidBaseItem
    case wrongSlot
    /// Two-handed weapons (and versatile ones used with both hands) need both hands free. Holds what's in the way.
    case needsBothHands(blockedBy: String)
    /// Something is already in the off hand or both hands are on a weapon. Holds what's in the way.
    case handsFull(blockedBy: String)
    case notVersatile
    case noAttunementNeeded
    case attunementFull
}

/// One inventory item as it's worn or held: the Library item, the ordinary item it's made from
/// (for magic items like "Armor, +1"), and its magic traits.
public struct GearItem: Hashable, Sendable {
    public let item: EquipmentItem
    /// The ordinary armour or weapon a magic item is made from, if it has no stats of its own.
    public let base: EquipmentItem?
    public let traits: MagicItemTraits
    /// Whether the character is attuned to it.
    public let isAttuned: Bool

    public init(item: EquipmentItem, base: EquipmentItem? = nil, isAttuned: Bool = false) {
        self.item = item
        self.base = base
        self.traits = MagicItemTraits.srd(item.id) ?? .none
        self.isAttuned = isAttuned
    }

    public var id: String { item.id }

    /// e.g. "Armor, +1 (Chain Mail)"
    public var name: String {
        guard let base, base.id != item.id, !item.name.localizedCaseInsensitiveContains(base.name) else { return item.name }
        return "\(item.name) (\(base.name))"
    }

    /// Magic only works once attuned, for items that need attunement.
    public var magicIsActive: Bool { !item.requiresAttunement || isAttuned }

    /// The armour stats in use, with Mithral's changes applied.
    public var armour: ArmourStats? {
        guard var stats = item.armour ?? base?.armour else { return nil }
        if traits.ignoresStrengthRequirement && magicIsActive { stats.strengthRequirement = nil }
        if traits.ignoresStealthDisadvantage && magicIsActive { stats.stealthDisadvantage = false }
        return stats
    }

    /// The weapon stats in use, with added properties and damage type applied.
    public var weapon: WeaponStats? {
        guard var stats = item.weapon ?? base?.weapon else { return nil }
        for property in traits.addedProperties where !stats.properties.contains(property) {
            stats.properties.append(property)
        }
        if let type = traits.damageType { stats.damageType = type }
        if traits.addedProperties.contains(.thrown) && stats.normalRange == nil {
            stats.normalRange = 20
            stats.longRange = 60
        }
        return stats
    }

    /// "Simple Melee", "Heavy Armour"… from whichever item has the stats.
    public var group: String {
        (item.weapon != nil || item.armour != nil) ? item.group : (base?.group ?? item.group)
    }

    /// The item whose name decides weapon proficiency (a +1 longsword is still a longsword).
    public var proficiencyItem: EquipmentItem { (item.weapon != nil || item.armour != nil) ? item : (base ?? item) }

    public var armorClassBonus: Int { magicIsActive ? traits.armorClassBonus : 0 }
    public var attackBonus: Int { magicIsActive ? traits.attackBonus : 0 }
    public var savingThrowBonus: Int { magicIsActive ? traits.savingThrowBonus : 0 }
    public var hitPointsPerLevel: Int { magicIsActive ? traits.hitPointsPerLevel : 0 }

    public var isTwoHanded: Bool { weapon?.properties.contains(.twoHanded) ?? false }
    public var isVersatile: Bool { weapon?.properties.contains(.versatile) ?? false }
    public var isLight: Bool { weapon?.properties.contains(.light) ?? false }

    /// Where it can go: body armour, shield, or a hand. Two-handed weapons only go in the main hand (using both).
    public var allowedSlots: [EquipSlot] {
        if let armour {
            return armour.kind == .shield ? [.shield] : [.armour]
        }
        if weapon != nil {
            return isTwoHanded ? [.mainHand] : [.mainHand, .offHand]
        }
        return []
    }

    /// The ordinary items this magic item can be made from. Empty for items that have their own stats.
    public static func baseOptions(for item: EquipmentItem, in catalog: ItemCatalog) -> [EquipmentItem] {
        guard item.weapon == nil, item.armour == nil, let base = MagicItemTraits.srd(item.id)?.base else { return [] }
        return base.options(in: catalog)
    }
}

/// What a character wears and holds, and which magic items they're attuned to (5e SRD rules):
/// one suit of body armour, one shield, a main and an off hand, and at most 3 attuned items.
public struct Loadout: Codable, Hashable, Sendable {
    public static let maxAttuned = 3

    public var armourID: String?
    public var shieldID: String?
    public var mainHandID: String?
    public var offHandID: String?
    /// A versatile weapon in the main hand used with both hands (bigger damage die).
    public var usesBothHands: Bool
    public var attunedIDs: [String]
    /// For magic items without their own stats: the ordinary item each one is, e.g. "armor-plus-1": "chain-mail".
    public var baseItemIDs: [String: String]

    public init(armourID: String? = nil, shieldID: String? = nil, mainHandID: String? = nil, offHandID: String? = nil,
                usesBothHands: Bool = false, attunedIDs: [String] = [], baseItemIDs: [String: String] = [:]) {
        self.armourID = armourID
        self.shieldID = shieldID
        self.mainHandID = mainHandID
        self.offHandID = offHandID
        self.usesBothHands = usesBothHands
        self.attunedIDs = attunedIDs
        self.baseItemIDs = baseItemIDs
    }

    enum CodingKeys: String, CodingKey {
        case armourID, shieldID, mainHandID, offHandID, usesBothHands, attunedIDs, baseItemIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            armourID: try container.decodeIfPresent(String.self, forKey: .armourID),
            shieldID: try container.decodeIfPresent(String.self, forKey: .shieldID),
            mainHandID: try container.decodeIfPresent(String.self, forKey: .mainHandID),
            offHandID: try container.decodeIfPresent(String.self, forKey: .offHandID),
            usesBothHands: try container.decodeIfPresent(Bool.self, forKey: .usesBothHands) ?? false,
            attunedIDs: try container.decodeIfPresent([String].self, forKey: .attunedIDs) ?? [],
            baseItemIDs: try container.decodeIfPresent([String: String].self, forKey: .baseItemIDs) ?? [:]
        )
    }

    public static let empty = Loadout()

    /// The slots an item is in, e.g. [.mainHand, .offHand] for two daggers.
    public func slots(of itemID: String) -> [EquipSlot] {
        var slots: [EquipSlot] = []
        if armourID == itemID { slots.append(.armour) }
        if shieldID == itemID { slots.append(.shield) }
        if mainHandID == itemID { slots.append(.mainHand) }
        if offHandID == itemID { slots.append(.offHand) }
        return slots
    }

    public func isEquipped(_ itemID: String) -> Bool { !slots(of: itemID).isEmpty }

    public func isAttuned(_ itemID: String) -> Bool { attunedIDs.contains(itemID) }

    /// The item as worn or held, with its chosen base item.
    public func gear(_ itemID: String, catalog: ItemCatalog) -> GearItem? {
        guard let item = catalog.item(id: itemID) else { return nil }
        let options = GearItem.baseOptions(for: item, in: catalog)
        var base: EquipmentItem?
        if let chosen = baseItemIDs[itemID], let match = options.first(where: { $0.id == chosen }) {
            base = match
        } else if options.count == 1 {
            base = options[0]
        }
        return GearItem(item: item, base: base, isAttuned: isAttuned(itemID))
    }

    private func name(_ itemID: String?, catalog: ItemCatalog) -> String {
        guard let itemID else { return "" }
        return gear(itemID, catalog: catalog)?.name ?? itemID
    }

    // MARK: Changing it

    /// Wears or wields an item. Something already in that slot is swapped out; anything else in the way is an error.
    public mutating func equip(_ itemID: String, in slot: EquipSlot, base baseID: String? = nil,
                               inventory: [InventoryEntry], catalog: ItemCatalog) throws {
        guard let entry = inventory.first(where: { $0.itemID == itemID }), entry.quantity > 0 else {
            throw EquipError.notInInventory
        }
        guard let item = catalog.item(id: itemID) else { throw EquipError.notEquippable }

        let options = GearItem.baseOptions(for: item, in: catalog)
        if !options.isEmpty {
            let chosen = baseID ?? baseItemIDs[itemID] ?? (options.count == 1 ? options[0].id : nil)
            guard let chosen else { throw EquipError.needsBaseItem }
            guard options.contains(where: { $0.id == chosen }) else { throw EquipError.invalidBaseItem }
            baseItemIDs[itemID] = chosen
        }
        guard let gear = gear(itemID, catalog: catalog), !gear.allowedSlots.isEmpty else {
            throw EquipError.notEquippable
        }
        guard gear.allowedSlots.contains(slot) else { throw EquipError.wrongSlot }

        switch slot {
        case .armour:
            armourID = itemID
        case .shield:
            if let main = mainHandID, mainWeaponNeedsBothHands(catalog: catalog) {
                throw EquipError.handsFull(blockedBy: name(main, catalog: catalog))
            }
            if let off = offHandID {
                throw EquipError.handsFull(blockedBy: name(off, catalog: catalog))
            }
            shieldID = itemID
        case .mainHand:
            if gear.isTwoHanded {
                if let shieldID { throw EquipError.needsBothHands(blockedBy: name(shieldID, catalog: catalog)) }
                if let offHandID, offHandID != itemID {
                    throw EquipError.needsBothHands(blockedBy: name(offHandID, catalog: catalog))
                }
                offHandID = nil
            } else if offHandID == itemID && entry.quantity < 2 {
                offHandID = nil
            }
            mainHandID = itemID
            usesBothHands = false
        case .offHand:
            if let main = mainHandID, mainWeaponNeedsBothHands(catalog: catalog), main != itemID {
                throw EquipError.handsFull(blockedBy: name(main, catalog: catalog))
            }
            if let shieldID { throw EquipError.handsFull(blockedBy: name(shieldID, catalog: catalog)) }
            if mainHandID == itemID {
                // One copy moves across; with two or more, one goes in each hand.
                if entry.quantity < 2 { mainHandID = nil }
                usesBothHands = false
            }
            offHandID = itemID
        }
    }

    /// Takes an item off or puts it away. Attunement stays until it's ended.
    public mutating func unequip(_ itemID: String) {
        if armourID == itemID { armourID = nil }
        if shieldID == itemID { shieldID = nil }
        if mainHandID == itemID {
            mainHandID = nil
            usesBothHands = false
        }
        if offHandID == itemID { offHandID = nil }
    }

    /// Switches a versatile main-hand weapon between one and two hands.
    public mutating func setUsesBothHands(_ both: Bool, catalog: ItemCatalog) throws {
        guard both else {
            usesBothHands = false
            return
        }
        guard let main = mainHandID, let gear = gear(main, catalog: catalog), gear.isVersatile else {
            throw EquipError.notVersatile
        }
        if let shieldID { throw EquipError.needsBothHands(blockedBy: name(shieldID, catalog: catalog)) }
        if let offHandID { throw EquipError.needsBothHands(blockedBy: name(offHandID, catalog: catalog)) }
        usesBothHands = true
    }

    /// Attunes to a magic item that needs it. At most 3 at a time.
    public mutating func attune(_ itemID: String, inventory: [InventoryEntry], catalog: ItemCatalog) throws {
        guard inventory.contains(where: { $0.itemID == itemID && $0.quantity > 0 }) else { throw EquipError.notInInventory }
        guard let item = catalog.item(id: itemID), item.requiresAttunement else { throw EquipError.noAttunementNeeded }
        guard !attunedIDs.contains(itemID) else { return }
        guard attunedIDs.count < Self.maxAttuned else { throw EquipError.attunementFull }
        attunedIDs.append(itemID)
    }

    public mutating func endAttunement(_ itemID: String) {
        attunedIDs.removeAll { $0 == itemID }
    }

    /// Drops anything that's no longer in the inventory (or no longer fits the rules), e.g. after the DM removes it.
    public func sanitized(inventory: [InventoryEntry], catalog: ItemCatalog) -> Loadout {
        func quantity(_ id: String?) -> Int {
            guard let id else { return 0 }
            return inventory.first { $0.itemID == id }?.quantity ?? 0
        }
        func fits(_ id: String?, _ slot: EquipSlot) -> Bool {
            guard let id, quantity(id) > 0, let gear = gear(id, catalog: catalog) else { return false }
            return gear.allowedSlots.contains(slot)
        }
        var clean = self
        if !fits(armourID, .armour) { clean.armourID = nil }
        if !fits(shieldID, .shield) { clean.shieldID = nil }
        if !fits(mainHandID, .mainHand) { clean.mainHandID = nil }
        if !fits(offHandID, .offHand) { clean.offHandID = nil }
        if let main = clean.mainHandID, main == clean.offHandID, quantity(main) < 2 { clean.offHandID = nil }
        if clean.mainWeaponNeedsBothHands(catalog: catalog) {
            clean.shieldID = nil
            clean.offHandID = nil
        }
        if clean.shieldID != nil { clean.offHandID = nil }
        if clean.usesBothHands {
            let versatile = clean.mainHandID.flatMap { clean.gear($0, catalog: catalog) }?.isVersatile ?? false
            if !versatile || clean.shieldID != nil || clean.offHandID != nil { clean.usesBothHands = false }
        }
        clean.attunedIDs = Array(clean.attunedIDs.filter { id in
            quantity(id) > 0 && (catalog.item(id: id)?.requiresAttunement ?? false)
        }.prefix(Self.maxAttuned))
        clean.baseItemIDs = clean.baseItemIDs.filter { quantity($0.key) > 0 }
        return clean
    }

    /// True when the main-hand weapon is two-handed, or versatile and used with both hands.
    func mainWeaponNeedsBothHands(catalog: ItemCatalog) -> Bool {
        guard let main = mainHandID, let gear = gear(main, catalog: catalog) else { return false }
        return gear.isTwoHanded || (usesBothHands && gear.isVersatile)
    }
}
