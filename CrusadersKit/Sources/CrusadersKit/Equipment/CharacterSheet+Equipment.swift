import Foundation

/// Armor Class, attacks and armour effects from equipped items (5e SRD 5.1 rules).
extension CharacterSheet {
    // MARK: Armor Class

    /// AC from body armour (or unarmoured), plus a shield, plus magic bonuses.
    public var armorClass: Int {
        armorClassParts.reduce(0) { $0 + $1.value }
    }

    /// What makes up the AC, e.g. [("Chain Mail", 16), ("Shield", 2)], for showing under the number.
    public var armorClassParts: [(name: String, value: Int)] {
        var parts: [(name: String, value: Int)] = []
        let dex = modifier(.dex)
        if let armour = gear.armour, let stats = armour.armour {
            parts.append((armour.name, stats.armorClass(dexterityModifier: dex) + armour.armorClassBonus))
        } else {
            parts.append(unarmouredDefense)
        }
        if let shield = gear.shield, let stats = shield.shield {
            parts.append((shield.name, stats.baseArmorClass + shield.armorClassBonus))
        }
        for effect in combat.activeEffects where effect.modifiers.armorClassBonus != 0 {
            parts.append((effect.name, effect.modifiers.armorClassBonus))
        }
        return parts
    }

    /// The best AC with no body armour: 10 + Dex, or a class's Unarmored Defense.
    var unarmouredDefense: (name: String, value: Int) {
        let dex = modifier(.dex)
        var best: (name: String, value: Int) = ("Unarmoured (10 + Dex)", 10 + dex)
        switch characterClass?.id {
        case "barbarian":
            let value = 10 + dex + modifier(.con)
            if value > best.value { best = ("Unarmored Defense (10 + Dex + Con)", value) }
        case "monk" where gear.shield == nil:
            let value = 10 + dex + modifier(.wis)
            if value > best.value { best = ("Unarmored Defense (10 + Dex + Wis)", value) }
        case "sorcerer" where hasSubclass && characterClass?.subclass.id == "draconic":
            let value = 13 + dex
            if value > best.value { best = ("Draconic Resilience (13 + Dex)", value) }
        default:
            break
        }
        return best
    }

    // MARK: Armour effects

    /// 10 feet when wearing heavy armour without its Strength requirement. Dwarves aren't slowed by heavy armour.
    public var armourSpeedPenalty: Int {
        guard let stats = gear.armour?.armour, let needed = stats.strengthRequirement,
              abilityScores[.str] < needed, race?.id != "dwarf" else { return 0 }
        return 10
    }

    /// Disadvantage on Dexterity (Stealth) checks from the armour worn.
    public var hasStealthDisadvantage: Bool {
        gear.armour?.armour?.stealthDisadvantage ?? false
    }

    /// Whether the character is proficient with this kind of armour. Characters without a class count as proficient.
    public func isProficient(withArmour kind: ArmourKind) -> Bool {
        guard let characterClass else { return true }
        let proficiencies = Set(characterClass.proficiencies.map { $0.lowercased() })
        switch kind {
        case .shield: return proficiencies.contains("shields")
        case .light, .medium, .heavy:
            return proficiencies.contains("all armor") || proficiencies.contains("\(kind.rawValue) armor")
        }
    }

    /// Worn armour or a shield the character isn't trained with.
    public var unproficientArmour: [GearItem] {
        [gear.armour, gear.shield].compactMap { $0 }.filter { worn in
            guard let kind = worn.armour?.kind, !worn.traits.alwaysProficient else { return false }
            return !isProficient(withArmour: kind)
        }
    }

    /// Problems with what's worn, for the sheet to show.
    public var equipmentWarnings: [String] {
        var warnings: [String] = []
        for item in unproficientArmour {
            warnings.append("Not proficient with \(item.name): disadvantage on Strength and Dexterity checks, saving throws and attack rolls, and you can't cast spells.")
        }
        if armourSpeedPenalty > 0, let worn = gear.armour, let needed = worn.armour?.strengthRequirement {
            warnings.append("\(worn.name) needs Strength \(needed): speed is \(armourSpeedPenalty) feet slower.")
        }
        for held in gear.equipped.map(\.gear) where held.item.requiresAttunement && !held.isAttuned {
            warnings.append("Attune to \(held.name) to use its magic.")
        }
        return warnings
    }

    var gearHitPointsPerLevel: Int {
        gear.attuned.reduce(0) { $0 + $1.hitPointsPerLevel }
    }

    var gearSavingThrowBonus: Int {
        gear.activeItems.reduce(0) { $0 + $1.savingThrowBonus }
    }

    // MARK: Weapons

    /// Whether the character is proficient with a weapon, from their class and race.
    /// Characters without a class count as proficient.
    public func isProficient(withWeapon gear: GearItem) -> Bool {
        guard let characterClass else { return true }
        let proficiencies = Set(characterClass.proficiencies.map { $0.lowercased() })
        let group = gear.group.lowercased()
        if group.hasPrefix("simple") && proficiencies.contains("simple weapons") { return true }
        if group.hasPrefix("martial") && proficiencies.contains("martial weapons") { return true }
        let base = gear.proficiencyItem
        if proficiencies.contains(Self.proficiencyName(for: base)) { return true }
        return racialWeaponIDs.contains(base.id)
    }

