import Foundation

/// The dice in a spell's rules text, read so casting it can roll for the player:
/// "Make a ranged spell attack… takes 1d10 fire damage", "must make a Dexterity saving throw… 8d6 fire damage",
/// "regains hit points equal to 1d8 + your spellcasting ability modifier".
public struct SpellDice: Hashable, Sendable {
    public enum AttackKind: String, Hashable, Sendable { case melee, ranged }

    public var attack: AttackKind?
    /// The ability the target saves with.
    public var save: Ability?
    public var damage: DamageDice?
    /// e.g. "fire"
    public var damageType: String?
    public var healing: DamageDice?
    /// "+ your spellcasting ability modifier" on healing.
    public var healingAddsModifier: Bool
    /// Cantrips that grow at character levels 5, 11 and 17 (Fire Bolt: 1d10, 2d10, 3d10, 4d10).
    public var cantripScales: Bool
    /// Extra dice for each slot level above the spell's own ("increases by 1d6 for each slot level above 3rd").
    public var perSlotAbove: DamageDice?

    public init(attack: AttackKind? = nil, save: Ability? = nil, damage: DamageDice? = nil, damageType: String? = nil,
                healing: DamageDice? = nil, healingAddsModifier: Bool = false, cantripScales: Bool = false,
                perSlotAbove: DamageDice? = nil) {
        self.attack = attack
        self.save = save
        self.damage = damage
        self.damageType = damageType
        self.healing = healing
        self.healingAddsModifier = healingAddsModifier
        self.cantripScales = cantripScales
        self.perSlotAbove = perSlotAbove
    }

    /// Nothing to roll: utility spells such as Mage Armor.
    public var isEmpty: Bool { attack == nil && save == nil && damage == nil && healing == nil }

