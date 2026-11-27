import Foundation

/// Where the creator's item edits are saved so every player sees them.
/// The app uses the CloudKit public database; tests and previews use the in-memory store.
public protocol ItemOverrideStore: Sendable {
    func loadOverrides() async throws -> [EquipmentItem]
    func save(_ item: EquipmentItem) async throws
    func remove(itemID: String) async throws
}

/// Whether the signed-in iCloud user may edit library items.
public struct CreatorStatus: Equatable, Sendable {
    public var isCreator: Bool
    /// The iCloud user record name, shown so the creator can be added to the Creator list.
    public var userID: String?
    /// Why we couldn't check, e.g. "Sign in to iCloud".
    public var problem: String?

    public init(isCreator: Bool, userID: String? = nil, problem: String? = nil) {
        self.isCreator = isCreator
        self.userID = userID
        self.problem = problem
    }

    public static let unknown = CreatorStatus(isCreator: false)
}

public protocol CreatorAccess: Sendable {
    func currentStatus() async -> CreatorStatus
}

/// Keeps edits in memory. Used by tests, previews and UI tests.
public actor InMemoryItemOverrideStore: ItemOverrideStore {
    private var stored: [String: EquipmentItem]
    public private(set) var saveCount = 0

    public init(overrides: [EquipmentItem] = []) {
        stored = Dictionary(overrides.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func loadOverrides() async throws -> [EquipmentItem] {
        stored.values.sorted { $0.id < $1.id }
    }

    public func save(_ item: EquipmentItem) async throws {
        stored[item.id] = item
        saveCount += 1
    }

    public func remove(itemID: String) async throws {
        stored[itemID] = nil
    }
}

public struct FixedCreatorAccess: CreatorAccess {
    public let status: CreatorStatus

    public init(_ status: CreatorStatus) {
        self.status = status
    }

    public init(isCreator: Bool) {
        self.status = CreatorStatus(isCreator: isCreator, userID: isCreator ? "_creator" : "_player")
    }

    public func currentStatus() async -> CreatorStatus { status }
}
