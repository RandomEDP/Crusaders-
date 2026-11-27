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
    let rules: RulesCatalog
    private let campaignDirectory: CampaignDirectory

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaignBook: CampaignBook = CampaignBook(),
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        campaignDirectory: CampaignDirectory = InMemoryCampaignDirectory.sample,
        rules: RulesCatalog = .srd,
        itemLibrary: ItemLibrary? = nil
    ) {
        self.roster = roster
        self.campaignBook = campaignBook
        self.libraryCategories = library.categories()
        self.campaignDirectory = campaignDirectory
        self.itemLibrary = itemLibrary ?? ItemLibrary.makeDefault()
        self.rules = rules
    }

    @discardableResult
    func addCharacter(name: String, race: String, characterClass: String, level: Int) throws -> PlayerCharacter {
        try roster.add(name: name, race: race, characterClass: characterClass, level: level)
    }

    /// Creates a character from the creation form.
    @discardableResult
    func createCharacter(from draft: CharacterDraft) throws -> PlayerCharacter {
        try roster.add(draft, catalog: rules)
    }

    func character(id: PlayerCharacter.ID) -> PlayerCharacter? {
        roster.character(id: id)
    }

    func sheet(for id: PlayerCharacter.ID) -> CharacterSheet? {
        character(id: id).map { CharacterSheet(character: $0, catalog: rules) }
    }

    /// Adds XP. Returns what the new levels unlock, or nil if the character didn't level up.
    @discardableResult
    func addExperience(_ amount: Int, to id: PlayerCharacter.ID) throws -> LevelUpSummary? {
        let gained = try roster.update(id: id) { try $0.addExperience(amount) }
        guard let gained, let hero = roster.character(id: id) else { return nil }
        return LevelUpSummary(character: hero, fromLevel: gained.lowerBound - 1, catalog: rules)
    }

    func toggleSpell(_ spellID: String, for id: PlayerCharacter.ID) {
        _ = try? roster.update(id: id) { $0.toggleSpell(spellID) }
    }

    func spendImprovementPoint(on ability: Ability, for id: PlayerCharacter.ID) throws {
        let catalog = self.rules
        try roster.update(id: id) { try $0.spendImprovementPoint(on: ability, catalog: catalog) }
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
