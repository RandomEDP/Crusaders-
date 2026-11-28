import Foundation

/// Dice plus a flat bonus, such as "1d8 + 3", "2d6", "1d4-1", "1d8 + 1d6 + 2" or a flat "1".
public struct DamageDice: Hashable, Codable, Sendable {
    /// Groups of the same die, e.g. 2d6 is count 2, sides 6.
    public struct Term: Hashable, Codable, Sendable {
        public var count: Int
        public var sides: Int

        public init(count: Int, sides: Int) {
            self.count = count
            self.sides = sides
        }
    }

    public var terms: [Term]
    public var bonus: Int

    public init(terms: [Term], bonus: Int = 0) {
        self.terms = terms.filter { $0.count > 0 && $0.sides > 0 }
        self.bonus = bonus
    }

    public init(count: Int, sides: Int, bonus: Int = 0) {
        self.init(terms: [Term(count: count, sides: sides)], bonus: bonus)
    }

    /// Reads "1d8 + 3", "1d4+1", "1d6-1", "1d4 − 1", "2d6", "1d8 + 1d6", or a flat number such as "1".
    /// Anything after the dice (a damage type) is ignored. Nil when there are no dice or numbers.
    public init?(_ raw: String) {
        let text = raw.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        guard let regex = try? NSRegularExpression(pattern: #"^\s*([+-]?\s*\d+(?:d\d+)?(?:\s*[+-]\s*\d+(?:d\d+)?)*)"#,
                                                   options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let expression = text[range].replacingOccurrences(of: " ", with: "").lowercased()
        var terms: [Term] = []
        var bonus = 0
        var current = ""
        var sign = 1
        func flush() -> Bool {
            guard !current.isEmpty else { return true }
            defer { current = "" }
            if current.contains("d") {
                let parts = current.split(separator: "d").map(String.init)
                guard parts.count == 2, let count = Int(parts[0]), let sides = Int(parts[1]), count > 0, sides > 0 else { return false }
                // A minus in front of dice isn't something weapons do; treat it as unreadable.
                guard sign > 0 else { return false }
                terms.append(Term(count: count, sides: sides))
            } else {
                guard let value = Int(current) else { return false }
                bonus += sign * value
            }
            return true
        }
        for character in expression {
            if character == "+" || character == "-" {
                guard flush() else { return nil }
                sign = character == "-" ? -1 : 1
            } else {
                current.append(character)
            }
        }
        guard flush() else { return nil }
        self.init(terms: terms, bonus: bonus)
    }

    /// No dice and no bonus, such as "0".
    public var isZero: Bool { terms.isEmpty && bonus == 0 }

    /// The dice with each term's count doubled, for a critical hit. The bonus stays the same.
    public var doubled: DamageDice {
        DamageDice(terms: terms.map { Term(count: $0.count * 2, sides: $0.sides) }, bonus: bonus)
    }

    /// Adds dice and a bonus, e.g. extra dice for a higher spell slot.
    public func adding(_ other: DamageDice) -> DamageDice {
        var merged = terms
        for term in other.terms {
            if let index = merged.firstIndex(where: { $0.sides == term.sides }) {
                merged[index].count += term.count
            } else {
                merged.append(term)
            }
        }
        return DamageDice(terms: merged, bonus: bonus + other.bonus)
    }

    public func addingBonus(_ extra: Int) -> DamageDice {
        DamageDice(terms: terms, bonus: bonus + extra)
    }

    /// Every term's count multiplied, e.g. a cantrip doing 2d10 at 5th level instead of 1d10.
    public func multiplied(by factor: Int) -> DamageDice {
        DamageDice(terms: terms.map { Term(count: $0.count * max(1, factor), sides: $0.sides) }, bonus: bonus)
    }

    /// e.g. "2d6 + 3", "1d4 − 1", "1"
    public var text: String {
        let dice = terms.map { "\($0.count)d\($0.sides)" }.joined(separator: " + ")
        guard !dice.isEmpty else { return "\(bonus)" }
        switch bonus {
        case 0: return dice
        case let value where value > 0: return "\(dice) + \(value)"
        default: return "\(dice) − \(-bonus)"
        }
    }

    /// Rolls every die. The total never goes below zero.
    public func roll(using roller: DiceRoller) -> RolledDice {
        var faces: [Int] = []
        for term in terms {
            faces += roller.roll(term.count, d: term.sides)
        }
        return RolledDice(dice: self, faces: faces)
    }
}

/// Dice that have been rolled: what was rolled and each die's result.
public struct RolledDice: Hashable, Sendable {
    public let dice: DamageDice
    /// Each die's result, in term order.
    public let faces: [Int]

    public init(dice: DamageDice, faces: [Int]) {
        self.dice = dice
        self.faces = faces
    }

    public var total: Int { max(0, faces.reduce(0, +) + dice.bonus) }

    /// e.g. "2d6 + 3: [4, 2] + 3", or "1" for a flat amount.
    public var breakdown: String {
        guard !faces.isEmpty else { return dice.text }
        let rolled = "[\(faces.map(String.init).joined(separator: ", "))]"
        let terms = dice.terms.map { "\($0.count)d\($0.sides)" }.joined(separator: " + ")
        switch dice.bonus {
        case 0: return "\(terms): \(rolled)"
        case let value where value > 0: return "\(terms): \(rolled) + \(value)"
        default: return "\(terms): \(rolled) − \(-dice.bonus)"
        }
    }
}

/// Whether a d20 roll has advantage (roll two, keep the higher) or disadvantage (keep the lower).
public enum RollMode: String, CaseIterable, Identifiable, Sendable {
    case normal, advantage, disadvantage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return "Roll"
        case .advantage: return "Roll with advantage"
        case .disadvantage: return "Roll with disadvantage"
        }
    }
}

/// One attack roll: the d20s thrown and the one that counts.
public struct D20Roll: Hashable, Sendable {
    public let faces: [Int]
    public let mode: RollMode
    public let bonus: Int

    public init(faces: [Int], mode: RollMode, bonus: Int) {
        self.faces = faces
        self.mode = mode
        self.bonus = bonus
    }

    public static func roll(bonus: Int, mode: RollMode, using roller: DiceRoller) -> D20Roll {
        let faces = roller.roll(mode == .normal ? 1 : 2, d: 20)
        return D20Roll(faces: faces, mode: mode, bonus: bonus)
    }

    /// The die that counts.
    public var natural: Int {
        switch mode {
        case .normal: return faces.first ?? 1
        case .advantage: return faces.max() ?? 1
        case .disadvantage: return faces.min() ?? 1
        }
    }

    public var total: Int { natural + bonus }
    public var isCritical: Bool { natural == 20 }
    public var isFumble: Bool { natural == 1 }

    /// e.g. "17 (d20: 14 + 3)" or "17 (advantage 14, 6; + 3)"
    public var breakdown: String {
        let signed = bonus == 0 ? "" : (bonus > 0 ? " + \(bonus)" : " − \(-bonus)")
        switch mode {
        case .normal:
            return "\(total) (d20: \(natural)\(signed))"
        case .advantage, .disadvantage:
            let label = mode == .advantage ? "advantage" : "disadvantage"
            return "\(total) (\(label) \(faces.map(String.init).joined(separator: ", ")), kept \(natural)\(signed))"
        }
    }
}
