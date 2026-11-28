import Foundation
import Observation

/// Where the creator's creatures (new ones and edits of SRD ones) are saved so every player sees them.
/// The app uses the CloudKit public database; tests and previews use the in-memory store.
public protocol CreatureStore: Sendable {
    func loadCreatures() async throws -> [Creature]
    func save(_ creature: Creature) async throws
    func remove(creatureID: String) async throws
}

/// Keeps the creator's creatures in memory. Used by tests, previews, UI tests and builds without iCloud.
public actor InMemoryCreatureStore: CreatureStore {
    private var stored: [String: Creature]
    public private(set) var saveCount = 0

    public init(creatures: [Creature] = []) {
        stored = Dictionary(creatures.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func loadCreatures() async throws -> [Creature] {
        stored.values.sorted { $0.id < $1.id }
    }

    public func save(_ creature: Creature) async throws {
        stored[creature.id] = creature
        saveCount += 1
    }

    public func remove(creatureID: String) async throws {
        stored[creatureID] = nil
    }
}

/// State behind Library > Creatures: the SRD creatures, the creator's additions and edits, and who can edit.
/// Uses the same creator list as Library > Items.
@MainActor
@Observable
public final class CreatureLibrary {
    public private(set) var catalog: CreatureCatalog
    public private(set) var creatorStatus: CreatorStatus = .unknown
    public private(set) var isLoading = false
    /// The last sync problem, shown as a banner. Built-in creatures still show when this is set.
    public private(set) var syncError: String?

    private let store: CreatureStore
    private let creatorAccess: CreatorAccess

    public init(baseCreatures: [Creature], store: CreatureStore, creatorAccess: CreatorAccess) {
        self.catalog = CreatureCatalog(baseCreatures: baseCreatures)
        self.store = store
        self.creatorAccess = creatorAccess
    }

    public var isCreator: Bool { creatorStatus.isCreator }

    /// Fetches the creator's creatures and checks whether the current user is a creator.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        creatorStatus = await creatorAccess.currentStatus()
        do {
            catalog.replaceEntries(try await store.loadCreatures())
            syncError = nil
        } catch {
            syncError = "Couldn't load the creator's creatures. Showing the built-in list."
        }
    }

    /// Saves a new creature or an edit. Throws a validation error, or `CreatureLibraryError`.
    @discardableResult
    public func save(_ edited: Creature) async throws -> Creature {
        guard isCreator else { throw CreatureLibraryError.notCreator }
        let original = catalog.original(id: edited.id)
        guard original != nil || edited.isCustom else { throw CreatureLibraryError.unknownCreature }
        let creature = try CreatureValidator.validated(edited)
        do {
            if creature == original {
                try await store.remove(creatureID: creature.id)
                catalog.remove(id: creature.id)
            } else {
                try await store.save(creature)
                catalog.apply(creature)
            }
        } catch {
            throw CreatureLibraryError.saveFailed
        }
        return creature
    }

    /// Puts an SRD creature back to its built-in values, or deletes one the creator added.
    public func remove(id: String) async throws {
        guard isCreator else { throw CreatureLibraryError.notCreator }
        do {
            try await store.remove(creatureID: id)
        } catch {
            throw CreatureLibraryError.saveFailed
        }
        catalog.remove(id: id)
    }
}

public enum CreatureLibraryError: Error, Equatable {
    case notCreator
    case unknownCreature
    case saveFailed
}

extension CreatureLibraryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notCreator: return "Only the app's creator can add or edit creatures."
        case .unknownCreature: return "That creature isn't in the library."
        case .saveFailed: return "Couldn't save to iCloud. Check your connection and try again."
        }
    }
}
