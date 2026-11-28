import Foundation

public enum CreatureValidationError: Error, Equatable {
    case emptyName
    case armorClassOutOfRange
    case hitPointsOutOfRange
    case invalidHitDice(String)
    case abilityOutOfRange(Ability)
    case invalidChallengeRating
    case emptySpeed
    case unnamedFeature
}

extension CreatureValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the creature a name."
        case .armorClassOutOfRange: return "Armour Class must be between 1 and 30."
        case .hitPointsOutOfRange: return "Hit points must be between 1 and 1,000."
        case .invalidHitDice(let text): return "\"\(text)\" isn't valid hit dice. Use dice like 2d6 or 19d12 + 133, or leave it blank."
        case .abilityOutOfRange(let ability): return "\(ability.name) must be between 1 and 30."
        case .invalidChallengeRating: return "Pick a challenge rating from 0 to 30."
        case .emptySpeed: return "Give the creature a speed, such as 30 ft."
        case .unnamedFeature: return "Every trait and action needs a name."
        }
    }
}

public enum CreatureValidator {
    /// Dice like "2d6", "19d12 + 133" or "7d8 - 7".
    public static func isValidHitDice(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        return compact.range(of: #"^\d{1,3}d\d{1,3}([+-]\d{1,4})?$"#, options: .regularExpression) != nil
    }

    /// Tidies a creature (trims text, drops empty optional text and blank features) and checks it makes sense.
    public static func validated(_ creature: Creature) throws -> Creature {
        var c = creature
        c.name = trim(c.name)
        c.alignment = trim(c.alignment)
        c.hitDice = trim(c.hitDice)
        c.speed = trim(c.speed)
        c.senses = trim(c.senses)
        c.languages = trim(c.languages)
        if c.alignment.isEmpty { c.alignment = "unaligned" }
        if c.languages.isEmpty { c.languages = "—" }
        c.subtype = optional(c.subtype)
        c.armorNote = optional(c.armorNote)
        c.savingThrows = optional(c.savingThrows)
        c.skills = optional(c.skills)
        c.damageVulnerabilities = optional(c.damageVulnerabilities)
        c.damageResistances = optional(c.damageResistances)
        c.damageImmunities = optional(c.damageImmunities)
        c.conditionImmunities = optional(c.conditionImmunities)
        c.description = optional(c.description)

        guard !c.name.isEmpty else { throw CreatureValidationError.emptyName }
        guard (1...30).contains(c.armorClass) else { throw CreatureValidationError.armorClassOutOfRange }
        guard (1...1000).contains(c.hitPoints) else { throw CreatureValidationError.hitPointsOutOfRange }
        if !c.hitDice.isEmpty, !isValidHitDice(c.hitDice) { throw CreatureValidationError.invalidHitDice(c.hitDice) }
        for ability in Ability.allCases where !(1...30).contains(c.abilities[ability]) {
            throw CreatureValidationError.abilityOutOfRange(ability)
        }
        guard ChallengeRating.isValid(c.challengeRating) else { throw CreatureValidationError.invalidChallengeRating }
        guard !c.speed.isEmpty else { throw CreatureValidationError.emptySpeed }

        c.traits = try features(c.traits)
        c.actions = try features(c.actions)
        c.reactions = try features(c.reactions)
        c.legendaryActions = try features(c.legendaryActions)
        return c
    }

    /// Drops rows left completely blank; a row with a description but no name is an error.
    private static func features(_ list: [CreatureFeature]) throws -> [CreatureFeature] {
        try list.compactMap { feature in
            let name = trim(feature.name)
            let description = trim(feature.description)
            if name.isEmpty && description.isEmpty { return nil }
            guard !name.isEmpty else { throw CreatureValidationError.unnamedFeature }
            return CreatureFeature(name: name, description: description)
        }
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = trim(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}
