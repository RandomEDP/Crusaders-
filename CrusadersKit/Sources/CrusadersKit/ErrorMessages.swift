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
        case .emptyPlayerName: return "Enter your name so the party knows who you are."
        case .invalidJoinCode: return "Join codes are 6 digits."
        case .campaignNotFound: return "No campaign uses that code."
        case .alreadyJoined: return "You're already in that campaign."
        case .codeTaken: return "Couldn't find a free join code. Please try again."
        case .directoryUnavailable: return "Couldn't reach iCloud. Check you're online and signed in to iCloud, then try again."
        case .noCharacterSelected: return "Pick one of your characters to join with."
        case .onlyDungeonMasterCanAdd: return "Only the Dungeon Master can add items."
        case .notYourInventory: return "You can only remove items from your own character."
        case .invalidQuantity: return "Enter a quantity of 1 or more."
        case .itemNotInInventory: return "That item isn't in the inventory any more."
        case .playerNotFound: return "That player isn't in this campaign."
        }
    }
}

extension ChatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyMessage: return "Write a message first."
        case .messageTooLong: return "That message is too long. Keep it under \(CampaignChat.maxLength) characters."
        case .notAllowed: return "Only the Dungeon Master and that player can read this private chat."
        case .onlyDungeonMasterCanNarrate: return "Only the Dungeon Master can narrate."
        case .privateChatNotReady: return "Your private chat opens once the Dungeon Master opens it on their phone. Pull down to check again."
        case .unavailable: return "Couldn't reach iCloud. Check you're online and signed in to iCloud, then try again."
        }
    }
}
