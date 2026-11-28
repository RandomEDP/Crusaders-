import Foundation

/// Hit points and potion effects on the character sheet.
extension CharacterSheet {
    /// Current, max and temporary hit points after damage and healing in the campaign.
    public var health: HealthState {
        combat.health(maxHitPoints: maxHitPoints)
    }

    public var activeEffects: [ActiveEffect] { combat.activeEffects }

    /// Haste doubles speed.
    var effectSpeedMultiplier: Int {
        combat.activeEffects.map(\.modifiers.speedMultiplier).filter { $0 > 1 }.max() ?? 1
    }

    /// e.g. ["Fly 30 ft", "Climb 30 ft"]
    public var extraSpeeds: [String] {
        let effects = combat.activeEffects
        var speeds: [String] = []
        if effects.contains(where: \.modifiers.flies) { speeds.append("Fly \(speed) ft") }
        if effects.contains(where: \.modifiers.climbs) { speeds.append("Climb \(speed) ft") }
        return speeds
    }

    /// Extra dice on attack rolls and saving throws, e.g. "+1d4 (Potion of Heroism)".
    public var effectSaveNotes: [String] {
        combat.activeEffects.compactMap { effect in
            effect.modifiers.attackAndSaveDice.map { "+\($0) (\(effect.name))" }
        }
    }

    /// Notes added to every attack, e.g. "+1d4 to hit (Potion of Heroism)", "+1d4 damage (Potion of Growth)".
    var effectAttackNotes: [String] {
        combat.activeEffects.flatMap { effect -> [String] in
            var notes: [String] = []
            if let dice = effect.modifiers.attackAndSaveDice { notes.append("+\(dice) to hit (\(effect.name))") }
            if let dice = effect.modifiers.weaponDamageDice {
                notes.append(dice.hasPrefix("-") ? "−\(dice.dropFirst()) damage (\(effect.name))" : "+\(dice) damage (\(effect.name))")
            }
            return notes
        }
    }
}
