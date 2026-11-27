import Foundation
import Observation
import CrusadersKit

/// App-wide state shared by every screen.
/// Characters are in memory for now. Campaigns are saved on the phone and shared through CloudKit once iCloud is on
/// (see `CampaignManager.makeDefault`). Library item edits sync through CloudKit (see `ItemLibrary.makeDefault`).
@MainActor
@Observable
final class AppModel {
    var roster: CharacterRoster
    let campaigns: CampaignManager
    let libraryCategories: [LibraryCategory]
    let itemLibrary: ItemLibrary
    let rules: RulesCatalog

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaigns: CampaignManager? = nil,
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        rules: RulesCatalog = .srd,
        itemLibrary: ItemLibrary? = nil
    ) {
        self.roster = roster
        self.campaigns = campaigns ?? CampaignManager.makeDefault()
        self.libraryCategories = library.categories()
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

    /// Creates a campaign with a new 6-digit join code. The user is its Dungeon Master.
    @discardableResult
    func createCampaign(name: String, yourName: String) async throws -> Campaign {
        try await campaigns.create(name: name, yourName: yourName)
    }

    /// Joins a campaign by its 6-digit code. The user is listed as a player.
    @discardableResult
    func joinCampaign(code: String, yourName: String) async throws -> Campaign {
        try await campaigns.join(code: code, yourName: yourName)
    }
}
