import Foundation

/// What a ranged weapon fires (5e SRD 5.1 Ammunition property): bows fire arrows, crossbows bolts,
/// slings bullets and blowguns needles. Each shot uses one piece from the inventory.
public enum AmmoKind: String, Codable, CaseIterable, Hashable, Sendable {
    case arrow, bolt, bullet, needle

    /// e.g. "arrows"
    public var plural: String {
        switch self {
        case .arrow: return "arrows"
        case .bolt: return "crossbow bolts"
        case .bullet: return "sling bullets"
        case .needle: return "blowgun needles"
        }
    }

    /// The ammunition a weapon needs, from its name or id: "Longbow" → arrows, "Light Crossbow" → bolts.
    /// Nil for weapons that don't fire anything.
    public static func fired(byWeaponNamed name: String) -> AmmoKind? {
        let lower = name.lowercased()
        if lower.contains("crossbow") { return .bolt }
        if lower.contains("longbow") || lower.contains("shortbow")
            || lower.range(of: #"\bbow\b"#, options: .regularExpression) != nil { return .arrow }
        if lower.contains("sling") { return .bullet }
        if lower.contains("blowgun") { return .needle }
        return nil
    }

    /// The ammunition a held weapon needs. Only weapons with the Ammunition property fire anything.
    public static func fired(by gear: GearItem) -> AmmoKind? {
        guard let weapon = gear.weapon, weapon.properties.contains(.ammunition) else { return nil }
        return fired(byWeaponNamed: gear.proficiencyItem.id) ?? fired(byWeaponNamed: gear.proficiencyItem.name)
            ?? fired(byWeaponNamed: gear.name)
    }

    /// What kind an inventory item is: "Arrows" → arrow, "Crossbow Bolts" → bolt. Nil for anything else,
    /// and for ammunition that fits every weapon ("Ammunition, +1"; see `fitsEveryWeapon`).
    public static func of(itemNamed name: String) -> AmmoKind? {
        let lower = name.lowercased()
        if lower.contains("bolt") { return .bolt }
        if lower.contains("arrow") { return .arrow }
        if lower.contains("bullet") { return .bullet }
        if lower.contains("needle") { return .needle }
        return nil
    }

    /// Magic ammunition such as "Ammunition, +1" that works with any weapon.
    public static func fitsEveryWeapon(itemNamed name: String) -> Bool {
        name.lowercased().hasPrefix("ammunition")
    }
}

/// One stack of ammunition in a character's inventory that a weapon can fire.
public struct AmmoStack: Identifiable, Hashable, Sendable {
    public let itemID: String
    public let name: String
    public let quantity: Int
    /// +1, +2 or +3 to attack and damage rolls for magic ammunition.
    public let bonus: Int

    public var id: String { itemID }

    public init(itemID: String, name: String, quantity: Int, bonus: Int = 0) {
        self.itemID = itemID
        self.name = name
        self.quantity = quantity
        self.bonus = bonus
    }

    /// The ammunition in an inventory that fits a weapon, ordinary ammunition first.
    /// Items the catalog knows must be in its Ammunition category, so an "Arrow-Catching Shield" never counts.
    public static func stacks(for kind: AmmoKind, in inventory: [InventoryEntry], catalog: ItemCatalog) -> [AmmoStack] {
        let fitting = inventory.compactMap { entry -> AmmoStack? in
            guard entry.quantity > 0 else { return nil }
            if let item = catalog.item(id: entry.itemID), item.category != .ammunition { return nil }
            let fits = AmmoKind.of(itemNamed: entry.name) == kind || AmmoKind.fitsEveryWeapon(itemNamed: entry.name)
            guard fits else { return nil }
            return AmmoStack(itemID: entry.itemID, name: entry.name, quantity: entry.quantity,
                             bonus: magicBonus(itemID: entry.itemID, name: entry.name))
        }
        return fitting.sorted { ($0.bonus, $0.name) < ($1.bonus, $1.name) }
    }

    /// "+2" in "Ammunition, +2", or the SRD ids ammunition-plus-1 to -3.
    static func magicBonus(itemID: String, name: String) -> Int {
        for value in [3, 2, 1] where itemID.hasSuffix("-plus-\(value)") || name.contains("+\(value)") {
            return value
        }
        return 0
    }
}

extension EquipmentItem {
    /// How many pieces one of this item holds, e.g. 20 for "Arrows (20)". Nil for anything that isn't ammunition.
    public var ammunitionBundleSize: Int? {
        guard category == .ammunition,
              let regex = try? NSRegularExpression(pattern: #"\((\d+)\)\s*$"#),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name),
              let size = Int(name[range]), size > 1 else { return nil }
        return size
    }

    /// What one piece is called in an inventory: "Arrows" for "Arrows (20)".
    public var inventoryName: String {
        guard ammunitionBundleSize != nil, let open = name.lastIndex(of: "(") else { return name }
        return name[..<open].trimmingCharacters(in: .whitespaces)
    }

    /// How many go into an inventory when the DM gives `quantity` of this item: bundles of ammunition are
    /// counted as single pieces (one "Arrows (20)" is 20 arrows), so each shot can use one.
    public func inventoryQuantity(for quantity: Int) -> Int {
        quantity * (ammunitionBundleSize ?? 1)
    }
}
