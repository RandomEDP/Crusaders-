import Foundation
import Observation
import CrusadersKit

/// App-wide state shared by every screen.
/// Everything is in memory for now. Sign in with Apple and CloudKit storage come in later branches.
@MainActor
@Observable
final class AppModel {
    var roster: CharacterRoster
    var campaignBook: CampaignBook
    let libraryCategories: [LibraryCategory]
    private let campaignDirectory: CampaignDirectory

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaignBook: CampaignBook = CampaignBook(),
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        campaignDirectory: CampaignDirectory = InMemoryCampaignDirectory.sample
    ) {
        self.roster = roster
        self.campaignBook = campaignBook
        self.libraryCategories = library.categories()
        self.campaignDirectory = campaignDirectory
    }

    @discardableResult
    func addCharacter(name: String, race: String, characterClass: String, level: Int) throws -> PlayerCharacter {
        try roster.add(name: name, race: race, characterClass: characterClass, level: level)
    }

    func deleteCharacters(atOffsets offsets: IndexSet) {
        roster.remove(atOffsets: offsets)
    }

    @discardableResult
    func createCampaign(name: String) throws -> Campaign {
        try campaignBook.create(name: name)
    }

    @discardableResult
    func joinCampaign(code: String) throws -> Campaign {
        try campaignBook.join(code: code, directory: campaignDirectory)
    }
}