    /// Class proficiency lists name weapons in the plural, e.g. "Longswords", "Crossbows, light".
    static func proficiencyName(for item: EquipmentItem) -> String {
        switch item.id {
        case "light-crossbow": return "crossbows, light"
        case "hand-crossbow": return "hand crossbows"
        default: return item.name.lowercased() + "s"
        }
    }

    /// Dwarven Combat Training and Elf Weapon Training.
    var racialWeaponIDs: Set<String> {
        var ids: Set<String> = []
        if race?.id == "dwarf" { ids.formUnion(["battleaxe", "handaxe", "light-hammer", "warhammer"]) }
        if subrace?.id == "high-elf" { ids.formUnion(["longsword", "shortsword", "shortbow", "longbow"]) }
        return ids
    }

    /// Attacks with held weapons, main hand first. An unarmed strike when the main hand is empty.
    public var attacks: [WeaponAttack] {
        var list: [WeaponAttack] = []
        if let main = gear.mainHand, main.weapon != nil {
            list.append(attack(with: main, hand: .mainHand))
        }
        if let off = gear.offHand, off.weapon != nil, !(off.id == gear.mainHand?.id && gear.usesBothHands) {
            list.append(attack(with: off, hand: .offHand))
        }
        if gear.mainHand == nil {
            let strength = modifier(.str)
            list.append(WeaponAttack(
                name: "Unarmed strike", hand: nil,
                attackBonus: strength + proficiencyBonus,
                damage: Self.damageText(dice: "1", modifier: strength, type: .bludgeoning),
                notes: armourDisadvantageNotes + effectAttackNotes
            ))
        }
        return list
    }

    private var armourDisadvantageNotes: [String] {
        unproficientArmour.isEmpty ? [] : ["Disadvantage: armour you aren't proficient with"]
    }

    func attack(with weaponItem: GearItem, hand: EquipSlot) -> WeaponAttack {
        let gear = weaponItem
        guard let weapon = gear.weapon else {
            return WeaponAttack(name: gear.name, hand: hand, attackBonus: 0, damage: "No damage", notes: [])
        }
        let isRanged = gear.group.lowercased().contains("ranged")
        let strength = modifier(.str)
        let dexterity = modifier(.dex)
        let abilityModifier: Int
        if weapon.properties.contains(.finesse) {
            abilityModifier = max(strength, dexterity)
        } else {
            abilityModifier = isRanged ? dexterity : strength
        }
        let proficient = isProficient(withWeapon: gear)
        let attackBonus = abilityModifier + (proficient ? proficiencyBonus : 0) + gear.attackBonus

        let bothHands = hand == .mainHand && self.gear.usesBothHands && gear.isVersatile
        let dice = bothHands ? (weapon.versatileDamage ?? weapon.damage) : weapon.damage
        // Off-hand attacks (two-weapon fighting) don't add a positive ability modifier to damage.
        let damageAbility = hand == .offHand ? min(0, abilityModifier) : abilityModifier
        let damage = weapon.damage == "0" || weapon.damageType == .none
            ? "No damage"
            : Self.damageText(dice: dice, modifier: damageAbility + gear.attackBonus, type: weapon.damageType)

        var notes: [String] = []
        if gear.isTwoHanded { notes.append("Two-handed") }
        if bothHands { notes.append("Versatile: using both hands") }
        if hand == .offHand {
            let mainIsLight = self.gear.mainHand?.isLight ?? false
            notes.append(mainIsLight && gear.isLight
                         ? "Bonus action attack (two-weapon fighting)"
                         : "Two-weapon fighting needs light weapons in both hands")
        }
        if let normal = weapon.normalRange, let long = weapon.longRange {
            notes.append("Range \(normal)/\(long) ft")
        }
        if weapon.properties.contains(.reach) { notes.append("Reach") }
        if weapon.properties.contains(.heavy) && race?.size == "Small" {
            notes.append("Disadvantage: heavy weapon for a Small creature")
        }
        if !proficient { notes.append("Not proficient: no proficiency bonus") }
        notes += effectAttackNotes
        notes += armourDisadvantageNotes
        if gear.item.requiresAttunement && !gear.isAttuned {
            notes.append("Not attuned: no magic")
        } else if let note = gear.traits.attackNote {
            notes.append(note)
        }
        return WeaponAttack(name: gear.name, hand: hand, attackBonus: attackBonus, damage: damage, notes: notes)
    }

    /// "1d8 + 3 slashing", "1d4 − 1 piercing", "2d6 slashing".
    static func damageText(dice: String, modifier: Int, type: DamageType) -> String {
        let bonus: String
        switch modifier {
        case 0: bonus = ""
        case let value where value > 0: bonus = " + \(value)"
        default: bonus = " − \(-modifier)"
        }
        return "\(dice)\(bonus) \(type.rawValue)"
    }
}

extension GearItem {
    /// The shield stats, when this is a shield.
    var shield: ArmourStats? {
        guard let stats = armour, stats.kind == .shield else { return nil }
        return stats
    }
}
