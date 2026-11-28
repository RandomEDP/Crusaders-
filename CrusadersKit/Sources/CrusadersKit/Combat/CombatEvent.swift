import Foundation

/// Changes an active effect makes to the character sheet while it lasts.
public struct EffectModifiers: Codable, Hashable, Sendable {
    /// Added to Armor Class (Haste: +2).
    public var armorClassBonus: Int
    /// Walking speed is multiplied by this (Haste: 2).
    public var speedMultiplier: Int
    /// Strength becomes this, unless it's already higher (Potion of Giant Strength).
    public var strengthScore: Int?
    /// Dice added to attack rolls and saving throws, e.g. "1d4" (Bless from Heroism).
    public var attackAndSaveDice: String?
    /// Dice added to (or, starting with "-", taken from) weapon damage, e.g. "1d4" (Enlarge) or "-1d4" (Reduce).
    public var weaponDamageDice: String?
    /// Gains a flying speed equal to walking speed.
    public var flies: Bool
    /// Gains a climbing speed equal to walking speed.
    public var climbs: Bool
    /// Anything else, shown on the sheet, e.g. "Advantage on Dexterity saving throws".
    public var notes: [String]

    public init(armorClassBonus: Int = 0, speedMultiplier: Int = 1, strengthScore: Int? = nil,
                attackAndSaveDice: String? = nil, weaponDamageDice: String? = nil,
                flies: Bool = false, climbs: Bool = false, notes: [String] = []) {
        self.armorClassBonus = armorClassBonus
        self.speedMultiplier = speedMultiplier
        self.strengthScore = strengthScore
        self.attackAndSaveDice = attackAndSaveDice
        self.weaponDamageDice = weaponDamageDice
        self.flies = flies
        self.climbs = climbs
        self.notes = notes
    }
}

/// A boost or condition that lasts a number of combat rounds (1 round = 6 seconds, 1 minute = 10 rounds).
public struct ActiveEffect: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// e.g. "Potion of Speed"
    public var name: String
    /// The round it started in.
    public var startRound: Int
    public var durationRounds: Int
    public var modifiers: EffectModifiers

    public init(id: UUID = UUID(), name: String, startRound: Int, durationRounds: Int, modifiers: EffectModifiers) {
        self.id = id
        self.name = name
        self.startRound = startRound
        self.durationRounds = durationRounds
        self.modifiers = modifiers
    }

    /// Everything it does, for the sheet, e.g. ["Strength 21"], ["+2 AC", "Speed doubled", …].
    public var summary: [String] {
        var lines: [String] = []
        let m = modifiers
        if let strength = m.strengthScore { lines.append("Strength \(strength)") }
        if m.armorClassBonus != 0 { lines.append("\(m.armorClassBonus > 0 ? "+" : "")\(m.armorClassBonus) AC") }
        if m.speedMultiplier > 1 { lines.append(m.speedMultiplier == 2 ? "Speed doubled" : "Speed ×\(m.speedMultiplier)") }
        if m.flies { lines.append("Flying speed equal to walking speed") }
        if m.climbs { lines.append("Climbing speed equal to walking speed") }
        if let dice = m.weaponDamageDice {
            lines.append(dice.hasPrefix("-") ? "−\(dice.dropFirst()) weapon damage" : "+\(dice) weapon damage")
        }
        return lines + m.notes
    }

    /// Rounds left once the campaign is at `round`. 0 or less means it has worn off.
    public func roundsLeft(atRound round: Int) -> Int {
        startRound + durationRounds - round
    }

    /// e.g. "8 rounds left", "59 min left", "2 h left"
    public static func timeLeftText(_ rounds: Int) -> String {
        if rounds >= 600 {
            let hours = Double(rounds) / 600
            return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) h left"
        }
        if rounds >= 20 { return "\(rounds / 10) min left" }
        return rounds == 1 ? "1 round left" : "\(rounds) rounds left"
    }
}

