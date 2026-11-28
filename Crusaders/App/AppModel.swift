import Foundation
import Observation
import CrusadersKit

/// App-wide state shared by every screen.
/// Characters are saved through `characterStore` (SwiftData, synced with iCloud when it's on; see `CharacterPersistence`).
/// Campaigns are saved on the phone and shared through CloudKit once iCloud is on (see `CampaignManager.makeDefault`).
/// Library item edits and the creator's creatures sync through CloudKit (see `ItemLibrary.makeDefault`, `CreatureLibrary.makeDefault`).
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
    /// Library > Creatures: SRD monsters plus the creator's own.
    let creatureLibrary: CreatureLibrary
    let rules: RulesCatalog
    /// Rolls hit dice on level-up for characters that roll hit points.
    let diceRoller: DiceRoller
    /// A D&D Beyond sheet that was read and is waiting on the review screen.
    var pendingImport: PendingSheetImport?
    /// Set when a picked or shared PDF couldn't be read.
    var importProblem: String?

    init(
        roster: CharacterRoster = CharacterRoster(),
        campaigns: CampaignManager? = nil,
        chat: CampaignChat? = nil,
        library: LibraryCatalog = PlaceholderLibraryCatalog(),
        rules: RulesCatalog = .srd,
        itemLibrary: ItemLibrary? = nil,
        creatureLibrary: CreatureLibrary? = nil,
        characterStore: CharacterStore? = nil,
        characterStorageMode: CharacterPersistence.Mode = .memory(reason: nil),
        diceRoller: DiceRoller = .random
    ) {
        self.roster = roster
        self.diceRoller = diceRoller
        let campaigns = campaigns ?? CampaignManager.makeDefault()
        self.campaigns = campaigns
        self.chat = chat ?? CampaignChat.makeDefault(sharedThroughCloudKit: campaigns.isShared)
        self.characterStore = characterStore
        self.characterStorageMode = characterStorageMode
        self.libraryCategories = library.categories()
        self.itemLibrary = itemLibrary ?? ItemLibrary.makeDefault()
        self.creatureLibrary = creatureLibrary ?? CreatureLibrary.makeDefault()
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

    /// Changes a character (details, lore, limited uses) and saves it.
    func updateCharacter(_ id: PlayerCharacter.ID, _ change: (inout PlayerCharacter) -> Void) {
        guard (try? roster.update(id: id, { change(&$0) })) != nil else { return }
        persist(id)
    }

    // MARK: Import from D&D Beyond

    /// Reads a character sheet PDF (picked in Files, or shared to the app) and opens the review screen.
    /// Everything is read on the phone; nothing is uploaded.
    func openSheetPDF(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            // Files shared with "Open in" are copied to Documents/Inbox; the copy isn't needed once read.
            if url.pathComponents.contains("Inbox") { try? FileManager.default.removeItem(at: url) }
        }
        do {
            let data = try Data(contentsOf: url)
            let result = try DDBSheetParser.parse(pdf: data, catalog: rules)
            importProblem = nil
            pendingImport = PendingSheetImport(result: result)
        } catch {
            importProblem = error.localizedDescription
        }
    }

    /// Saves a reviewed import as a new character, through the normal save path (so it syncs like any other).
    @discardableResult
    func saveImport(_ result: SheetImport) throws -> PlayerCharacter {
        let character = try roster.add(imported: result, catalog: rules)
        persist(character.id)
        pendingImport = nil
        return character
    }

    /// The character sheet with equipped items applied: from the campaign given, or else the first campaign
    /// this user plays the character in.
    func sheet(for id: PlayerCharacter.ID, campaignCode: String? = nil) -> CharacterSheet? {
        guard let character = character(id: id) else { return nil }
        let campaign = playedCampaign(for: id, code: campaignCode)
        return CharacterSheet(
            character: character, catalog: rules,
            gear: campaign?.equippedGear(of: campaigns.me.id, catalog: itemLibrary.catalog) ?? .none,
            combat: campaign?.combatState(of: campaigns.me.id) ?? .none
        )
    }

    /// The campaign given (if this user plays the character there), or the first one they play it in.
    func playedCampaign(for characterID: PlayerCharacter.ID, code: String?) -> Campaign? {
        let playing = campaigns(playing: characterID)
        return code.flatMap { code in playing.first { $0.joinCode == code } } ?? playing.first
    }

    /// Campaigns where this user plays the character, in the order they were joined.
    func campaigns(playing characterID: PlayerCharacter.ID) -> [Campaign] {
        let me = campaigns.me.id
        return campaigns.campaigns.filter { $0.player(id: me)?.character?.id == characterID }
    }

    /// What the character wears and holds in a campaign (or the first campaign they're in).
    func gear(for characterID: PlayerCharacter.ID, campaignCode: String? = nil) -> EquippedGear {
        guard let campaign = playedCampaign(for: characterID, code: campaignCode) else { return .none }
        return campaign.equippedGear(of: campaigns.me.id, catalog: itemLibrary.catalog)
    }

    /// Adds XP. Returns what the new levels unlock, or nil if the character didn't level up.
    @discardableResult
    func addExperience(_ amount: Int, to id: PlayerCharacter.ID) throws -> LevelUpSummary? {
        let hitDie = rules.characterClass(id: roster.character(id: id)?.classID)?.hitDie ?? 8
        let roller = diceRoller
        let gained = try roster.update(id: id) { character -> ClosedRange<Int>? in
            let gained = try character.addExperience(amount)
            character.rollMissingHitPoints(hitDie: hitDie, roller: roller)
            return gained
        }
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
        // Ammunition bundles go in as single pieces ("Arrows (20)" × 1 is 20 arrows), so each shot can use one.
        try await campaigns.addItem(itemID: item.id, name: item.inventoryName, quantity: item.inventoryQuantity(for: quantity),
                                    to: playerID, inCampaign: code)
    }

    // MARK: Equipment (the player who owns the character, or the DM)

    @discardableResult
    func equip(_ itemID: String, in slot: EquipSlot, base: String? = nil, for playerID: String,
               inCampaign code: String) async throws -> Campaign {
        try await campaigns.equip(itemID: itemID, in: slot, base: base, for: playerID, inCampaign: code,
                                  catalog: itemLibrary.catalog)
    }

    @discardableResult
    func unequip(_ itemID: String, for playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.unequip(itemID: itemID, for: playerID, inCampaign: code, catalog: itemLibrary.catalog)
    }

    @discardableResult
    func setUsesBothHands(_ both: Bool, for playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.setUsesBothHands(both, for: playerID, inCampaign: code, catalog: itemLibrary.catalog)
    }

    @discardableResult
    func attune(_ itemID: String, for playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.attune(itemID: itemID, for: playerID, inCampaign: code, catalog: itemLibrary.catalog)
    }

    @discardableResult
    func endAttunement(_ itemID: String, for playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.endAttunement(itemID: itemID, for: playerID, inCampaign: code, catalog: itemLibrary.catalog)
    }

    // MARK: Combat

    /// Drinks a potion from a character's inventory and applies its effects.
    @discardableResult
    func usePotion(_ itemID: String, for playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.usePotion(itemID: itemID, for: playerID, inCampaign: code, roller: diceRoller)
    }

    /// On a player's phone: tells the DM this character's max HP and AC in the campaign, if they changed.
    func reportStatus(inCampaign code: String) async {
        guard let campaign = campaigns.campaign(code: code),
              let characterID = campaign.player(id: campaigns.me.id)?.character?.id,
              let sheet = sheet(for: characterID, campaignCode: code) else { return }
        _ = try? await campaigns.reportStatus(maxHitPoints: sheet.maxHitPoints, armorClass: sheet.armorClass, inCampaign: code)
    }

    /// The DM, or the player who owns the character, removes one of an item.
    @discardableResult
    func removeItem(_ itemID: String, from playerID: String, inCampaign code: String) async throws -> Campaign {
        try await campaigns.removeItem(itemID: itemID, from: playerID, inCampaign: code)
    }
}

