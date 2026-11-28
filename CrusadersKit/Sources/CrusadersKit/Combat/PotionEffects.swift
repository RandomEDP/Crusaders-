import Foundation

/// Dice like "2d4+2", "10d4 + 20", "3d6" or "1d4".
public struct DiceExpression: Hashable, Sendable {
    public let count: Int
    public let sides: Int
    public let bonus: Int

    public init(count: Int, sides: Int, bonus: Int = 0) {
        self.count = count
        self.sides = sides
        self.bonus = bonus
    }

    public init?(_ text: String) {
        let cleaned = text.replacingOccurrences(of: " ", with: "").lowercased()
        let parts = cleaned.split(separator: "d", maxSplits: 1).map(String.init)
        guard parts.count == 2, let count = Int(parts[0]), count > 0 else { return nil }
        var sidesText = parts[1]
        var bonus = 0
        if let sign = sidesText.firstIndex(where: { $0 == "+" || $0 == "-" }) {
            guard let value = Int(sidesText[sign...].replacingOccurrences(of: "+", with: "")) else { return nil }
            bonus = value
            sidesText = String(sidesText[..<sign])
        }
        guard let sides = Int(sidesText), sides > 0 else { return nil }
        self.init(count: count, sides: sides, bonus: bonus)
    }

    /// e.g. "2d4 + 2"
    public var text: String {
        switch bonus {
        case 0: return "\(count)d\(sides)"
        case let value where value > 0: return "\(count)d\(sides) + \(value)"
        default: return "\(count)d\(sides) − \(-bonus)"
        }
    }

    public func roll(using roller: DiceRoller) -> Int {
        roller.roll(count, d: sides).reduce(0, +) + bonus
    }
}

/// What drinking an SRD potion does, so pressing Use applies it.
public struct PotionEffect: Sendable {
    public enum Duration: Hashable, Sendable {
        case rounds(Int)
        /// Rolled when drunk, e.g. 1d4 hours for Growth: the dice give hours.
        case rolledHours(DiceExpression)
    }

    public var healing: DiceExpression?
    public var temporaryHitPoints: Int?
    public var damageDice: DiceExpression?
    public var damageType: DamageType
    /// An effect that lasts a while, named after the potion.
    public var modifiers: EffectModifiers?
    public var duration: Duration?

    public init(healing: DiceExpression? = nil, temporaryHitPoints: Int? = nil,
                damageDice: DiceExpression? = nil, damageType: DamageType = .none,
                modifiers: EffectModifiers? = nil, duration: Duration? = nil) {
        self.healing = healing
        self.temporaryHitPoints = temporaryHitPoints
        self.damageDice = damageDice
        self.damageType = damageType
        self.modifiers = modifiers
        self.duration = duration
    }

    /// Rolls the dice and makes the events drinking it causes, all at `date`, starting at `round`.
    public func events(itemName: String, playerID: String, authorID: String, round: Int,
                       roller: DiceRoller, date: Date = Date()) -> [CombatEvent] {
        var events: [CombatEvent] = []
        func add(_ kind: CombatEvent.Kind, _ note: String) {
            events.append(CombatEvent(playerID: playerID, kind: kind, authorID: authorID,
                                      date: date.addingTimeInterval(Double(events.count) * 0.001), note: note))
        }
        if let healing {
            let amount = max(0, healing.roll(using: roller))
            add(.healing(amount: amount), "\(itemName): regained \(amount) HP (\(healing.text))")
        }
        if let damageDice {
            let amount = max(0, damageDice.roll(using: roller))
            add(.damage(amount: amount, type: damageType), "\(itemName): took \(amount) \(damageType.rawValue) damage (\(damageDice.text))")
        }
        if let temporaryHitPoints {
            add(.temporaryHitPoints(amount: temporaryHitPoints), "\(itemName): \(temporaryHitPoints) temporary HP")
        }
        if let modifiers, let duration {
            let rounds: Int
            switch duration {
            case .rounds(let count): rounds = count
            case .rolledHours(let dice): rounds = max(1, dice.roll(using: roller)) * Self.hour
            }
            let effect = ActiveEffect(name: itemName, startRound: round, durationRounds: rounds, modifiers: modifiers)
            add(.effectStarted(effect), "\(itemName): \(ActiveEffect.timeLeftText(rounds).replacingOccurrences(of: " left", with: ""))")
        }
        return events
    }

