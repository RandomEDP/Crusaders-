import Foundation

/// The SRD experience point table.
public enum Experience {
    /// The XP needed to reach each level: index 0 is level 1.
    public static let thresholds = [
        0, 300, 900, 2_700, 6_500, 14_000, 23_000, 34_000, 48_000, 64_000,
        85_000, 100_000, 120_000, 140_000, 165_000, 195_000, 225_000, 265_000, 305_000, 355_000
    ]

    /// The level a character with this much XP has reached (1 to 20).
    public static func level(forXP xp: Int) -> Int {
        thresholds.lastIndex { xp >= $0 }.map { $0 + 1 } ?? 1
    }

    /// The XP a character needs to be this level.
    public static func minimumXP(forLevel level: Int) -> Int {
        thresholds[min(max(level, 1), thresholds.count) - 1]
    }

    /// The XP needed for the level after this one, or nil at level 20.
    public static func nextLevelXP(afterLevel level: Int) -> Int? {
        level < thresholds.count ? thresholds[max(level, 1)] : nil
    }
}
