import Foundation

public enum ItemValidationError: Error, Equatable {
    case emptyName
    case emptyGroup
    case negativeCost
    case negativeWeight
    case invalidDamage(String)
    case invalidRange
    case armorClassOutOfRange
    case dexterityCapOutOfRange
    case strengthOutOfRange
}

extension ItemValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the item a name."
        case .emptyGroup: return "Give the item a sub-heading, such as Martial Melee."
        case .negativeCost: return "Cost can't be negative."
        case .negativeWeight: return "Weight can't be negative."
        case .invalidDamage(let text): return "\"\(text)\" isn't valid damage. Use dice like 1d8 or 2d6, or a number."
        case .invalidRange: return "Long range must be at least the normal range, and both must be above 0."
        case .armorClassOutOfRange: return "Armour Class must be between 0 and 30."
        case .dexterityCapOutOfRange: return "Max Dex bonus must be between 0 and 10."
        case .strengthOutOfRange: return "Strength requirement must be between 1 and 30."
        }
    }
}

public enum ItemValidator {
    /// Dice notation like "1d8", "2d6", "1d4 + 1", or a flat number like "1".
    public static func isValidDamage(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        return compact.range(of: #"^(\d{1,3}(d\d{1,3})?)([+-]\d{1,3})?$"#, options: .regularExpression) != nil
    }

    /// Tidies an edited item (trims text, drops empty optional values) and checks it makes sense.
    public static func validated(_ item: EquipmentItem) throws -> EquipmentItem {
        var item = item
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.group = item.group.trimmingCharacters(in: .whitespacesAndNewlines)
        item.description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !item.name.isEmpty else { throw ItemValidationError.emptyName }
        guard !item.group.isEmpty else { throw ItemValidationError.emptyGroup }
        if let cost = item.cost, cost.amount < 0 { throw ItemValidationError.negativeCost }
        if let weight = item.weight, weight < 0 { throw ItemValidationError.negativeWeight }

        if var weapon = item.weapon {
            weapon.damage = weapon.damage.trimmingCharacters(in: .whitespaces)
            guard isValidDamage(weapon.damage) else { throw ItemValidationError.invalidDamage(weapon.damage) }
            if let versatile = weapon.versatileDamage?.trimmingCharacters(in: .whitespaces) {
                if versatile.isEmpty {
                    weapon.versatileDamage = nil
                } else {
                    guard isValidDamage(versatile) else { throw ItemValidationError.invalidDamage(versatile) }
                    weapon.versatileDamage = versatile
                }
            }
            switch (weapon.normalRange, weapon.longRange) {
            case (nil, nil):
                break
            case let (normal?, long?):
                guard normal > 0, long >= normal else { throw ItemValidationError.invalidRange }
            default:
                throw ItemValidationError.invalidRange
            }
            item.weapon = weapon
        }

        if let armour = item.armour {
            guard (0...30).contains(armour.baseArmorClass) else { throw ItemValidationError.armorClassOutOfRange }
            if let cap = armour.maxDexterityBonus, !(0...10).contains(cap) { throw ItemValidationError.dexterityCapOutOfRange }
            if let strength = armour.strengthRequirement, !(1...30).contains(strength) { throw ItemValidationError.strengthOutOfRange }
        }
        return item
    }
}