    /// 1 minute = 10 rounds, 1 hour = 600 rounds.
    public static let minute = 10
    public static let hour = 600

    /// The SRD potions the app can apply, by item id.
    public static func srd(_ itemID: String) -> PotionEffect? {
        table[itemID]
    }

    private static func giantStrength(_ score: Int) -> PotionEffect {
        PotionEffect(modifiers: EffectModifiers(strengthScore: score), duration: .rounds(hour))
    }

    private static func lasting(_ minutes: Int, _ modifiers: EffectModifiers) -> PotionEffect {
        PotionEffect(modifiers: modifiers, duration: .rounds(minutes * minute))
    }

    static let table: [String: PotionEffect] = [
        "potion-of-healing": PotionEffect(healing: DiceExpression(count: 2, sides: 4, bonus: 2)),
        "potion-of-greater-healing": PotionEffect(healing: DiceExpression(count: 4, sides: 4, bonus: 4)),
        "potion-of-superior-healing": PotionEffect(healing: DiceExpression(count: 8, sides: 4, bonus: 8)),
        "potion-of-supreme-healing": PotionEffect(healing: DiceExpression(count: 10, sides: 4, bonus: 20)),
        "potion-of-hill-giant-strength": giantStrength(21),
        "potion-of-frost-giant-strength": giantStrength(23),
        "potion-of-stone-giant-strength": giantStrength(23),
        "potion-of-fire-giant-strength": giantStrength(25),
        "potion-of-cloud-giant-strength": giantStrength(27),
        "potion-of-storm-giant-strength": giantStrength(29),
        "potion-of-heroism": PotionEffect(
            temporaryHitPoints: 10,
            modifiers: EffectModifiers(attackAndSaveDice: "1d4", notes: ["Bless: +1d4 to attack rolls and saving throws"]),
            duration: .rounds(hour)
        ),
        "potion-of-speed": lasting(1, EffectModifiers(
            armorClassBonus: 2, speedMultiplier: 2,
            notes: ["Haste: advantage on Dexterity saving throws", "One extra action each turn (Attack, Dash, Disengage, Hide or Use an Object)"]
        )),
        "potion-of-growth": PotionEffect(
            modifiers: EffectModifiers(weaponDamageDice: "1d4",
                                       notes: ["Enlarged: size one bigger, advantage on Strength checks and saving throws"]),
            duration: .rolledHours(DiceExpression(count: 1, sides: 4))
        ),
        "potion-of-diminution": PotionEffect(
            modifiers: EffectModifiers(weaponDamageDice: "-1d4",
                                       notes: ["Reduced: size one smaller, disadvantage on Strength checks and saving throws"]),
            duration: .rolledHours(DiceExpression(count: 1, sides: 4))
        ),
        "potion-of-flying": lasting(60, EffectModifiers(flies: true, notes: ["You can hover"])),
        "potion-of-climbing": lasting(60, EffectModifiers(climbs: true, notes: ["Advantage on Strength (Athletics) checks to climb"])),
        "potion-of-invisibility": lasting(60, EffectModifiers(notes: ["Invisible until you attack or cast a spell"])),
        "potion-of-resistance": lasting(60, EffectModifiers(notes: ["Resistance to one damage type (set when it was made)"])),
        "potion-of-water-breathing": lasting(60, EffectModifiers(notes: ["You can breathe underwater"])),
        "potion-of-gaseous-form": lasting(60, EffectModifiers(notes: ["Gaseous form: fly 10 ft, resistance to nonmagical damage"])),
        "potion-of-animal-friendship": lasting(60, EffectModifiers(notes: ["Cast animal friendship at will (save DC 13)"])),
        "potion-of-clairvoyance": lasting(10, EffectModifiers(notes: ["Clairvoyance: see or hear a place you know within 1 mile"])),
        "potion-of-mind-reading": lasting(1, EffectModifiers(notes: ["Detect thoughts (save DC 13)"])),
        "potion-of-poison": PotionEffect(
            damageDice: DiceExpression(count: 3, sides: 6), damageType: .poison,
            modifiers: EffectModifiers(notes: ["Poisoned if you failed the DC 13 Constitution save: disadvantage on attack rolls and ability checks"]),
            duration: .rounds(hour)
        ),
    ]
}
