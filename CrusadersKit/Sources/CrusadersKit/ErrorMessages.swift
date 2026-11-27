import Foundation

/// Friendly messages shown in the UI when an action fails.
extension CharacterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give your character a name."
        case .levelOutOfRange: return "Level must be between 1 and 20."
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
