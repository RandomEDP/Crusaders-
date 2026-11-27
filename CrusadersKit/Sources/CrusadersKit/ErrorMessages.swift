import Foundation

/// Friendly messages shown in the UI when an action fails.
extension CharacterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give your character a name."
        case .levelOutOfRange: return "Level must be between 1 and 20."
        case .missingRace: return "Pick a race."
        case .missingClass: return "Pick a class."
        case .invalidSubrace: return "Pick a subrace for this race."
        case .invalidAbilityScore: return "Ability scores must be between 3 and 18 before bonuses."
        case .invalidRacialBonus: return "Those racial bonus choices aren't allowed for this race."
        case .tooManySkills: return "You've picked more skills than your class allows."
        case .invalidSkill: return "One of those skills isn't on your class list."
        case .invalidExperience: return "Enter an amount of XP above zero."
        case .noImprovementPoints: return "No Ability Score Improvement points left to spend."
        case .abilityAtMaximum: return "Abilities can't go above 20."
        case .characterNotFound: return "That character no longer exists."
        }
    }
}

extension CampaignError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give your campaign a name."
        case .invalidJoinCode: return "Join codes are 6 letters or numbers."
        case .campaignNotFound: return "No campaign uses that code."
        case .alreadyJoined: return "You're already in that campaign."
        }
    }
}