    /// Reads the dice out of an SRD spell's text.
    public init(spell: Spell) {
        let text = spell.description
        let lower = text.lowercased()
        self.init()
        if lower.contains("ranged spell attack") {
            attack = .ranged
        } else if lower.contains("melee spell attack") {
            attack = .melee
        }
        // The first saving throw the text names.
        save = Ability.allCases
            .compactMap { ability in lower.range(of: "\(ability.name.lowercased()) saving throw").map { (ability, $0.lowerBound) } }
            .min { $0.1 < $1.1 }?.0
        if let match = Self.firstMatch(#"(\d+d\d+(?:\s*\+\s*\d+)?) (\w+) damage"#, in: text),
           DamageType(rawValue: match[2].lowercased()) != nil {
            damage = DamageDice(match[1])
            damageType = match[2].lowercased()
        }
        if let match = Self.firstMatch(#"regains? (?:a number of )?hit points equal to (\d+d\d+(?:\s*\+\s*\d+)?)( \+ your spellcasting ability modifier)?"#, in: text) {
            healing = DamageDice(match[1])
            healingAddsModifier = !match[2].isEmpty
        }
        cantripScales = spell.isCantrip && damage != nil && lower.contains("when you reach 5th level")
        if let higher = spell.higherLevel,
           let match = Self.firstMatch(#"(?:damage|healing) increases by (\d+d\d+) for each slot level above"#, in: higher) {
            perSlotAbove = DamageDice(match[1])
        }
    }

    /// Capture groups of the first match, with "" for groups that didn't take part.
    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// A spell ready to cast: what to roll, worked out for the caster and the slot used.
public struct SpellCast: Hashable, Sendable {
    public let name: String
    /// 0 for cantrips.
    public let spellLevel: Int
    /// The slot spent, nil for cantrips.
    public let slotLevel: Int?
    public let attackBonus: Int?
    /// e.g. "DC 13 Dexterity save"
    public let saveText: String?
    public let damage: DamageDice?
    public let damageType: String?
    public let healing: DamageDice?

    public init(name: String, spellLevel: Int, slotLevel: Int?, attackBonus: Int? = nil, saveText: String? = nil,
                damage: DamageDice? = nil, damageType: String? = nil, healing: DamageDice? = nil) {
        self.name = name
        self.spellLevel = spellLevel
        self.slotLevel = slotLevel
        self.attackBonus = attackBonus
        self.saveText = saveText
        self.damage = damage
        self.damageType = damageType
        self.healing = healing
    }

    /// An SRD spell cast by a character. `casterLevel` scales cantrips; a higher `slotLevel` adds upcast dice.
    public init(spell: Spell, dice: SpellDice? = nil, slotLevel: Int?, casterLevel: Int,
                attackBonus: Int?, saveDC: Int?, abilityModifier: Int) {
        let dice = dice ?? SpellDice(spell: spell)
        var damage = dice.damage
        var healing = dice.healing
        if dice.cantripScales {
            let tier = casterLevel >= 17 ? 4 : casterLevel >= 11 ? 3 : casterLevel >= 5 ? 2 : 1
            damage = damage?.multiplied(by: tier)
        }
        if let slotLevel, let extra = dice.perSlotAbove, slotLevel > spell.level {
            let steps = slotLevel - spell.level
            let added = extra.multiplied(by: steps)
            if dice.healing != nil, dice.damage == nil {
                healing = healing?.adding(added)
            } else {
                damage = damage?.adding(added)
            }
        }
        if dice.healingAddsModifier { healing = healing?.addingBonus(abilityModifier) }
        let saveText = dice.save.map { ability in
            saveDC.map { "DC \($0) \(ability.name) save" } ?? "\(ability.name) save"
        }
        self.init(name: spell.name, spellLevel: spell.level, slotLevel: spell.isCantrip ? nil : slotLevel,
                  attackBonus: dice.attack != nil ? attackBonus : nil, saveText: saveText,
                  damage: damage, damageType: dice.damageType, healing: healing)
    }

    public func roll(mode: RollMode = .normal, using roller: DiceRoller) -> SpellCastResult {
        let toHit = attackBonus.map { D20Roll.roll(bonus: $0, mode: mode, using: roller) }
        var damageRoll: RolledDice?
        if let damage, !(toHit?.isFumble ?? false) {
            damageRoll = ((toHit?.isCritical ?? false) ? damage.doubled : damage).roll(using: roller)
        }
        return SpellCastResult(cast: self, toHit: toHit, damage: damageRoll, healing: healing?.roll(using: roller))
    }
}

/// What happened when a spell was cast.
public struct SpellCastResult: Hashable, Sendable {
    public let cast: SpellCast
    public let toHit: D20Roll?
    public let damage: RolledDice?
    public let healing: RolledDice?

    /// The message posted in the party chat, e.g.
    /// "✨ Thirke casts Fireball (3rd-level slot, 1 left)\nSave: DC 13 Dexterity save\nDamage: 28 fire (8d6: [...])".
    public func chatText(characterName: String, slotsLeft: Int? = nil) -> String {
        var title = "✨ \(characterName) casts \(cast.name)"
        if let slot = cast.slotLevel {
            let left = slotsLeft.map { ", \($0) left" } ?? ""
            title += " (\(Spell.ordinal(slot))-level slot\(left))"
        }
        var lines = [title]
        if let toHit {
            var line = "Spell attack: \(toHit.breakdown)"
            if toHit.isCritical { line += ". Critical hit!" }
            if toHit.isFumble { line += ". Natural 1: a miss." }
            lines.append(line)
        }
        if let save = cast.saveText { lines.append("Save: \(save)") }
        if let damage {
            let type = cast.damageType.map { " \($0)" } ?? ""
            lines.append("Damage: \(damage.total)\(type) (\(damage.breakdown))")
        }
        if let healing {
            lines.append("Healing: \(healing.total) HP (\(healing.breakdown))")
        }
        return lines.joined(separator: "\n")
    }
}

public enum ActionError: Error, Equatable, Sendable {
    /// No slots of this level (or higher, when choosing) are left.
    case noSpellSlot(level: Int)
    /// The weapon needs ammunition and there's none in the inventory.
    case noAmmunition(AmmoKind)
    /// The ability has no uses left until a rest.
    case noUsesLeft(name: String)
    /// Ammunition is kept in campaign inventories, so ranged weapons need the character to be in a campaign.
    case ammunitionNeedsCampaign
}

// MARK: Spell slots

/// A spell slot level and how many slots of it are left.
public struct SlotLevel: Hashable, Identifiable, Sendable {
    public let level: Int
    public let left: Int
    public var id: Int { level }

    public init(level: Int, left: Int) {
        self.level = level
        self.left = left
    }
}

extension PlayerCharacter {
    /// Slots spent at each spell level, 1st to 9th, since the last rest.
    public func spellSlotsUsed(atLevel level: Int) -> Int {
        guard (1...9).contains(level), level - 1 < spellSlotsUsed.count else { return 0 }
        return spellSlotsUsed[level - 1]
    }

    /// Spends a slot of this level. `maximum` is how many the character has at that level.
    public mutating func spendSpellSlot(level: Int, maximum: Int) throws {
        guard (1...9).contains(level), spellSlotsUsed(atLevel: level) < maximum else {
            throw ActionError.noSpellSlot(level: level)
        }
        while spellSlotsUsed.count < 9 { spellSlotsUsed.append(0) }
        spellSlotsUsed[level - 1] += 1
    }

    /// Gives back one slot of this level (for a mis-tap).
    public mutating func restoreSpellSlot(level: Int) {
        guard (1...9).contains(level), spellSlotsUsed(atLevel: level) > 0 else { return }
        spellSlotsUsed[level - 1] -= 1
    }

    /// Warlocks get their Pact Magic slots back on a short rest.
    public var usesPactMagic: Bool {
        if let imported = importedSheet, !imported.classes.isEmpty {
            return imported.classes.allSatisfy { $0.name.caseInsensitiveCompare("Warlock") == .orderedSame }
        }
        return classID == "warlock"
    }
}

extension CharacterSheet {
    /// Slots at each spell level, 1st to 9th, when fully rested: from the class table, or as printed on an imported sheet.
    public var spellSlotMaximums: [Int] {
        if let imported = character.importedSheet {
            return (1...9).map { imported.slots(atLevel: $0) }
        }
        let slots = spellSlots
        return (0..<9).map { $0 < slots.count ? slots[$0] : 0 }
    }

    public func spellSlotsLeft(atLevel level: Int) -> Int {
        guard (1...9).contains(level) else { return 0 }
        return max(0, spellSlotMaximums[level - 1] - character.spellSlotsUsed(atLevel: level))
    }

    /// Slot levels the character could cast a spell of this level with, lowest first, and how many each has left.
    public func castingLevels(forSpellLevel level: Int) -> [SlotLevel] {
        guard (1...9).contains(level) else { return [] }
        return (level...9).compactMap { slot in
            spellSlotMaximums[slot - 1] > 0 ? SlotLevel(level: slot, left: spellSlotsLeft(atLevel: slot)) : nil
        }
    }

    /// True when any slot level has slots.
    public var hasSpellSlots: Bool { spellSlotMaximums.contains { $0 > 0 } }

    /// Level used for cantrip damage: the character level (total level for an imported multiclass).
    public var casterLevel: Int {
        character.importedSheet.map { max(1, $0.totalLevel) } ?? level
    }

    /// Spell attack bonus, save DC and ability modifier, from the class or as printed on an imported sheet.
    public var spellcastingNumbers: (attackBonus: Int?, saveDC: Int?, abilityModifier: Int) {
        if let imported = character.importedSheet, let casting = imported.spellcasting.first {
            let modifier = casting.ability.flatMap { imported.ability($0)?.modifier } ?? 0
            return (casting.attackBonus, casting.saveDC, modifier)
        }
        return (spellAttackBonus, spellSaveDC, spellcastingAbility.map { modifier($0) } ?? 0)
    }

    /// Works out a cast of an SRD spell, using a slot of `slotLevel` for leveled spells.
    public func cast(_ spell: Spell, slotLevel: Int?) -> SpellCast {
        let numbers = spellcastingNumbers
        return SpellCast(spell: spell, slotLevel: spell.isCantrip ? nil : (slotLevel ?? spell.level),
                         casterLevel: casterLevel, attackBonus: numbers.attackBonus, saveDC: numbers.saveDC,
                         abilityModifier: numbers.abilityModifier)
    }

    /// A spell printed on an imported sheet with no SRD match: rolls to hit when the sheet gives a bonus ("+4")
    /// and shows the save it gives ("DEX 12").
    public func cast(imported spell: ImportedSheet.SpellEntry, slotLevel: Int?) -> SpellCast {
        let text = spell.saveOrAttack ?? ""
        let bonus = SpellDice.firstMatch(#"([+-]\d+)"#, in: text).flatMap { Int($0[1].replacingOccurrences(of: "+", with: "")) }
        let save = SpellDice.firstMatch(#"([A-Za-z]{3}) (\d+)"#, in: text).map { "DC \($0[2]) \($0[1].uppercased()) save" }
        return SpellCast(name: spell.name, spellLevel: spell.level, slotLevel: spell.level == 0 ? nil : (slotLevel ?? spell.level),
                         attackBonus: bonus, saveText: save)
    }
}
