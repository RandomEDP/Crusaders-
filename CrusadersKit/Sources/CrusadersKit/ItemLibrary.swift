import Foundation
import Observation

/// State behind Library > Items: the catalogue, the creator's edits, and whether this user can edit.
@MainActor
@Observable
public final class ItemLibrary {
    public private(set) var catalog: ItemCatalog
    public private(set) var creatorStatus: CreatorStatus = .unknown
    public private(set) var isLoading = false
    /// The last sync problem, shown as a banner. Built-in items still show when this is set.
    public private(set) var syncError: String?

    private let store: ItemOverrideStore
    private let creatorAccess: CreatorAccess

    public init(baseItems: [EquipmentItem], store: ItemOverrideStore, creatorAccess: CreatorAccess) {
        self.catalog = ItemCatalog(baseItems: baseItems)
        self.store = store
        self.creatorAccess = creatorAccess
    }

    public var isCreator: Bool { creatorStatus.isCreator }

    /// Fetches the creator's edits and checks whether the current user is a creator.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        creatorStatus = await creatorAccess.currentStatus()
        do {
            catalog.replaceOverrides(try await store.loadOverrides())
            syncError = nil
        } catch {
            syncError = "Couldn't load the latest item edits. Showing the built-in list."
        }
    }

    /// Saves a creator edit. Throws a validation error, or `ItemLibraryError` if the user can't edit.
    @discardableResult
    public func save(_ edited: EquipmentItem) async throws -> EquipmentItem {
        guard isCreator else { throw ItemLibraryError.notCreator }
        guard catalog.original(id: edited.id) != nil else { throw ItemLibraryError.unknownItem }
        let item = try ItemValidator.validated(edited)
        do {
            if item == catalog.original(id: item.id) {
                try await store.remove(itemID: item.id)
                catalog.revert(id: item.id)
            } else {
                try await store.save(item)
                catalog.applyEdit(item)
            }
        } catch {
            throw ItemLibraryError.saveFailed
        }
        return item
    }

    /// Puts an item back to its built-in SRD values.
    public func revert(id: String) async throws {
        guard isCreator else { throw ItemLibraryError.notCreator }
        do {
            try await store.remove(itemID: id)
        } catch {
            throw ItemLibraryError.saveFailed
        }
        catalog.revert(id: id)
    }
}

public enum ItemLibraryError: Error, Equatable {
    case notCreator
    case unknownItem
    case saveFailed
}

extension ItemLibraryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notCreator: return "Only the app's creator can edit items."
        case .unknownItem: return "That item isn't in the library."
        case .saveFailed: return "Couldn't save to iCloud. Check your connection and try again."
        }
    }
}
