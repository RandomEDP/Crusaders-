import Foundation
import Observation
import CrusadersKit

/// App-wide state shared by every screen.
/// Characters and campaigns are in memory for now. Library item edits sync through CloudKit (see `ItemLibrary.makeDefault`).
@MainActor
@Observable
final class AppModel {
    var roster: CharacterRoster
    var campaignBook: CampaignBook
    let libraryCategories: [LibraryCategory]
    let itemLibrary: ItemLibrary
    private let campaignDirectory: CampaignDirectory

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaignBook: CampaignBook = CampaignBook(),
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        campaignDirectory: CampaignDirectory = InMemoryCampaignDirectory.sample,
        itemLibrary: ItemLibrary? = nil
    ) {
        self.roster = roster
        self.campaignBook = campaignBook
        self.libraryCategories = library.categories()
        self.campaignDirectory = campaignDirectory
        self.itemLibrary = itemLibrary ?? ItemLibrary.makeDefault()
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
