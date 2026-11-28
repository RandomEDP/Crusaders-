import Foundation

/// The coins a character carries, by type.
public struct CoinPurse: Hashable, Sendable {
    public private(set) var counts: [Coin: Int]

    public init(_ counts: [Coin: Int] = [:]) {
        self.counts = counts.filter { $0.value != 0 }
    }

    public subscript(coin: Coin) -> Int { counts[coin] ?? 0 }

    public var isEmpty: Bool { counts.values.allSatisfy { $0 == 0 } }

    /// Everything, in copper (house rule rates, see `Coin.copperValue`).
    public var totalCopper: Int {
        counts.reduce(0) { $0 + $1.key.copperValue * $1.value }
    }

    /// e.g. "12 gp, 40 sp, 3 cp", biggest coins first.
    public var text: String {
        let parts = Coin.allCases.reversed().compactMap { coin -> String? in
            let count = self[coin]
            return count > 0 ? "\(count) \(coin.rawValue)" : nil
        }
        return parts.isEmpty ? "No coins" : parts.joined(separator: ", ")
    }

    /// The purse after `deltas`, or nil if any coin would go below zero.
    public func adding(_ deltas: [Coin: Int]) -> CoinPurse? {
        var next = counts
        for (coin, delta) in deltas {
            let value = (next[coin] ?? 0) + delta
            guard value >= 0 else { return nil }
            next[coin] = value
        }
        return CoinPurse(next)
    }

    /// Copper as gold, silver and copper, fewest coins first (change is never given in electrum or platinum).
    public static func change(forCopper copper: Int) -> [Coin: Int] {
        var left = max(0, copper)
        var coins: [Coin: Int] = [:]
        for coin in [Coin.gp, .sp, .cp] {
            let count = left / coin.copperValue
            if count > 0 { coins[coin] = count }
            left -= count * coin.copperValue
        }
        return coins
    }

    /// The coins that change hands to pay `cost`: exact coins where possible (smallest first), otherwise
    /// breaking a bigger coin and getting change back. Negative numbers leave the purse, positive ones are change.
    /// Nil if there isn't enough money.
    public func payment(for cost: Cost) -> [Coin: Int]? {
        let price = cost.inCopper
        guard price > 0, totalCopper >= price else { return nil }
        // Paid with the same coin if there are enough of them.
        if self[cost.coin] >= cost.amount { return [cost.coin: -cost.amount] }

        var left = counts
        var paid: [Coin: Int] = [:]
        var remaining = price
        // Exact payment with smaller coins first, never overpaying.
        for coin in Coin.allCases.sorted(by: { $0.copperValue < $1.copperValue }) {
            let use = min(left[coin] ?? 0, remaining / coin.copperValue)
            if use > 0 {
                paid[coin, default: 0] += use
                left[coin, default: 0] -= use
                remaining -= use * coin.copperValue
            }
        }
        // Then break bigger coins: the smallest one that covers what's left, or the biggest there is.
        while remaining > 0 {
            let available = Coin.allCases.filter { (left[$0] ?? 0) > 0 }.sorted { $0.copperValue < $1.copperValue }
            guard let coin = available.first(where: { $0.copperValue >= remaining }) ?? available.last else { return nil }
            paid[coin, default: 0] += 1
            left[coin, default: 0] -= 1
            remaining -= coin.copperValue
        }
        var deltas = paid.mapValues { -$0 }
        for (coin, count) in Self.change(forCopper: -remaining) {
            deltas[coin, default: 0] += count
        }
        return deltas.filter { $0.value != 0 }
    }
}

/// Coins added to or taken from a character's purse, as one record (an exchange or payment with change is one change).
public struct CoinChange: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var playerID: String
    public var deltas: [Coin: Int]
    public var authorID: String
    public var date: Date
    /// e.g. "Paid 5 gp", "Given by the DM"
    public var note: String?

    public init(id: UUID = UUID(), playerID: String, deltas: [Coin: Int], authorID: String, date: Date = Date(),
                note: String? = nil) {
        self.id = id
        self.playerID = playerID
        self.deltas = deltas
        self.authorID = authorID
        self.date = date
        self.note = note
    }

    /// Change in total worth, in copper.
    public var valueCopper: Int {
        deltas.reduce(0) { $0 + $1.key.copperValue * $1.value }
    }
}

public enum CoinError: Error, Equatable, Sendable {
    case invalidAmount
    case notEnoughMoney
    case onlyDungeonMasterCanGive
    case notYourPurse
}
