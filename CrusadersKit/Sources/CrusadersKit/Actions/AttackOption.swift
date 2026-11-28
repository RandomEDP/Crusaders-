import Foundation

/// An attack the player can tap to roll: a held weapon, an unarmed strike, or an attack printed on
/// an imported sheet (D&D Beyond).
public struct AttackOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Added to the d20. Nil for attacks that force a saving throw instead (see `saveText`).
    public let attackBonus: Int?
    /// e.g. "DC 12" when the target makes a save instead of being rolled against.
    public let saveText: String?
    public let damage: DamageDice?
    /// e.g. "piercing"
    public let damageType: String?
    /// What each attack uses up, for bows, crossbows, slings and blowguns.
    public let ammunition: AmmoKind?
    public let notes: [String]

    public init(id: String, name: String, attackBonus: Int?, saveText: String? = nil, damage: DamageDice?,
                damageType: String?, ammunition: AmmoKind? = nil, notes: [String] = []) {
        self.id = id
        self.name = name
        self.attackBonus = attackBonus
        self.saveText = saveText
        self.damage = damage
        self.damageType = damageType
        self.ammunition = ammunition
        self.notes = notes
    }

    /// A held weapon or unarmed strike worked out by the character sheet.
    public init(_ attack: WeaponAttack) {
        self.init(id: "weapon-\(attack.id)", name: attack.name, attackBonus: attack.attackBonus,
                  damage: attack.damageDice, damageType: attack.damageType == .none ? nil : attack.damageType.rawValue,
                  ammunition: attack.ammunition, notes: attack.notes)
    }

    /// An attack as printed on an imported sheet. Bows and crossbows there use ammunition too.
    public init(imported attack: ImportedSheet.AttackEntry, index: Int) {
        self.init(id: "imported-\(index)-\(attack.name)", name: attack.name, attackBonus: attack.attackBonus,
                  saveText: attack.saveText, damage: attack.damage.flatMap(DamageDice.init),
                  damageType: attack.damageType?.lowercased(), ammunition: AmmoKind.fired(byWeaponNamed: attack.name),
                  notes: attack.notes.map { [$0] } ?? [])
    }

    /// Rolls to hit (unless the attack forces a save) and damage. A natural 20 doubles the damage dice;
    /// a natural 1 misses, so no damage is rolled. `extraBonus` comes from magic ammunition.
    public func roll(mode: RollMode = .normal, extraBonus: Int = 0, using roller: DiceRoller) -> AttackResult {
        let toHit = attackBonus.map { D20Roll.roll(bonus: $0 + extraBonus, mode: mode, using: roller) }
        var damageRoll: RolledDice?
        if let damage, !(toHit?.isFumble ?? false) {
            let dice = damage.addingBonus(extraBonus)
            damageRoll = ((toHit?.isCritical ?? false) ? dice.doubled : dice).roll(using: roller)
        }
        return AttackResult(attack: self, toHit: toHit, damage: damageRoll)
    }
}

/// What happened when an attack was rolled.
public struct AttackResult: Hashable, Sendable {
    public let attack: AttackOption
    public let toHit: D20Roll?
    public let damage: RolledDice?

    public init(attack: AttackOption, toHit: D20Roll?, damage: RolledDice?) {
        self.attack = attack
        self.toHit = toHit
        self.damage = damage
    }

    /// The message posted in the party chat, e.g.
    /// "⚔️ Thirke attacks with Longbow\nTo hit: 17 (d20: 14 + 3)\nDamage: 7 piercing (1d8: [4] + 3)\nArrows: 19 left".
    public func chatText(characterName: String, ammoName: String? = nil, ammoLeft: Int? = nil) -> String {
        var lines = ["⚔️ \(characterName) attacks with \(attack.name)"]
        if let toHit {
            var line = "To hit: \(toHit.breakdown)"
            if toHit.isCritical { line += ". Critical hit!" }
            if toHit.isFumble { line += ". Natural 1: a miss." }
            lines.append(line)
        } else if let save = attack.saveText {
            lines.append("Save: \(save)")
        }
        if let damage {
            let type = attack.damageType.map { " \($0)" } ?? ""
            lines.append("Damage: \(damage.total)\(type) (\(damage.breakdown))")
        }
        if let ammoName, let ammoLeft {
            lines.append("\(ammoName): \(ammoLeft) left")
        }
        return lines.joined(separator: "\n")
    }
}

extension CharacterSheet {
    /// Every attack the character can tap to roll: held weapons for characters made here, or the
    /// attacks printed on the sheet for imported ones.
    public var attackOptions: [AttackOption] {
        if let imported = character.importedSheet, !imported.attacks.isEmpty {
            // The printed numbers already include the other app's feats and items.
            return imported.attacks.enumerated().map { AttackOption(imported: $0.element, index: $0.offset) }
        }
        return attacks.map(AttackOption.init)
    }
}
