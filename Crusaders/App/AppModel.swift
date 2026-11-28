import Foundation
import Observation
import CrusadersKit

/// App-wide state shared by every screen.
/// Characters are saved through `characterStore` (SwiftData, synced with iCloud when it's on; see `CharacterPersistence`).
/// Campaigns are saved on the phone and shared through CloudKit once iCloud is on (see `CampaignManager.makeDefault`).
/// Library item edits sync through CloudKit (see `ItemLibrary.makeDefault`).
@MainActor
@Observable
final class AppModel {
    private(set) var roster: CharacterRoster
    /// Set when saving or loading characters failed, for the Characters screen to show.
    private(set) var characterStorageProblem: String?
    let characterStorageMode: CharacterPersistence.Mode
    private let characterStore: CharacterStore?
    let campaigns: CampaignManager
    /// Party and private chats in campaigns. Shared through CloudKit when campaigns are (see `CloudKitChatService`).
    let chat: CampaignChat
    let libraryCategories: [LibraryCategory]
    let itemLibrary: ItemLibrary
    let rules: RulesCatalog

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaigns: CampaignManager? = nil,
        chat: CampaignChat? = nil,
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        rules: RulesCatalog = .srd,
        itemLibrary: ItemLibrary? = nil,
        characterStore: CharacterStore? = nil,
        characterStorageMode: CharacterPersistence.Mode = .memory(reason: nil)
    ) {
        self.roster = roster
        let campaigns = campaigns ?? CampaignManager.makeDefault()
        self.campaigns = campaigns
        self.chat = chat ?? CampaignChat.makeDefault(sharedThroughCloudKit: campaigns.isShared)
        self.characterStore = characterStore
        self.characterStorageMode = characterStorageMode
        self.libraryCategories = library.categories()
        self.itemLibrary = itemLibrary ?? ItemLibrary.makeDefault()
        self.rules = rules
        if characterStore != nil {
            reloadCharacters()
        }
    }

    /// The app's model with characters saved where `CharacterPersistence` picks.
    static func live() -> AppModel {
        let setup = CharacterPersistence.makeDefault()
        return AppModel(characterStore: setup.store, characterStorageMode: setup.mode)
    }

    /// Reads characters from the store again, for example after iCloud brings in changes.
    func reloadCharacters() {
        guard let characterStore else { return }
        do {
            roster = CharacterRoster(characters: try characterStore.loadCharacters())
            characterStorageProblem = nil
        } catch {
            characterStorageProblem = "Couldn't load your characters: \(error.localizedDescription)"
        }
    }

    private func persist(_ id: PlayerCharacter.ID) {
        guard let characterStore else { return }
        do {
            if let character = roster.character(id: id) {
                try characterStore.save(character)
            } else {
                try characterStore.delete(id: id)
            }
            characterStorageProblem = nil
        } catch {
            characterStorageProblem = "Couldn't save your changes: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addCharacter(name: String, race: String, characterClass: String, level: Int) throws -> PlayerCharacter {
        let character = try roster.add(name: name, race: race, characterClass: characterClass, level: level)
        persist(character.id)
        return character
    }

    /// Creates a character from the creation form.
    @discardableResult
    func createCharacter(from draft: CharacterDraft) throws -> PlayerCharacter {
        let character = try roster.add(draft, catalog: rules)
        persist(character.id)
        return character
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
        persist(id)
        guard let gained, let hero = roster.character(id: id) else { return nil }
        return LevelUpSummary(character: hero, fromLevel: gained.lowerBound - 1, catalog: rules)
    }

    func toggleSpell(_ spellID: String, for id: PlayerCharacter.ID) {
        guard (try? roster.update(id: id) { $0.toggleSpell(spellID) }) != nil else { return }
        persist(id)
    }

    func spendImprovementPoint(on ability: Ability, for id: PlayerCharacter.ID) throws {
        let catalog = self.rules
        try roster.update(id: id) { try $0.spendImprovementPoint(on: ability, catalog: catalog) }
        persist(id)
    }

    func deleteCharacters(atOffsets offsets: IndexSet) {
        let ids = offsets.compactMap { roster.characters.indices.contains($0) ? roster.characters[$0].id : nil }
        roster.remove(atOffsets: offsets)
        for id in ids {
            persist(id)
        }
    }

    /// Creates a campaign with a new 6-digit join code. The user is its Dungeon Master.
    @discardableResult
    func createCampaign(name: String, yourName: String) async throws -> Campaign {
        try await campaigns.create(name: name, yourName: yourName)
    }

    /// Joins a campaign by its 6-digit code with one of the user's saved characters. The user is listed as a player.
    @discardableResult
    func joinCampaign(code: String, yourName: String, characterID: PlayerCharacter.ID?) async throws -> Campaign {
        try await campaigns.join(code: code, yourName: yourName, character: characterID.flatMap(character(id:)))
    }

    /// The DM adds a Library item to a player's character inventory.
    @discardableResult
    func addItem(_ item: EquipmentItem, quantity: Int, to playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.addItem(itemID: item.id, name: item.name, quantity: quantity, to: playerID, inCampaign: code)
    }

    /// The DM, or the player who owns the character, removes one of an item.
    @discardableResult
    func removeItem(_ itemID: String, from playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.removeItem(itemID: itemID, from: playerID, inCampaign: code)
    }
}
