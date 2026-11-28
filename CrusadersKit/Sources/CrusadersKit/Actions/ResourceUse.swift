import Foundation

extension CharacterResource {
    /// Dice written in the detail, e.g. 1d10 in "DC 12 Dex, 1d10 Acid".
    public var detailDice: DamageDice? {
        guard let detail,
              let match = SpellDice.firstMatch(#"(\d+d\d+(?:\s*[+-]\s*\d+)?)"#, in: detail) else { return nil }
        return DamageDice(match[1])
    }

    /// The damage type after the dice, e.g. "acid" in "DC 12 Dex, 1d10 Acid".
    var detailDamageType: String? {
        guard let detail,
              let match = SpellDice.firstMatch(#"\d+d\d+(?:\s*[+-]\s*\d+)?\s+([A-Za-z]+)"#, in: detail),
              DamageType(rawValue: match[1].lowercased()) != nil else { return nil }
        return match[1].lowercased()
    }

    /// The message posted in the party chat when the ability is used, rolling any dice in its detail, e.g.
    /// "🔥 Thirke uses Breath Weapon (1 of 2 left)\nDC 12 Dex, 1d10 Acid\nRoll: 7 acid (1d10: [7])".
    /// `remaining` is the uses left after this one.
    public func useText(characterName: String, remaining: Int, roller: DiceRoller) -> String {
        var lines = ["🔥 \(characterName) uses \(name) (\(remaining) of \(uses) left)"]
        if let detail, !detail.isEmpty { lines.append(detail) }
        if let dice = detailDice {
            let rolled = dice.roll(using: roller)
            let type = detailDamageType.map { " \($0)" } ?? ""
            lines.append("Roll: \(rolled.total)\(type) (\(rolled.breakdown))")
        }
        return lines.joined(separator: "\n")
    }
}

extension PlayerCharacter {
    /// Spends one use of an ability, or throws when none are left. Returns the resource after the use.
    @discardableResult
    public mutating func spendResource(_ id: CharacterResource.ID) throws -> CharacterResource {
        guard let resource = resources.first(where: { $0.id == id }) else { throw CharacterError.characterNotFound }
        guard useResource(id), let used = resources.first(where: { $0.id == id }) else {
            throw ActionError.noUsesLeft(name: resource.name)
        }
        return used
    }
}