/// Something that happened to a character in play: damage, healing, temporary hit points, an effect starting
/// or ending, the DM moving the campaign on a number of rounds, or the player's phone reporting the character's
/// max hit points and AC so the DM can see them. Each is its own record, written by whoever did it.
public struct CombatEvent: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case damage(amount: Int, type: DamageType)
        case healing(amount: Int)
        /// Temporary hit points don't stack: the higher of the old and new amount is kept.
        case temporaryHitPoints(amount: Int)
        case effectStarted(ActiveEffect)
        case effectEnded(effectID: UUID)
        /// The DM moves the whole campaign on (playerID is empty).
        case roundsAdvanced(count: Int)
        /// Restores all hit points and ends every effect (playerID's character).
        case longRest
        /// From the player's phone, so the DM sees max HP and AC.
        case statusReport(maxHitPoints: Int, armorClass: Int)
    }

    public let id: UUID
    /// The player whose character it happened to. Empty for `roundsAdvanced`.
    public var playerID: String
    public var kind: Kind
    public var authorID: String
    public var date: Date
    /// Shown in the log, e.g. "Potion of Healing: regained 7 HP (2d4 + 2)".
    public var note: String?

    public init(id: UUID = UUID(), playerID: String, kind: Kind, authorID: String, date: Date = Date(), note: String? = nil) {
        self.id = id
        self.playerID = playerID
        self.kind = kind
        self.authorID = authorID
        self.date = date
        self.note = note
    }
}

/// A character's hit points right now.
public struct HealthState: Hashable, Sendable {
    public var current: Int
    public var maximum: Int
    public var temporary: Int

    public init(current: Int, maximum: Int, temporary: Int = 0) {
        self.current = current
        self.maximum = maximum
        self.temporary = temporary
    }

    public var isDown: Bool { current <= 0 }

    /// e.g. "15 / 22 HP + 5 temp"
    public var text: String {
        temporary > 0 ? "\(current) / \(maximum) HP + \(temporary) temp" : "\(current) / \(maximum) HP"
    }
}

/// One character's combat situation in a campaign: the round, their events, and what's active.
public struct CombatState: Hashable, Sendable {
    /// The campaign's current round (starts at 0).
    public var round: Int
    /// This character's allowed events, oldest first.
    public var events: [CombatEvent]

    public init(round: Int = 0, events: [CombatEvent] = []) {
        self.round = round
        self.events = events
    }

    public static let none = CombatState()

    /// Effects that have started, not ended, and not worn off.
    public var activeEffects: [ActiveEffect] {
        var effects: [ActiveEffect] = []
        for event in events {
            switch event.kind {
            case .effectStarted(let effect): effects.append(effect)
            case .effectEnded(let id): effects.removeAll { $0.id == id }
            case .longRest: effects.removeAll()
            default: break
            }
        }
        return effects.filter { $0.roundsLeft(atRound: round) > 0 }
    }

    /// Hit points after every event, starting from full. Damage takes temporary hit points first;
    /// healing never goes above the maximum and never below 0 to start with.
    public func health(maxHitPoints: Int) -> HealthState {
        var state = HealthState(current: maxHitPoints, maximum: maxHitPoints)
        for event in events {
            switch event.kind {
            case .damage(let amount, _):
                let absorbed = min(state.temporary, max(0, amount))
                state.temporary -= absorbed
                state.current = max(0, state.current - (max(0, amount) - absorbed))
            case .healing(let amount):
                state.current = min(maxHitPoints, state.current + max(0, amount))
            case .temporaryHitPoints(let amount):
                state.temporary = max(state.temporary, amount)
            case .longRest:
                state.current = maxHitPoints
                state.temporary = 0
            default:
                break
            }
        }
        return state
    }

    /// The latest max HP and AC the player's phone reported, for the DM's screen.
    public var lastReport: (maxHitPoints: Int, armorClass: Int)? {
        for event in events.reversed() {
            if case let .statusReport(maxHitPoints, armorClass) = event.kind { return (maxHitPoints, armorClass) }
        }
        return nil
    }

    /// Damage and healing totals, for when no max HP has been reported yet.
    public var netDamage: Int {
        health(maxHitPoints: 10_000).maximum - health(maxHitPoints: 10_000).current
    }
}

public enum CombatError: Error, Equatable, Sendable {
    case invalidAmount
    /// Only the DM moves rounds on, deals damage to others, or gives healing and temporary hit points.
    case onlyDungeonMaster
    case notYourCharacter
    /// That item has no effect the app knows how to apply.
    case cantUseItem
}