// MARK: - Rolling attacks, casting spells and using abilities

/// What tapping an attack, spell or ability did, for the sheet to show.
struct ActionOutcome: Identifiable, Equatable {
    let id = UUID()
    /// The roll, as posted in the party chat.
    let text: String
    /// The campaign whose party chat got the roll. Nil when the character isn't in a campaign.
    let postedTo: String?
    /// Set when the roll couldn't be posted (iCloud down); the slot, use or ammunition is still spent.
    let problem: String?
}

extension AppModel {
    /// Ammunition in the character's campaign inventory that a weapon can fire, ordinary ammunition first.
    func ammunition(_ kind: AmmoKind, for characterID: PlayerCharacter.ID, campaignCode: String? = nil) -> [AmmoStack] {
        guard let campaign = playedCampaign(for: characterID, code: campaignCode) else { return [] }
        return AmmoStack.stacks(for: kind, in: campaign.inventory(of: campaigns.me.id), catalog: itemLibrary.catalog)
    }

    /// Rolls an attack and posts it in the campaign's party chat. Bows, crossbows, slings and blowguns use one
    /// piece of ammunition from the inventory (`ammoItemID`, or the first that fits), and can't fire without it.
    func rollAttack(_ attack: AttackOption, characterID: PlayerCharacter.ID, campaignCode: String? = nil,
                    mode: RollMode = .normal, ammoItemID: String? = nil) async throws -> ActionOutcome {
        guard let character = character(id: characterID) else { throw CharacterError.characterNotFound }
        let campaign = playedCampaign(for: characterID, code: campaignCode)
        var stack: AmmoStack?
        if let kind = attack.ammunition {
            guard let campaign else { throw ActionError.ammunitionNeedsCampaign }
            let stacks = ammunition(kind, for: characterID, campaignCode: campaign.joinCode)
            stack = stacks.first { $0.itemID == ammoItemID } ?? stacks.first
            guard let stack else { throw ActionError.noAmmunition(kind) }
            try await campaigns.removeItem(itemID: stack.itemID, quantity: 1, from: campaigns.me.id, inCampaign: campaign.joinCode)
        }
        let result = attack.roll(mode: mode, extraBonus: stack?.bonus ?? 0, using: diceRoller)
        let text = result.chatText(characterName: character.name, ammoName: stack?.name,
                                   ammoLeft: stack.map { $0.quantity - 1 })
        return await post(text, campaign: campaign)
    }

