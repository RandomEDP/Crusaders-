import Foundation

/// Rolls dice. Tests pass a roller with fixed results.
public final class DiceRoller: @unchecked Sendable {
    private let lock = NSLock()
    private let rollDie: (Int) -> Int

    /// `rollDie` gets the number of sides and returns a result from 1 to that number.
    public init(_ rollDie: @escaping (Int) -> Int) {
        self.rollDie = rollDie
    }

    /// Real random rolls.
    public static let random = DiceRoller { sides in Int.random(in: 1...max(1, sides)) }

    /// Returns these results in order, then starts again. Each is clamped to the die's sides.
    public static func sequence(_ results: [Int]) -> DiceRoller {
        var index = 0
        return DiceRoller { sides in
            guard !results.isEmpty else { return 1 }
            let result = results[index % results.count]
            index += 1
            return min(max(result, 1), max(1, sides))
        }
    }

    public func roll(_ sides: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return rollDie(sides)
    }

    public func roll(_ count: Int, d sides: Int) -> [Int] {
        (0..<max(0, count)).map { _ in roll(sides) }
    }
}

/// One ability score rolled as 4d6, dropping the lowest die.
public struct AbilityRoll: Codable, Hashable, Sendable {
    /// All four dice, in the order rolled.
    public let dice: [Int]

    public init(dice: [Int]) {
        self.dice = dice
    }

    public static func roll(using roller: DiceRoller = .random) -> AbilityRoll {
        AbilityRoll(dice: roller.roll(4, d: 6))
    }

    /// The index of the die that doesn't count.
    public var droppedIndex: Int? {
        dice.indices.min { dice[$0] < dice[$1] }
    }

    public var total: Int {
        guard let droppedIndex else { return 0 }
        return dice.enumerated().filter { $0.offset != droppedIndex }.map(\.element).reduce(0, +)
    }
}

/// How the player sets ability scores while building a character.
public enum AbilityMethod: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    /// 15, 14, 13, 12, 10, 8, placed where the player wants.
    case standardArray
    /// 27 points to spend, scores 8 to 15.
    case pointBuy
    /// Six 4d6-drop-lowest rolls, placed where the player wants.
    case rolled
    /// Any score from 3 to 18, for scores rolled at the table.
    case custom

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .standardArray: return "Standard array"
        case .pointBuy: return "Point buy"
        case .rolled: return "Roll 4d6"
        case .custom: return "Custom"
        }
    }
}

/// How hit points go up each level.
public enum HitPointMethod: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    /// The SRD fixed value: half the hit die + 1.
    case fixed
    /// Roll the hit die each level.
    case rolled

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .fixed: return "Fixed"
        case .rolled: return "Roll"
        }
    }
}

/// The SRD point-buy rules.
public enum PointBuy {
    public static let budget = 27
    public static let range = 8...15

    /// Points a score costs, or nil if point buy doesn't allow it.
    public static func cost(of score: Int) -> Int? {
        switch score {
        case 8: return 0
        case 9: return 1
        case 10: return 2
        case 11: return 3
        case 12: return 4
        case 13: return 5
        case 14: return 7
        case 15: return 9
        default: return nil
        }
    }

    /// Total points spent, or nil if any score is outside 8 to 15.
    public static func spent(on scores: AbilityScores) -> Int? {
        var total = 0
        for ability in Ability.allCases {
            guard let cost = cost(of: scores[ability]) else { return nil }
            total += cost
        }
        return total
    }

    public static func remaining(for scores: AbilityScores) -> Int? {
        spent(on: scores).map { budget - $0 }
    }

    /// Whether raising this ability by 1 stays within the rules and the budget.
    public static func canIncrease(_ ability: Ability, in scores: AbilityScores) -> Bool {
        var raised = scores
        raised[ability] += 1
        guard let spent = spent(on: raised) else { return false }
        return spent <= budget
    }

    public static func canDecrease(_ ability: Ability, in scores: AbilityScores) -> Bool {
        scores[ability] > range.lowerBound
    }
}