    /// Casts a spell: spends a slot of `slotLevel` (cantrips are free), rolls its attack, damage or healing,
    /// and posts it in the party chat. Throws, spending nothing, when no slot of that level is left.
    func castSpell(_ spell: Spell, slotLevel: Int?, characterID: PlayerCharacter.ID, campaignCode: String? = nil,
                   mode: RollMode = .normal) async throws -> ActionOutcome {
        guard let sheet = sheet(for: characterID, campaignCode: campaignCode) else { throw CharacterError.characterNotFound }
        let slot = spell.isCantrip ? nil : (slotLevel ?? spell.level)
        return try await cast(sheet.cast(spell, slotLevel: slot), sheet: sheet, characterID: characterID,
                              campaignCode: campaignCode, mode: mode)
    }

    /// Casts a spell printed on an imported sheet that has no SRD match.
    func castSpell(imported spell: ImportedSheet.SpellEntry, slotLevel: Int?, characterID: PlayerCharacter.ID,
                   campaignCode: String? = nil, mode: RollMode = .normal) async throws -> ActionOutcome {
        guard let sheet = sheet(for: characterID, campaignCode: campaignCode) else { throw CharacterError.characterNotFound }
        if let id = spell.srdID, let srd = rules.spells(ids: [id]).first {
            return try await castSpell(srd, slotLevel: slotLevel, characterID: characterID, campaignCode: campaignCode, mode: mode)
        }
        return try await cast(sheet.cast(imported: spell, slotLevel: slotLevel), sheet: sheet, characterID: characterID,
                              campaignCode: campaignCode, mode: mode)
    }

    private func cast(_ cast: SpellCast, sheet: CharacterSheet, characterID: PlayerCharacter.ID,
                      campaignCode: String?, mode: RollMode) async throws -> ActionOutcome {
        var slotsLeft: Int?
        if let slot = cast.slotLevel {
            let maximum = sheet.spellSlotMaximums[slot - 1]
            try roster.update(id: characterID) { try $0.spendSpellSlot(level: slot, maximum: maximum) }
            persist(characterID)
            slotsLeft = self.sheet(for: characterID, campaignCode: campaignCode)?.spellSlotsLeft(atLevel: slot)
        }
        let text = cast.roll(mode: mode, using: diceRoller).chatText(characterName: sheet.character.name, slotsLeft: slotsLeft)
        return await post(text, campaign: playedCampaign(for: characterID, code: campaignCode))
    }

    /// Gives back a spell slot (for a mis-tap).
    func restoreSpellSlot(level: Int, for characterID: PlayerCharacter.ID) {
        updateCharacter(characterID) { $0.restoreSpellSlot(level: level) }
    }

    /// Uses an ability with limited uses (Breath Weapon, Sorcery Points), rolls any dice in its detail,
    /// and posts it in the party chat. Throws, spending nothing, when no uses are left.
    func useAbility(_ resourceID: CharacterResource.ID, characterID: PlayerCharacter.ID,
                    campaignCode: String? = nil) async throws -> ActionOutcome {
        guard let character = character(id: characterID) else { throw CharacterError.characterNotFound }
        let used = try roster.update(id: characterID) { try $0.spendResource(resourceID) }
        persist(characterID)
        let text = used.useText(characterName: character.name, remaining: used.remaining, roller: diceRoller)
        return await post(text, campaign: playedCampaign(for: characterID, code: campaignCode))
    }

    /// Posts a roll in the party chat, when the character is in a campaign.
    private func post(_ text: String, campaign: Campaign?) async -> ActionOutcome {
        guard let code = campaign?.joinCode, let latest = campaigns.campaign(code: code) else {
            return ActionOutcome(text: text, postedTo: nil, problem: nil)
        }
        do {
            try await chat.send(text, in: .party, campaign: latest, as: campaigns.me)
            return ActionOutcome(text: text, postedTo: latest.name, problem: nil)
        } catch {
            return ActionOutcome(text: text, postedTo: nil,
                                 problem: "Couldn't post this in the party chat: \(error.localizedDescription)")
        }
    }
}

/// A sheet read from a PDF, waiting to be reviewed.
struct PendingSheetImport: Identifiable {
    let id = UUID()
    var result: SheetImport
}
